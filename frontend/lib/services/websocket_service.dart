// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../models/order_model.dart';
import '../services/session_service.dart';
import '../models/session_state.dart';
import '../services/order_service_v2.dart';
import '../services/restaurant_availability_service.dart';
import '../services/business_status_cache.dart';
import '../config/api_config.dart';

class WebSocketService extends ChangeNotifier with WidgetsBindingObserver {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  static WebSocketService get instance => _instance;
  WebSocketService._internal() {
    WidgetsBinding.instance.addObserver(this);
    _setupSessionListener(); // ✅ Re-enabled
    _startSubscriptionMonitoring();
  }

  // WebSocket configuration - Correct WizzUser endpoint  
  static String get _baseWsUrl {
    final url = ApiConfig.webSocketUrl;
    if (url.isEmpty) {
      throw StateError('Missing WEBSOCKET_URL (dart-define)');
    }
    return url;
  }
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  bool _authReconnectPending = false;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;
  StreamSubscription<SessionState>? _sessionSubscription;
  
  // Track last session state to prevent loops
  SessionState? _lastSessionState;
  
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const Duration _heartbeatInterval = Duration(seconds: 15); // تقليل فترة heartbeat
  
  // ✅ NEW: Flag to prevent multiple simultaneous connection attempts
  bool _connectionInProgress = false;

  final Map<String, StreamController<OrderModel>> _orderStreams = {};
  
  // StreamController for business status updates
  final Map<String, StreamController<Map<String, dynamic>>> _businessStatusStreams = {};
  
  // StreamController for connection status
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  // Callback for business status updates
  Function(String businessId, bool isBusy, String status)? onBusinessStatusUpdate;

  // ✨ NEW: Callback for working hours updates
  Function(String businessId, String weekday, Map<String, dynamic> workingHours)? onWorkingHoursUpdate;
  
  // ✨ NEW: Callback for comprehensive business updates (status + working hours)
  Function(String businessId, Map<String, dynamic> updateData)? onBusinessUpdate;

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  Stream<bool> get connectionStream => _connectionController.stream;
  
  // Getter for testing - allows verification of reconnection state
  bool get shouldReconnect => _shouldReconnect;

  /// Helper method to get platform safely across all platforms
  String _getPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
      return 'unknown';
    } catch (e) {
      return 'web'; // fallback للويب
    }
  }

  /// الحصول على Device ID مستقر للجهاز
  Future<String> _getStableDeviceId(String platform) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const deviceIdKey = 'stable_device_id';
      
      String? existingDeviceId = prefs.getString(deviceIdKey);
      
      if (existingDeviceId != null && existingDeviceId.isNotEmpty) {
        debugPrint('WebSocket: استخدام Device ID موجود: $existingDeviceId');
        return existingDeviceId;
      }
      
      // إنشاء Device ID جديد مستقر
      final stableDeviceId = 'flutter_${platform}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(deviceIdKey, stableDeviceId);
      
      debugPrint('WebSocket: إنشاء Device ID جديد مستقر: $stableDeviceId');
      return stableDeviceId;
      
    } catch (e) {
      debugPrint('WebSocket: خطأ في الحصول على Device ID مستقر: $e');
      // fallback إلى Device ID مؤقت
      return 'flutter_${platform}_temp_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// الاتصال بخدمة WebSocket للمستخدمين الضيوف باستخدام Guest Token
  /// هذه الدالة تسمح للمستخدمين الضيوف بالاتصال بـ WebSocket لتلقي التحديثات الفورية
  Future<void> connectWithGuestToken(String guestToken, {String? orderId}) async {
    // إذا كان متصل بالفعل، فقط اشترك في الطلب إذا تم تمرير orderId
    if (_isConnected) {
      debugPrint('WebSocket: متصل بالفعل كضيف، اشتراك في الطلب: $orderId');
      if (orderId != null) {
        subscribeToOrder(orderId);
      }
      return;
    }
    
    // إذا كان يحاول الاتصال، انتظر
    if (_isConnecting) {
      debugPrint('WebSocket: اتصال ضيف قيد التقدم، انتظار...');
      return;
    }

    try {
      _isConnecting = true;
      notifyListeners();

      debugPrint('WebSocket: 🏃‍♂️ بدء اتصال ضيف جديد باستخدام Guest Token...');
      
      // تنظيف أي اتصال سابق
      await _cleanupConnection();

      // إعداد معلومات الجهاز والتطبيق بطريقة آمنة للويب
      String platform = _getPlatform();
      const appVersion = '1.0.0';
      final deviceId = await _getStableDeviceId(platform);

      // إنشاء URL الاتصال مع Guest Token
      final queryParams = <String, String>{
        'guestToken': guestToken,
        'userType': 'guest',
        'platform': platform,
        'appVersion': appVersion,
        'deviceId': deviceId,
      };
      
      // إضافة معرف الطلب إذا تم تمريره
      if (orderId != null) {
        queryParams['orderId'] = orderId;
      }
      
      // 🔧 FIX: Build query string manually to preserve wss:// scheme
      final queryString = queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final wsUrl = '$_baseWsUrl?$queryString';
      
      debugPrint('WebSocket: محاولة الاتصال كضيف بـ $wsUrl');

      // إنشاء قناة WebSocket مع معالجة أفضل للأخطاء
      debugPrint('WebSocket: إنشاء WebSocketChannel للضيف...');
      
      try {
        _channel = WebSocketChannel.connect(
          Uri.parse(wsUrl),
          protocols: null, // Explicitly set to null for simplicity
        );
        
        debugPrint('WebSocket: تم إنشاء WebSocketChannel للضيف بنجاح، بدء الاستماع...');
        
        // Send a test message immediately to verify connection
        Future.delayed(Duration(seconds: 1), () {
          if (_channel != null && !_isConnected) {
            try {
              _channel!.sink.add('{"type":"ping","userType":"guest","guestToken":"$guestToken","timestamp":"${DateTime.now().toIso8601String()}"}');
              debugPrint('WebSocket: تم إرسال ping للضيف للتحقق من الاتصال');
            } catch (e) {
              debugPrint('WebSocket: فشل إرسال ping للضيف: $e');
            }
          }
        });
        
      } catch (e) {
        debugPrint('WebSocket: خطأ في إنشاء WebSocketChannel للضيف: $e');
        _handleConnectionFailure('Failed to create WebSocket channel for guest: $e');
        return;
      }

      // الاستماع للرسائل مع timeout أطول للاتصال
      _connectionTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_isConnecting) {
          debugPrint('WebSocket: انتهت مهلة الاتصال للضيف (30 ثانية)');
          _handleConnectionFailure('Guest connection timeout after 30 seconds');
        }
      });

      debugPrint('WebSocket: بدء الاستماع للرسائل للضيف...');
      _subscription = _channel!.stream.listen(
        (message) {
          debugPrint('WebSocket: تم استلام رسالة للضيف: ${message.toString().substring(0, message.toString().length > 100 ? 100 : message.toString().length)}...');
          _connectionTimeoutTimer?.cancel();
          if (!_isConnected) {
            _isConnected = true;
            _isConnecting = false;
            _reconnectAttempts = 0;
            debugPrint('WebSocket: ✅ تم الاتصال بنجاح للضيف');
            _connectionController.add(true); // Broadcast connection status
            _startHeartbeat();
            notifyListeners();
          }
          _onMessage(message);
        },
        onError: (error) {
          debugPrint('WebSocket: ❌ خطأ في الاتصال للضيف: $error');
          debugPrint('WebSocket: نوع الخطأ للضيف: ${error.runtimeType}');
          _connectionTimeoutTimer?.cancel();
          _handleConnectionFailure(error.toString());
        },
        onDone: () {
          debugPrint('WebSocket: تم إغلاق الاتصال للضيف من الخادم');
          _connectionTimeoutTimer?.cancel();
          _onDisconnected();
        },
      );

    } catch (e) {
      debugPrint('WebSocket: خطأ في إنشاء الاتصال للضيف: $e');
      _handleConnectionFailure(e.toString());
    }
  }

  /// الاتصال بخدمة WebSocket لتتبع طلب معين
  Future<void> connectForOrder(String orderId) async {
    // إذا كان متصل بالفعل، فقط اشترك في الطلب
    if (_isConnected) {
      debugPrint('WebSocket: متصل بالفعل، اشتراك في طلب: $orderId');
      subscribeToOrder(orderId);
      return;
    }
    
    // إذا كان يحاول الاتصال، انتظر
    if (_isConnecting) {
      debugPrint('WebSocket: اتصال قيد التقدم، انتظار...');
      return;
    }

    try {
      _isConnecting = true;
      notifyListeners();

      // محاولة الحصول على معرف المستخدم و JWT Token
      String? userId;
      String? token;
      try {
        final sessionService = SessionService.instance;
        userId = sessionService.currentUserId;
        // 🔧 إصلاح: استخدام idToken بدلاً من accessToken للحصول على معرف المستخدم
        token = sessionService.idToken;
        debugPrint('WebSocket: معرف المستخدم: ${userId ?? "غير متاح"}');
        debugPrint('WebSocket: ID Token متاح: ${token != null ? "نعم" : "لا"}');
      } catch (e) {
        debugPrint('WebSocket: لا يمكن الحصول على بيانات المصادقة: $e');
      }

      // إعداد معلومات الجهاز والتطبيق بطريقة آمنة للويب
      String platform = _getPlatform();
      const appVersion = '1.0.0';
      final deviceId = await _getStableDeviceId(platform);

      // إنشاء URL الاتصال مع JWT Token أو معلومات إضافية
      final queryParams = <String, String>{
        'orderId': orderId,
        'platform': platform,
        'appVersion': appVersion,
        'deviceId': deviceId,
      };
      
      // استخدام ID Token إذا كان متاحاً (للمستخدمين المسجلين)
      if (token != null && token.isNotEmpty && token != 'temp_token') {
        queryParams['token'] = token;
        debugPrint('WebSocket: ✅ سيتم استخدام ID Token لتتبع الطلب');
        // 🔧 إصلاح: لا ترسل userId عند وجود token، دع Backend يستخرجه من Token
      } else {
        // للضيوف: أرسل userId بصيغة GUEST# + deviceId
        queryParams['userId'] = 'GUEST#$deviceId';
        queryParams['userType'] = 'guest';
        queryParams['entityType'] = 'guest';
        debugPrint('WebSocket: 👤 اتصال كضيف مع userId: GUEST#$deviceId');
      }
      
      // 🔧 FIX: Build query string manually to preserve wss:// scheme
      final queryString = queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final wsUrl = '$_baseWsUrl?$queryString';
      
      debugPrint('WebSocket: محاولة الاتصال لتتبع الطلب بـ $wsUrl');

      // إنشاء قناة WebSocket مع معالجة أفضل للأخطاء
      debugPrint('WebSocket: إنشاء WebSocketChannel لتتبع الطلب...');
      
      try {
        _channel = IOWebSocketChannel.connect(
          wsUrl, // Use wsUrl string directly, not Uri.parse()
        );
        
        debugPrint('WebSocket: تم إنشاء WebSocketChannel لتتبع الطلب بنجاح، بدء الاستماع...');
        
        // Send a test message immediately to verify connection
        Future.delayed(Duration(seconds: 1), () {
          if (_channel != null && !_isConnected) {
            try {
              _channel!.sink.add('{"type":"ping","orderId":"$orderId","timestamp":"${DateTime.now().toIso8601String()}"}');
              debugPrint('WebSocket: تم إرسال ping لتتبع الطلب للتحقق من الاتصال');
            } catch (e) {
              debugPrint('WebSocket: فشل إرسال ping لتتبع الطلب: $e');
            }
          }
        });
        
      } catch (e) {
        debugPrint('WebSocket: خطأ في إنشاء WebSocketChannel لتتبع الطلب: $e');
        _handleConnectionFailure('Failed to create WebSocket channel for order tracking: $e');
        return;
      }

      // الاستماع للرسائل مع timeout أطول للاتصال
      _connectionTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_isConnecting) {
          debugPrint('WebSocket: انتهت مهلة الاتصال لتتبع الطلب (30 ثانية)');
          // 🔧 إصلاح: لا نُعيد المحاولة عند timeout - نترك OrderTracking يعمل بـ Polling
          _isConnecting = false;
          _reconnectAttempts = 0;
          notifyListeners();
          debugPrint('WebSocket: ✅ تم إلغاء إعادة المحاولة - OrderTracking سيعمل بـ Polling');
        }
      });

      debugPrint('WebSocket: بدء الاستماع للرسائل لتتبع الطلب...');
      _subscription = _channel!.stream.listen(
        (message) {
          debugPrint('WebSocket: تم استلام رسالة لتتبع الطلب: ${message.toString().substring(0, message.toString().length > 100 ? 100 : message.toString().length)}...');
          _connectionTimeoutTimer?.cancel();
          if (!_isConnected) {
            _isConnected = true;
            _isConnecting = false;
            _reconnectAttempts = 0;
            debugPrint('WebSocket: ✅ تم الاتصال بنجاح لتتبع الطلب $orderId');
            _connectionController.add(true); // Broadcast connection status
            _startHeartbeat();
            notifyListeners();
          }
          _onMessage(message);
        },
        onError: (error) {
          debugPrint('WebSocket: ❌ خطأ في الاتصال لتتبع الطلب: $error');
          debugPrint('WebSocket: نوع الخطأ لتتبع الطلب: ${error.runtimeType}');
          _connectionTimeoutTimer?.cancel();
          _handleConnectionFailure(error.toString());
        },
        onDone: () {
          debugPrint('WebSocket: تم إغلاق الاتصال لتتبع الطلب من الخادم');
          _connectionTimeoutTimer?.cancel();
          _onDisconnected();
        },
      );

    } catch (e) {
      debugPrint('WebSocket: خطأ في إنشاء الاتصال: $e');
      _handleConnectionFailure(e.toString());
    }
  }

  /// الاتصال بخدمة WebSocket
  /// ⛔ هذه الطريقة معطلة - يجب استخدام connectForOrder(orderId) فقط
  Future<void> connect() async {
    debugPrint('⛔ WebSocket: استدعاء connect() مرفوض!');
    debugPrint('⛔ WebSocket: يجب استخدام connectForOrder(orderId) للاتصال');
    debugPrint('⛔ WebSocket: الاتصال بدون orderId غير مسموح');
    return;
  }

  /// إعادة الاشتراك في جميع الاشتراكات الموجودة عند إعادة الاتصال
  void _resubscribeToExistingSubscriptions() {
    try {
      debugPrint('WebSocket: إعادة إعداد الاشتراكات الموجودة...');
      
      // إعادة الاشتراك في تحديثات المطاعم
      final businessIds = _businessStatusStreams.keys.toList();
      for (final businessId in businessIds) {
        if (!_businessStatusStreams[businessId]!.isClosed) {
          debugPrint('WebSocket: 🔄 إعادة اشتراك في المطعم: $businessId');
          _sendMessage({
            'type': 'subscribe',
            'action': 'subscribe',
            'businessId': businessId,
            'business_id': businessId,
            'timestamp': DateTime.now().toIso8601String(),
          });
        }
      }
      
      // إعادة الاشتراك في تحديثات الطلبات
      final orderIds = _orderStreams.keys.toList();
      for (final orderId in orderIds) {
        if (!_orderStreams[orderId]!.isClosed) {
          debugPrint('WebSocket: إعادة اشتراك في الطلب: $orderId');
          _sendMessage({
            'type': 'subscribe_order',
            'order_id': orderId,
          });
        }
      }
      
      debugPrint('WebSocket: تم إعادة إعداد ${businessIds.length} اشتراك مطعم و ${orderIds.length} اشتراك طلب');
    } catch (e) {
      debugPrint('WebSocket: خطأ في إعادة إعداد الاشتراكات: $e');
    }
  }

  /// 🆕 إعداد مستمع لتغييرات الجلسة
  void _setupSessionListener() {
    try {
      _sessionSubscription = SessionService.instance.sessionStateStream.listen(_onSessionChanged);
      debugPrint('WebSocket: ✅ تم إعداد مستمع تغييرات الجلسة');
    } catch (e) {
      debugPrint('WebSocket: ❌ خطأ في إعداد مستمع الجلسة: $e');
    }
  }

  /// معالجة تغييرات الجلسة
  void _onSessionChanged(SessionState newState) {
    debugPrint('WebSocket: 🔄 تغيير في حالة الجلسة: ${newState.runtimeType}');
    
    // 🚨 إصلاح فوري: منع حلقة لا نهائية بإضافة debouncing
    if (_isConnecting) {
      debugPrint('WebSocket: ⚠️ تجاهل تغيير الجلسة - اتصال قيد التقدم');
      return;
    }
    
    // منع التعامل مع نفس حالة الجلسة مرتين متتاليتين
    if (_lastSessionState != null && _lastSessionState.runtimeType == newState.runtimeType) {
      debugPrint('WebSocket: ⚠️ تجاهل تكرار نفس حالة الجلسة: ${newState.runtimeType}');
      return;
    }
    
    _lastSessionState = newState;
    
    if (newState is SessionActive) {
      // المستخدم سجل دخوله - لكن لا نعيد الاتصال إذا كان متصل بالفعل
      if (_isConnected) {
        debugPrint('WebSocket: ✅ متصل بالفعل، تجاهل إعادة الاتصال');
        return;
      }
      debugPrint('WebSocket: 👤 تسجيل دخول مستخدم - إعادة تفعيل الاتصال');
      _handleUserLogin(newState.userData);
      
    } else if (newState is GuestSession) {
      // المستخدم أصبح ضيف - لا نحتاج WebSocket للضيوف
      debugPrint('WebSocket: 👤 تحويل إلى ضيف - قطع الاتصال');
      if (_isConnected) {
        disconnect();
      }
      
    } else if (newState is SessionInitial) {
      // تم تسجيل الخروج أو حالة أولية - قطع الاتصال
      debugPrint('WebSocket: 🚪 حالة أولية - قطع الاتصال');
      if (_isConnected) {
        disconnect();
      }
    }
  }

  /// معالجة تسجيل دخول المستخدم
  void _handleUserLogin(Map<String, dynamic> userData) {
    // قطع الاتصال الحالي إن وجد
    if (_isConnected) {
      debugPrint('WebSocket: 🔄 قطع الاتصال الحالي لإعادة الاتصال بمعرف المستخدم الجديد');
      disconnect();
    }
    
    // إعادة تفعيل إعادة الاتصال مع معرف المستخدم الجديد
    enableReconnection();
    
    // 🚨 FIX: عدم الاتصال تلقائياً - سيتم الاتصال فقط عند تتبع طلب
    // السبب: الاتصال التلقائي كان يحدث بدون orderId ويستبدل الاتصال الصحيح
    debugPrint('WebSocket: 👤 تم تسجيل الدخول - جاهز للاتصال عند الحاجة');
    // REMOVED: connect() call that was causing duplicate connections
  }
  
  /// 🔧 FIX: تفعيل إعادة الاتصال
  void enableReconnection() {
    debugPrint('WebSocket: ♻️ تفعيل إعادة الاتصال');
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    notifyListeners();
  }



  /// تنظيف الاتصال السابق
  Future<void> _cleanupConnection() async {
    try {
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = null;
      
      if (_subscription != null) {
        await _subscription!.cancel();
        _subscription = null;
      }
      
      if (_channel != null) {
        await _channel!.sink.close();
        _channel = null;
      }
      
      debugPrint('WebSocket: تم تنظيف الاتصال السابق');
    } catch (e) {
      debugPrint('WebSocket: خطأ في تنظيف الاتصال: $e');
    }
  }

  /// قطع الاتصال
  Future<void> disconnect() async {
    debugPrint('WebSocket: قطع الاتصال');
    
    _shouldReconnect = false;
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false); // Broadcast disconnection status

    _stopHeartbeat();
    _stopReconnectTimer();
    _connectionTimeoutTimer?.cancel();

    await _subscription?.cancel();
    
    // 🔧 إصلاح: إغلاق القناة بشكل صريح مع status code
    // لضمان أن API Gateway يحذف connectionId من جدوله
    try {
      await _channel?.sink.close(1000, 'Normal closure'); // 1000 = normal closure
      debugPrint('WebSocket: ✅ تم إغلاق القناة بشكل صريح');
    } catch (e) {
      debugPrint('WebSocket: ⚠️ خطأ في إغلاق القناة: $e');
    }

    _subscription = null;
    _channel = null;
    _connectionTimeoutTimer = null;

    // إغلاق جميع streams الطلبات
    for (final controller in _orderStreams.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _orderStreams.clear();

    // إغلاق جميع streams المطاعم
    for (final controller in _businessStatusStreams.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _businessStatusStreams.clear();
    
    // 🔧 تأخير قصير للتأكد من إتمام الإغلاق على مستوى API Gateway
    await Future.delayed(Duration(milliseconds: 1000));
    debugPrint('WebSocket: ⏳ تم الانتظار لضمان تنظيف API Gateway');

    notifyListeners();
  }

  /// الاستماع لتحديثات حالة مطعم معين
  Stream<Map<String, dynamic>> subscribeToBusinessStatus(String businessId) {
    // إذا كان الاشتراك موجود ومغلق، قم بإزالته
    if (_businessStatusStreams.containsKey(businessId) && 
        _businessStatusStreams[businessId]!.isClosed) {
      _businessStatusStreams.remove(businessId);
    }
    
    if (_businessStatusStreams.containsKey(businessId)) {
      debugPrint('WebSocket: استخدام اشتراك موجود للمطعم: $businessId');
      return _businessStatusStreams[businessId]!.stream;
    }

    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _businessStatusStreams[businessId] = controller;

    // 🚨 FIX: عدم إرسال رسالة الاشتراك إذا لم يكن متصل
    // الاشتراكات في تحديثات المطاعم لا تحتاج WebSocket - يمكن استخدام Polling
    // إرسال رسالة فقط إذا كان هناك اتصال WebSocket نشط بالفعل
    if (_isConnected && _channel != null) {
      _sendMessage({
        'type': 'subscribe',
        'action': 'subscribe',
        'businessId': businessId,
        'business_id': businessId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('WebSocket: ✅ تم إرسال طلب اشتراك للمطعم: $businessId');
    } else {
      debugPrint('WebSocket: ⚠️ لا يوجد اتصال WebSocket - الاشتراك في Polling فقط');
    }
    
    debugPrint('WebSocket: ✅ تم إنشاء stream للاشتراك في المطعم: $businessId');
    
    // مراقبة إغلاق الاشتراك وإعادة الاشتراك عند الحاجة
    controller.onCancel = () {
      debugPrint('WebSocket: تم إلغاء اشتراك المطعم: $businessId');
    };
    
    return controller.stream;
  }

  /// إلغاء الاستماع لتحديثات مطعم معين
  void unsubscribeFromBusinessStatus(String businessId) {
    if (_businessStatusStreams.containsKey(businessId)) {
      _businessStatusStreams[businessId]?.close();
      _businessStatusStreams.remove(businessId);

      // إرسال طلب إلغاء الاشتراك
      _sendMessage({
        'type': 'unsubscribe',
        'action': 'unsubscribe',
        'businessId': businessId,
        'business_id': businessId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      debugPrint('WebSocket: ✅ تم إرسال طلب إلغاء اشتراك للمطعم: $businessId');
    }
  }

  /// الاستماع لتحديثات طلب معين
  Stream<OrderModel> subscribeToOrder(String orderId) {
    debugPrint('WebSocket: 🔔 طلب الاشتراك in تحديثات الطلب: $orderId');
    
    if (_orderStreams.containsKey(orderId)) {
      debugPrint('WebSocket: ✅ يوجد اشتراك موجود للطلب: $orderId');
      return _orderStreams[orderId]!.stream;
    }

    final controller = StreamController<OrderModel>.broadcast();
    _orderStreams[orderId] = controller;

    // 🔧 إرسال طلب الاشتراك المحسن مع معرف المستخدم أو guestToken
    _setupOrderSubscriptionAsync(orderId, controller);

    return controller.stream;
  }

  /// إعداد اشتراك الطلب بشكل async
  Future<void> _setupOrderSubscriptionAsync(String orderId, StreamController<OrderModel> controller) async {
    final sessionService = SessionService.instance;
    final orderServiceV2 = OrderServiceV2();
    await orderServiceV2.ensureInitialized();
    
    Map<String, dynamic> subscriptionMessage = {
      'type': 'subscribe_order',
      'action': 'subscribe_order',
      'order_id': orderId,
      'orderId': orderId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // التحقق من نوع المستخدم وإرسال البيانات المناسبة
    if (sessionService.isGuest) {
      // للضيوف: إرسال guestToken بدلاً من user_id
      final guestToken = orderServiceV2.guestToken;
      if (guestToken != null && guestToken.isNotEmpty) {
        subscriptionMessage['guestToken'] = guestToken;
        subscriptionMessage['guest_token'] = guestToken;
        debugPrint('WebSocket: 🎭 مستخدم ضيف - إرسال guestToken: $guestToken');
      } else {
        subscriptionMessage['user_id'] = 'guest';
        subscriptionMessage['userId'] = 'guest';
        debugPrint('WebSocket: ⚠️ مستخدم ضيف لكن لا يوجد guestToken');
      }
    } else {
      // للمستخدمين المسجلين: إرسال userId العادي
      final userId = sessionService.currentUserId;
      subscriptionMessage['user_id'] = userId;
      subscriptionMessage['userId'] = userId;
      debugPrint('WebSocket: 👤 مستخدم مسجل - إرسال userId: $userId');
    }

    debugPrint('WebSocket: 📤 إرسال رسالة اشتراك محسنة: $subscriptionMessage');
    _sendMessage(subscriptionMessage);

    // 🚀 طلب حالة الطلب الحالية فور الاشتراك
    Future.delayed(Duration(seconds: 1), () {
      _sendMessage({
        'type': 'get_order_status',
        'action': 'get_order_status', 
        'orderId': orderId,
        'order_id': orderId,
      });
    });
  }

  /// إلغاء الاستماع لطلب معين
  void unsubscribeFromOrder(String orderId) {
    if (_orderStreams.containsKey(orderId)) {
      _orderStreams[orderId]?.close();
      _orderStreams.remove(orderId);

      // إرسال طلب إلغاء الاشتراك
      _sendMessage({
        'type': 'unsubscribe_order',
        'order_id': orderId,
      });
    }
  }

  /// إرسال رسالة عبر WebSocket مع معالجة أفضل للأخطاء
  void _sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      try {
        final jsonMessage = jsonEncode(message);
        _channel!.sink.add(jsonMessage);
        debugPrint('WebSocket: تم إرسال رسالة: $jsonMessage');
      } catch (e) {
        debugPrint('WebSocket: خطأ في إرسال الرسالة: $e');
        // في حالة فشل الإرسال، اعتبر الاتصال مقطوع
        _handleConnectionFailure('Send failed: $e');
      }
    } else {
      debugPrint('WebSocket: لا يمكن إرسال الرسالة - الاتصال غير متاح');
      // 🚨 FIX: عدم الاتصال تلقائياً - يجب أن يكون الاتصال فقط عبر connectForOrder()
      // السبب: الاتصال بدون orderId يخلق اتصال ضيف حتى للمستخدمين المسجلين
      debugPrint('WebSocket: ✅ تم إرسال طلب اشتراك جديد للمطعم: ${message['businessId'] ?? 'unknown'}');
      // REMOVED: connect() call that was causing guest connections for registered users
    }
  }

  /// معالجة الرسائل الواردة
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      debugPrint('WebSocket: رسالة واردة: $data');

      final messageType = data['type'] as String?;
      
      // 🔧 DEBUG: Enhanced logging for order-related messages
      if (data.containsKey('orderId') || data.containsKey('order_id') || messageType?.contains('order') == true || messageType?.contains('ORDER') == true) {
        debugPrint('WebSocket: 🎯 رسالة متعلقة بالطلب مكتشفة!');
        debugPrint('WebSocket: Type: $messageType');
        debugPrint('WebSocket: OrderId: ${data['orderId'] ?? data['order_id']}');
        debugPrint('WebSocket: Status: ${data['status']}');
        debugPrint('WebSocket: Full data: $data');
      }
      
      switch (messageType) {
        case 'ping':
          // Respond to ping with pong
          _sendMessage({'type': 'pong', 'timestamp': DateTime.now().toIso8601String()});
          break;
        case 'pong':
          debugPrint('WebSocket: ✅ تم تلقي pong - الاتصال نشط');
          break;
        case 'heartbeat':
          // إرسال استجابة heartbeat
          _sendMessage({'type': 'heartbeat_response', 'timestamp': DateTime.now().toIso8601String()});
          debugPrint('WebSocket: ✅ تم تلقي heartbeat وإرسال استجابة');
          break;
        case 'heartbeat_response':
          debugPrint('WebSocket: ✅ تم تلقي استجابة heartbeat - الاتصال مستقر');
          break;
        case 'order_update':
        case 'ORDER_STATUS_UPDATE':
        case 'UPDATE_ORDER_STATUS':
        case 'order_status_update':
          debugPrint('WebSocket: 📝 معالجة تحديث الطلب - Type: $messageType');
          _handleOrderUpdate(data);
          break;
        case 'order_cancelled':
          debugPrint('WebSocket: 🚫 معالجة إشعار إلغاء الطلب');
          _handleOrderCancellation(data);
          break;
        case 'order_status_changed':
          _handleOrderStatusChange(data);
          break;
        case 'delivery_update':
          _handleDeliveryUpdate(data);
          break;
        case 'BUSINESS_STATUS_UPDATE':
        case 'business_status_update':
          // Handle both formats: direct data or nested in 'data' field
          final updateData = data.containsKey('data') ? data['data'] as Map<String, dynamic> : data;
          _handleBusinessStatusUpdate(updateData);
          break;
        case 'WORKING_HOURS_UPDATE':
        case 'working_hours_update':
          // معالجة تحديثات ساعات العمل
          final workingHoursData = data.containsKey('data') ? data['data'] as Map<String, dynamic> : data;
          _handleWorkingHoursUpdate(workingHoursData);
          break;
        case 'subscription_ack':
          _handleSubscriptionAck(data);
          break;
        case 'business_status_update_ack':
          _handleBusinessStatusUpdateAck(data);
          break;
        case 'user_orders_update':
        case 'USER_ORDERS_UPDATE':
          debugPrint('WebSocket: 🎯 معالجة تحديث طلبات المستخدم');
          _handleUserOrdersUpdate(data);
          break;
        case 'guest_orders_update': 
        case 'GUEST_ORDERS_UPDATE':
          debugPrint('WebSocket: 🎭 معالجة تحديث طلبات الضيف');
          _handleGuestOrdersUpdate(data);
          break;
        case 'auth_error':
          if (_authReconnectPending) break;
          _authReconnectPending = true;
          final orderIds = _orderStreams.keys.toList();
          unawaited(() async {
            try {
              await disconnect();
              await Future<void>.delayed(const Duration(seconds: 2));
              if (SessionService.instance.isLoggedIn && orderIds.isNotEmpty) {
                await connectForOrder(orderIds.first);
              }
            } finally { _authReconnectPending = false; }
          }());
          break;
        case 'error':
          debugPrint('WebSocket: خطأ من الخادم: ${data['message']}');
          break;
        default:
          // 🔧 FIX: معالجة شاملة لجميع رسائل تحديث الطلبات المحتملة
          bool isOrderRelated = false;
          String? orderId;
          
          // فحص شامل لكل الحقول المحتملة التي تحمل معرف الطلب
          if (data.containsKey('orderId')) {
            orderId = data['orderId'] as String?;
            isOrderRelated = true;
          } else if (data.containsKey('order_id')) {
            orderId = data['order_id'] as String?;
            isOrderRelated = true;
          } else if (data.containsKey('id') && messageType?.toLowerCase().contains('order') == true) {
            orderId = data['id'] as String?;
            isOrderRelated = true;
          }
          
          if (isOrderRelated && orderId != null) {
            // فحص إذا كان هناك معلومات حالة للطلب
            bool hasStatusInfo = data.containsKey('status') || 
                                data.containsKey('newStatus') || 
                                data.containsKey('orderStatus') ||
                                data.containsKey('state');
            
            if (hasStatusInfo) {
              debugPrint('WebSocket: 🎯 تحديث طلب مكتشف (type: $messageType) - معالجة كتحديث طلب');
              debugPrint('WebSocket: OrderId: $orderId');
              _handleOrderUpdate(data);
            } else {
              debugPrint('WebSocket: 📄 رسالة متعلقة بالطلب $orderId لكن بدون معلومات حالة: $data');
            }
          } else {
            debugPrint('WebSocket: ❓ نوع رسالة غير معروف: $messageType');
            debugPrint('WebSocket: محتوى الرسالة: $data');
          }
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة الرسالة: $e');
    }
  }

  /// معالجة إشعار إلغاء الطلب
  void _handleOrderCancellation(Map<String, dynamic> data) {
    try {
      debugPrint('WebSocket: 🚫 معالجة إشعار إلغاء الطلب: $data');
      
      final orderId = data['orderId'] as String?;
      final orderData = data['order'] as Map<String, dynamic>?;
      
      if (orderId != null) {
        debugPrint('WebSocket: الطلب الملغى: $orderId');
        
        // إشعار OrderServiceV2 بالإلغاء للتحديث الفوري للقوائم
        try {
          // تم إزالة الاستدعاء المباشر لـ OrderService حيث أن الطريقة غير موجودة
          // بدلاً من ذلك، نعتمد على stream notifications للتحديث
          debugPrint('WebSocket: تم معالجة إلغاء الطلب $orderId عبر streams');
        } catch (e) {
          debugPrint('WebSocket: خطأ في معالجة إلغاء الطلب: $e');
        }
        
        // معالجة كتحديث طلب عادي للـ streams
        _handleOrderUpdate({
          'orderId': orderId,
          'status': 'cancelled',
          'type': 'order_status_update',
          ...?orderData,
        });
        
        debugPrint('WebSocket: ✅ تم معالجة إلغاء الطلب $orderId بنجاح');
      } else {
        debugPrint('WebSocket: خطأ - معرف الطلب مفقود في إشعار الإلغاء');
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة إشعار إلغاء الطلب: $e');
    }
  }

  /// معالجة تحديث الطلب
  void _handleOrderUpdate(Map<String, dynamic> data) {
    try {
      debugPrint('WebSocket: معالجة تحديث الطلب: $data');
      
      // 🔧 FIX: Handle different WebSocket message formats
      String? orderId;
      String? status;
      String? estimatedDeliveryTime;
      Map<String, dynamic>? orderData;
      
      // 🔧 ENHANCED: Handle ALL possible WebSocket message formats comprehensively
      
      // Format 1: Direct ORDER_STATUS_UPDATE (from merchant app via WebSocket)
      if (data.containsKey('orderId') && data.containsKey('status')) {
        orderId = data['orderId'] as String?;
        status = data['status'] as String?;
        estimatedDeliveryTime = data['estimatedDeliveryTime'] as String?;
        debugPrint('WebSocket: Format 1 - Direct ORDER_STATUS_UPDATE format detected: $orderId -> $status');
      }
      // Format 2: order_update format (from DynamoDB stream processor)
      else if (data.containsKey('orderId') && data.containsKey('status') && data.containsKey('eventName')) {
        orderId = data['orderId'] as String?;
        status = data['status'] as String?;
        debugPrint('WebSocket: Format 2 - DynamoDB stream format detected: $orderId -> $status');
      }
      // Format 3: UPDATE_ORDER_STATUS from merchant app (alternative field names)
      else if (data.containsKey('order_id') && data.containsKey('status')) {
        orderId = data['order_id'] as String?;
        status = data['status'] as String?;
        debugPrint('WebSocket: Format 3 - Merchant UPDATE_ORDER_STATUS format detected: $orderId -> $status');
      }
      // Format 4: Merchant status update with merchantId field
      else if ((data.containsKey('orderId') || data.containsKey('order_id')) && 
               data.containsKey('status') && 
               (data.containsKey('merchantId') || data.containsKey('businessId'))) {
        orderId = data['orderId'] ?? data['order_id'] as String?;
        status = data['status'] as String?;
        debugPrint('WebSocket: Format 4 - Merchant business update format detected: $orderId -> $status');
      }
      // Format 5: Nested order data
      else if (data.containsKey('order')) {
        orderData = data['order'] as Map<String, dynamic>?;
        if (orderData != null) {
          orderId = orderData['orderId'] ?? orderData['id'];
          status = orderData['status'];
          estimatedDeliveryTime = orderData['estimatedDeliveryTime'];
          debugPrint('WebSocket: Format 5 - Nested order data format detected: $orderId -> $status');
        }
      }
      // Format 6: Any message with order info (broadest match)
      else {
        // Try to extract order info from any available fields
        orderId = data['orderId'] ?? data['order_id'] ?? data['id'];
        status = data['status'] ?? data['newStatus'];
        if (orderId != null && status != null) {
          debugPrint('WebSocket: Format 6 - Generic order update format detected: $orderId -> $status');
        }
      }
      
      if (orderId != null && status != null) {
        debugPrint('WebSocket: 🔄 تحديث الطلب $orderId إلى حالة: $status');
        
        // 🚀 NEW: إرسال التحديث لجميع streams المناسبة (فردي + جماعي)
        final orderStatus = OrderStatus.fromString(status);
        bool updateSent = false;
        
        try {
          // 1. تحديث stream الطلب الفردي إذا موجود
          if (_orderStreams.containsKey(orderId)) {
            debugPrint('WebSocket: جلب تفاصيل الطلب الكاملة لـ $orderId (stream فردي)');
            _fetchAndUpdateOrder(orderId, orderStatus, estimatedDeliveryTime);
            updateSent = true;
          }
          
          // 2. تحديث streams طلبات المستخدم الشاملة
          for (String streamKey in _orderStreams.keys) {
            if (streamKey.startsWith('user_orders_') || streamKey.startsWith('guest_orders_')) {
              debugPrint('WebSocket: إرسال تحديث للـ stream الشامل: $streamKey');
              _fetchAndUpdateOrderForStream(streamKey, orderId, orderStatus, estimatedDeliveryTime);
              updateSent = true;
            }
          }
          
          if (updateSent) {
            debugPrint('WebSocket: ✅ تم تحديث الطلب $orderId بنجاح في جميع streams المناسبة');
          } else {
            debugPrint('WebSocket: ⚠️ لا يوجد مستمعين للطلب $orderId في أي stream');
          }
          
        } catch (e) {
          debugPrint('WebSocket: خطأ في إنشاء OrderModel: $e');
        }
      } else {
        debugPrint('WebSocket: بيانات الطلب ناقصة - orderId: $orderId, status: $status');
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تحديث الطلب: $e');
    }
  }
  /// جلب وتحديث الطلب لـ stream معين
  Future<void> _fetchAndUpdateOrderForStream(String streamKey, String orderId, OrderStatus newStatus, String? estimatedDeliveryTime) async {
    try {
      if (!_orderStreams.containsKey(streamKey) || _orderStreams[streamKey]!.isClosed) {
        debugPrint('WebSocket: تخطي stream غير متاح: $streamKey');
        return;
      }
      
      debugPrint('WebSocket: جلب وإرسال تحديث الطلب $orderId للـ stream: $streamKey');
      
      final orderService = OrderServiceV2();
      final order = await orderService.getOrderDetails(orderId);
      
      if (order != null) {
        final updatedOrder = order.copyWith(
          status: order.status,
          estimatedDeliveryTime: order.estimatedDeliveryTime,
        );
        
        _orderStreams[streamKey]!.add(updatedOrder);
        debugPrint('WebSocket: ✅ تم إرسال تحديث الطلب $orderId للـ stream: $streamKey');
      } else {
        debugPrint('WebSocket: ❌ فشل جلب بيانات الطلب $orderId للـ stream: $streamKey');
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في تحديث stream $streamKey للطلب $orderId: $e');
    }
  }

   /// Fetch full order details and update the stream
  Future<void> _fetchAndUpdateOrder(String orderId, OrderStatus newStatus, String? estimatedDeliveryTime) async {
    try {
      debugPrint('WebSocket: 🔄 بدء جلب تفاصيل الطلب $orderId مع الحالة الجديدة: ${newStatus.arabicName}');

      // 🔧 FIX: Use OrderServiceV2 singleton instance for consistency with orders_screen
      final orderService = OrderServiceV2();
      final order = await orderService.getOrderDetails(orderId);
      
      if (order != null) {
        debugPrint('WebSocket: ✅ تم جلب بيانات الطلب $orderId بنجاح');
        
        // A fresh server read takes precedence over a delayed notification.
        final updatedOrder = order.copyWith(
          status: order.status, // Canonical read wins over a delayed notification hint
          estimatedDeliveryTime: order.estimatedDeliveryTime,
        );
        
        debugPrint('WebSocket: 📤 إرسال الطلب المحدث للمستمعين - ID: ${updatedOrder.id}, Status: ${updatedOrder.status.arabicName}');
        
        // Send the updated order to listeners with error handling
        if (_orderStreams.containsKey(orderId) && !_orderStreams[orderId]!.isClosed) {
          _orderStreams[orderId]!.add(updatedOrder);
          debugPrint('WebSocket: ✅ تم إرسال تحديث الطلب $orderId بنجاح إلى ${_orderStreams[orderId]!.hasListener ? 'مستمع نشط' : 'بدون مستمعين'}');
          
          // 🔧 FIX: Notify all listeners that WebSocket service has been updated
          notifyListeners();
        } else {
          debugPrint('WebSocket: ⚠️ لا يمكن إرسال التحديث - Stream مغلق أو غير موجود للطلب $orderId');
        }
      } else {
        debugPrint('WebSocket: ❌ فشل في جلب بيانات الطلب $orderId من OrderService');
        
        // 🚀 FALLBACK: Create minimal order with just status update if fetch fails
        debugPrint('WebSocket: 🔧 إنشاء طلب مبسط بالحالة الجديدة كبديل');
        try {
          // This would require access to minimal order data or we skip this fallback
          debugPrint('WebSocket: تخطي إنشاء طلب مبسط - يتطلب بيانات إضافية');
        } catch (e) {
          debugPrint('WebSocket: خطأ في إنشاء الطلب المبسط: $e');
        }
      }
    } catch (e) {
      debugPrint('WebSocket: ❌ خطأ عام في جلب تفاصيل الطلب $orderId: $e');
      debugPrint('WebSocket: نوع الخطأ: ${e.runtimeType}');
    }
  }

  /// معالجة تغيير حالة الطلب
  void _handleOrderStatusChange(Map<String, dynamic> data) {
    try {
      final orderId = data['order_id'] as String?;
      final statusString = data['status'] as String?;

      if (orderId != null && statusString != null) {
        final status = OrderStatus.fromString(statusString);
        
        // Handle this as a regular order update through the existing mechanism
        _handleOrderUpdate({
          'orderId': orderId,
          'status': statusString,
          'type': 'order_status_change',
        });

        debugPrint('WebSocket: تغيرت حالة الطلب $orderId إلى ${status.arabicName}');
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تغيير حالة الطلب: $e');
    }
  }

  /// معالجة تحديث التوصيل
  void _handleDeliveryUpdate(Map<String, dynamic> data) {
    try {
      final orderId = data['order_id'] as String?;
      final driverLocation = data['driver_location'] as Map<String, dynamic>?;

      if (orderId != null) {
        // يمكن إضافة معالجة تحديثات التوصيل هنا
        debugPrint('WebSocket: تحديث توصيل للطلب $orderId');
        
        if (driverLocation != null) {
          final lat = driverLocation['latitude'] as double?;
          final lng = driverLocation['longitude'] as double?;
          debugPrint('WebSocket: موقع السائق: $lat, $lng');
        }
        
        // معالجة وقت الوصول المتوقع إذا كان متوفراً
        if (data.containsKey('estimated_arrival')) {
          final estimatedArrival = data['estimated_arrival'] as String?;
          if (estimatedArrival != null) {
            debugPrint('WebSocket: وقت الوصول المتوقع: $estimatedArrival');
          }
        }
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تحديث التوصيل: $e');
    }
  }

  /// معالجة تحديث حالة المطعم
  void _handleBusinessStatusUpdate(Map<String, dynamic> data) {
    try {
      final businessId = data['businessId'] as String?;
      final businessName = data['businessName'] as String?;
      final status = data['status'] as String?;
      final statusMessage = data['statusMessage'] as String?;
      final canAcceptOrders = data['canAcceptOrders'] as bool?;
      final timestamp = data['timestamp'] as String?;
      final isBusy = data['isBusy'] as bool?;

      if (businessId != null) {
        debugPrint('WebSocket: تحديث حالة المطعم $businessId');
        debugPrint('WebSocket: الحالة الجديدة: $status');
        debugPrint('WebSocket: يمكن استقبال الطلبات: $canAcceptOrders');
        debugPrint('WebSocket: مشغول: $isBusy');
        debugPrint('WebSocket: الرسالة: $statusMessage');

        // إرسال التحديث للمستمعين المهتمين بهذا المطعم
        if (_businessStatusStreams.containsKey(businessId)) {
          final controller = _businessStatusStreams[businessId]!;
          
          // التحقق من أن controller ما زال مفتوح
          if (!controller.isClosed) {
            final updateData = {
              'businessId': businessId,
              'businessName': businessName,
              'status': status,
              'statusMessage': statusMessage,
              'canAcceptOrders': canAcceptOrders,
              'isBusy': isBusy,
              'timestamp': timestamp,
            };
            
            controller.add(updateData);
            debugPrint('WebSocket: تم إرسال تحديث حالة المطعم للمستمعين: $businessId');
          } else {
            debugPrint('WebSocket: Controller مغلق للمطعم $businessId - إزالة من القائمة');
            _businessStatusStreams.remove(businessId);
          }
        } else {
          debugPrint('WebSocket: لا يوجد مستمعين لتحديثات المطعم: $businessId');
        }

        // تشغيل callback إذا كان معرف
        if (onBusinessStatusUpdate != null) {
          final businessStatus = status ?? 'unknown';
          final businessIsBusy = isBusy ?? (canAcceptOrders == false);
          onBusinessStatusUpdate!(businessId, businessIsBusy, businessStatus);
          debugPrint('WebSocket: تم تشغيل callback لتحديث حالة المطعم');
        }
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تحديث حالة المطعم: $e');
    }
  }

  /// معالجة تحديثات ساعات العمل
  void _handleWorkingHoursUpdate(Map<String, dynamic> data) {
    try {
      final businessId = data['businessId'] as String?;
      final weekday = data['weekday'] as String?;
      final weekdayArabic = data['weekdayArabic'] as String?;
      final opening = data['opening'] as String?;
      final closing = data['closing'] as String?;
      final isClosed = data['isClosed'] as bool?;
      final isDayClosed = data['isDayClosed'] as bool?;
      final statusMessage = data['statusMessage'] as String?;
      final eventType = data['eventType'] as String?;

      if (businessId != null && weekday != null) {
        debugPrint('WebSocket: 🕐 تحديث ساعات العمل للمطعم $businessId');
        debugPrint('WebSocket: اليوم: $weekday ($weekdayArabic)');
        debugPrint('WebSocket: ساعات العمل: $opening - $closing');
        debugPrint('WebSocket: مغلق: $isClosed');
        debugPrint('WebSocket: نوع الحدث: $eventType');
        debugPrint('WebSocket: الرسالة: $statusMessage');

        // 🔥 إنشاء كائن ساعات العمل مع إعطاء أولوية عالية لـ isClosed
        final dayWorkingHours = {
          'open': (isDayClosed == true || isClosed == true) ? 'none' : (opening ?? 'none'),
          'close': (isDayClosed == true || isClosed == true) ? 'none' : (closing ?? 'none'),
          'isClosed': isClosed ?? isDayClosed ?? false,
        };

        // إنشاء تحديث شامل لحالة المطعم مع ساعات العمل الجديدة
        final businessStatusUpdate = {
          'businessId': businessId,
          'workingHoursUpdated': true,
          'workingHours': {
            weekday: dayWorkingHours,
          },
          'statusMessage': statusMessage,
          'timestamp': DateTime.now().toIso8601String(),
          
          // 🚨 إضافة معلومات إضافية مهمة للتحديث الفوري
          'eventType': eventType,
          'dayUpdated': weekday,
          'isClosed': isClosed,
          'isDayClosed': isDayClosed,
          
          // إجبار إعادة فحص حالة المطعم
          'forceStatusRecheck': true,
        };

        debugPrint('🔄 إرسال تحديث ساعات العمل شامل: $businessStatusUpdate');

        // 🔥 مسح كاش المطعم فوراً لإجبار إعادة فحص حالة التوفر
        _invalidateRestaurantCache(businessId);

        // إرسال التحديث للمستمعين المهتمين بهذا المطعم
        if (_businessStatusStreams.containsKey(businessId)) {
          final controller = _businessStatusStreams[businessId]!;
          
          // التحقق من أن controller ما زال مفتوح
          if (!controller.isClosed) {
            controller.add(businessStatusUpdate);
            debugPrint('WebSocket: ✅ تم إرسال تحديث ساعات العمل للمستمعين: $businessId');
          } else {
            debugPrint('WebSocket: Controller مغلق للمطعم $businessId - إزالة من القائمة');
            _businessStatusStreams.remove(businessId);
          }
        } else {
          debugPrint('WebSocket: ⚠️ لا يوجد مستمعين لتحديثات المطعم: $businessId');
        }

        // تشغيل callback لتحديث ساعات العمل المحدد
        if (onWorkingHoursUpdate != null) {
          onWorkingHoursUpdate!(businessId, weekday, dayWorkingHours);
          debugPrint('WebSocket: تم تشغيل callback لتحديث ساعات العمل المحدد');
        }

        // تشغيل callback شامل للتحديثات
        if (onBusinessUpdate != null) {
          onBusinessUpdate!(businessId, businessStatusUpdate);
          debugPrint('WebSocket: تم تشغيل callback التحديث الشامل');
        }

        // تشغيل callback إذا كان معرف (للتوافق مع الكود الحالي)
        if (onBusinessStatusUpdate != null) {
          // في حالة تحديث ساعات العمل، نعتبر المطعم مشغول مؤقتاً حتى يتم فحص الساعات الجديدة
          final businessIsBusy = isDayClosed == true || isClosed == true;
          onBusinessStatusUpdate!(businessId, businessIsBusy, eventType ?? 'working_hours_update');
          debugPrint('WebSocket: تم تشغيل callback لتحديث ساعات العمل');
        }
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تحديث ساعات العمل: $e');
    }
  }

  /// معالجة تأكيد الاشتراك
  void _handleSubscriptionAck(Map<String, dynamic> data) {
    try {
      final action = data['action'] as String?;
      final businessId = data['businessId'] as String?;
      final connectionId = data['connectionId'] as String?;
      final timestamp = data['timestamp'] as String?;

      debugPrint('WebSocket: ✅ تأكيد الاشتراك - Action: $action, BusinessId: $businessId');
      debugPrint('WebSocket: Connection ID: $connectionId, Timestamp: $timestamp');

      // لا نحتاج لفعل أي شيء خاص هنا، مجرد تسجيل تأكيد الاشتراك
      // هذا يمنع الرسالة من الوصول إلى default case والتسبب في إعادة اتصال غير ضرورية
      
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تأكيد الاشتراك: $e');
    }
  }

  /// معالجة تأكيد تحديث حالة المطعم
  void _handleBusinessStatusUpdateAck(Map<String, dynamic> data) {
    try {
      final businessId = data['businessId'] as String?;
      final isBusy = data['isBusy'] as bool?;
      final processed = data['processed'] as bool?;
      final timestamp = data['timestamp'] as String?;

      debugPrint('WebSocket: ✅ تأكيد تحديث حالة المطعم - BusinessId: $businessId');
      debugPrint('WebSocket: isBusy: $isBusy, Processed: $processed, Timestamp: $timestamp');

      // لا نحتاج لفعل أي شيء خاص هنا، مجرد تسجيل تأكيد التحديث
      
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تأكيد تحديث حالة المطعم: $e');
    }
  }

  /// معالجة قطع الاتصال
  void _onDisconnected() {
    debugPrint('WebSocket: تم قطع الاتصال');
    _isConnected = false;
    _connectionController.add(false); // Broadcast disconnection status
    _stopHeartbeat();
    notifyListeners();
    _handleReconnect();
  }

  /// إعادة الاتصال التلقائي
  void _handleReconnect() {
    // 🚨 إصلاح فوري: حماية مشددة ضد إعادة الاتصال المتعدد
    if (!_shouldReconnect || _reconnectAttempts >= 3) { // تقليل من 5 إلى 3
      debugPrint('WebSocket: 🛑 لن يتم إعادة الاتصال - المحاولات: $_reconnectAttempts / 3');
      return;
    }

    // تحقق من عدم وجود اتصال بالفعل
    if (_isConnected || _isConnecting) {
      debugPrint('WebSocket: ⏸️ تجاهل إعادة الاتصال - متصل بالفعل أو اتصال قيد التقدم');
      return;
    }

    _reconnectAttempts++;
    
    debugPrint('WebSocket: 🔄 محاولة إعادة الاتصال #$_reconnectAttempts');

    // 🔧 إصلاح: زيادة تأخير إعادة الاتصال تدريجياً
    final delay = Duration(seconds: 5 + (_reconnectAttempts * 3)); // 5s, 8s, 11s

    // إلغاء أي مؤقت سابق لتجنب التداخل
    _reconnectTimer?.cancel();
    
    _reconnectTimer = Timer(delay, () {
      // 🚨 FIX: عدم إعادة الاتصال تلقائياً - يجب أن يكون الاتصال فقط عبر connectForOrder()
      // السبب: إعادة الاتصال التلقائي بدون orderId يخلق اتصالات ضيف للمستخدمين المسجلين
      debugPrint('WebSocket: ⏸️ تم تخطي إعادة الاتصال التلقائي - الاتصال يجب أن يكون عبر connectForOrder() فقط');
      // REMOVED: connect() call - reconnection should only happen through connectForOrder()
    });
  }

  /// بدء heartbeat مع معالجة فشل الاستجابة المحسنة
  void _startHeartbeat() {
    _stopHeartbeat(); // إيقاف أي heartbeat سابق
    
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isConnected && _channel != null) {
        try {
          _sendMessage({
            'action': 'heartbeat',
            'type': 'heartbeat',
            'timestamp': DateTime.now().toIso8601String(),
          });
          
          // 🔧 إصلاح: إزالة timeout للـ heartbeat لأن الخادم قد لا يرد
          // بدلاً من ذلك، نعتمد على WebSocket connection state
          debugPrint('WebSocket: ✅ تم إرسال heartbeat - ${DateTime.now().toIso8601String()}');
          
        } catch (e) {
          debugPrint('WebSocket: ❌ خطأ في إرسال heartbeat: $e');
          // فقط في حالة فشل الإرسال نقطع الاتصال
          _handleConnectionFailure('Heartbeat send failed: $e');
        }
      } else {
        debugPrint('WebSocket: ⏹️ إيقاف heartbeat - الاتصال غير متاح');
        timer.cancel();
      }
    });
  }

  /// إيقاف heartbeat
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// إيقاف مؤقت إعادة الاتصال
  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// إعادة تعيين حالة إعادة الاتصال
  void resetReconnection() {
    _shouldReconnect = true;
    _reconnectAttempts = 0;
  }

  /// معالجة فشل الاتصال مع تسجيل مفصل وإعادة المحاولة الذكية
  void _handleConnectionFailure(String reason) {
    debugPrint('WebSocket: 💥 فشل الاتصال - السبب: $reason');
    debugPrint('WebSocket: الحالة الحالية - متصل: $_isConnected، يحاول الاتصال: $_isConnecting');
    
    // تحديث الحالة
    _isConnecting = false;
    if (_isConnected) {
      _isConnected = false;
      _connectionController.add(false);
      notifyListeners();
    }
    
    // فحص أنواع الأخطاء التي لا تحتاج إعادة محاولة
    if (reason.contains('403') || reason.contains('Forbidden')) {
      debugPrint('WebSocket: 🚫 خطأ مصادقة - لن يتم إعادة المحاولة');
      return;
    }
    
    if (reason.contains('1005') || reason.contains('1006')) {
      debugPrint('WebSocket: 🔚 إغلاق طبيعي للاتصال - لن يتم إعادة المحاولة');
      return;
    }
    
    // 🔧 إصلاح: عدم إعادة المحاولة عند timeout للاتصال الأول
    if (reason.contains('timeout') && _reconnectAttempts == 0) {
      debugPrint('WebSocket: ⏰ timeout للاتصال الأول - لن يتم إعادة المحاولة (OrderTracking سيعمل بـ Polling)');
      _shouldReconnect = false;
      _cleanupConnection();
      return;
    }
    
    // تنظيف الاتصال الحالي
    _cleanupConnection();
    
    // محاولة إعادة الاتصال إذا مسموح
    if (_shouldReconnect && _reconnectAttempts < 5) {
      final delaySeconds = 3 + (_reconnectAttempts * 2); // 3s, 5s, 7s, 9s, 11s
      debugPrint('WebSocket: 🔄 سيتم محاولة إعادة الاتصال بعد $delaySeconds ثواني (محاولة ${_reconnectAttempts + 1}/5)');
      _handleReconnect();
    } else {
      debugPrint('WebSocket: ❌ تجاوز الحد الأقصى لمحاولات إعادة الاتصال أو تم إيقاف إعادة الاتصال');
      _shouldReconnect = false;
      notifyListeners();
    }
  }

  /// 🆕 إيقاف إعادة الاتصال نهائياً (مفيد عند تسجيل الخروج)
  void stopReconnectionPermanently() {
    debugPrint('WebSocket: 🚫 إيقاف إعادة الاتصال نهائياً');
    _shouldReconnect = false;
    _reconnectAttempts = 999; // رقم كبير لمنع المحاولات
    _stopReconnectTimer();
    disconnect();
  }



  /// التحقق من حالة طلب معين (طلب مباشر)
  Future<void> requestOrderStatus(String orderId) async {
    _sendMessage({
      'type': 'get_order_status',
      'order_id': orderId,
    });
  }

  /// إرسال موقع المستخدم (للتوصيل)
  void updateUserLocation(double latitude, double longitude) {
    _sendMessage({
      'type': 'user_location_update',
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// 🚀 NEW: الاشتراك في جميع طلبات المستخدم المسجل
  Stream<OrderModel> subscribeToUserOrders(String userId) {
    debugPrint('🎯 WebSocket: الاشتراك في جميع طلبات المستخدم: $userId');
    
    final streamKey = 'user_orders_$userId';
    
    // إنشاء stream جديد أو استخدام الموجود
    if (!_orderStreams.containsKey(streamKey)) {
      _orderStreams[streamKey] = StreamController<OrderModel>.broadcast();
      
      // إرسال رسالة اشتراك للخادم
      _sendMessage({
        'type': 'subscribe_user_orders',
        'user_id': userId,
      });
      
      debugPrint('✅ تم إنشاء اشتراك جديد لطلبات المستخدم: $userId');
    } else {
      debugPrint('ℹ️ استخدام اشتراك موجود لطلبات المستخدم: $userId');
    }
    
    return _orderStreams[streamKey]!.stream;
  }

  /// 🚀 NEW: الاشتراك في جميع طلبات المستخدم الضيف
  Stream<OrderModel> subscribeToGuestOrders(String guestToken) {
    debugPrint('🎭 WebSocket: الاشتراك في جميع طلبات الضيف: $guestToken');
    
    final streamKey = 'guest_orders_$guestToken';
    
    // إنشاء stream جديد أو استخدام الموجود
    if (!_orderStreams.containsKey(streamKey)) {
      _orderStreams[streamKey] = StreamController<OrderModel>.broadcast();
      
      // إرسال رسالة اشتراك للخادم
      _sendMessage({
        'type': 'subscribe_guest_orders',
        'guest_token': guestToken,
      });
      
      debugPrint('✅ تم إنشاء اشتراك جديد لطلبات الضيف: $guestToken');
    } else {
      debugPrint('ℹ️ استخدام اشتراك موجود لطلبات الضيف: $guestToken');
    }
    
    return _orderStreams[streamKey]!.stream;
  }

  /// إلغاء الاشتراك في طلبات المستخدم
  void unsubscribeFromUserOrders(String userId) {
    final streamKey = 'user_orders_$userId';
    debugPrint('🗑️ WebSocket: إلغاء اشتراك طلبات المستخدم: $userId');
    
    _orderStreams[streamKey]?.close();
    _orderStreams.remove(streamKey);
    
    _sendMessage({
      'type': 'unsubscribe_user_orders',
      'user_id': userId,
    });
  }

  /// إلغاء الاشتراك في طلبات الضيف
  void unsubscribeFromGuestOrders(String guestToken) {
    final streamKey = 'guest_orders_$guestToken';
    debugPrint('🗑️ WebSocket: إلغاء اشتراك طلبات الضيف: $guestToken');
    
    _orderStreams[streamKey]?.close();
    _orderStreams.remove(streamKey);
    
    _sendMessage({
      'type': 'unsubscribe_guest_orders',
      'guest_token': guestToken,
    });
  }

  /// معالجة تحديثات طلبات المستخدم
  void _handleUserOrdersUpdate(Map<String, dynamic> data) {
    try {
      debugPrint('WebSocket: 🎯 معالجة تحديث طلبات المستخدم: $data');
      
      // استخراج معلومات الطلب من البيانات
      final orderId = data['orderId'] ?? data['order_id'] ?? data['id'];
      final userId = data['userId'] ?? data['user_id'];
      
      if (orderId != null && userId != null) {
        debugPrint('WebSocket: تحديث طلب $orderId للمستخدم $userId');
        
        // إرسال التحديث إلى stream المستخدم
        final streamKey = 'user_orders_$userId';
        if (_orderStreams.containsKey(streamKey)) {
          _handleOrderUpdate(data);
        }
        
        // أيضاً إرسال للـ stream الخاص بالطلب إذا كان موجود
        if (_orderStreams.containsKey(orderId)) {
          _handleOrderUpdate(data);
        }
      } else {
        debugPrint('WebSocket: معلومات ناقصة في تحديث طلبات المستخدم: $data');
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تحديث طلبات المستخدم: $e');
    }
  }

  /// معالجة تحديثات طلبات الضيف
  void _handleGuestOrdersUpdate(Map<String, dynamic> data) {
    try {
      debugPrint('WebSocket: 🎭 معالجة تحديث طلبات الضيف: $data');
      
      // استخراج معلومات الطلب من البيانات
      final orderId = data['orderId'] ?? data['order_id'] ?? data['id'];
      final guestToken = data['guestToken'] ?? data['guest_token'];
      
      if (orderId != null && guestToken != null) {
        debugPrint('WebSocket: تحديث طلب $orderId للضيف $guestToken');
        
        // إرسال التحديث إلى stream الضيف
        final streamKey = 'guest_orders_$guestToken';
        if (_orderStreams.containsKey(streamKey)) {
          _handleOrderUpdate(data);
        }
        
        // أيضاً إرسال للـ stream الخاص بالطلب إذا كان موجود
        if (_orderStreams.containsKey(orderId)) {
          _handleOrderUpdate(data);
        }
      } else {
        debugPrint('WebSocket: معلومات ناقصة في تحديث طلبات الضيف: $data');
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في معالجة تحديث طلبات الضيف: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _connectionController.close(); // Close the stream controller
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('WebSocket: 📱 تغيير حالة التطبيق: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        // 🔧 إصلاح: تحقق دقيق من حالة الاتصال قبل إعادة الاتصال
        debugPrint('WebSocket: 🔄 التطبيق عاد للمقدمة - فحص الاتصال...');
        // 🔧 إصلاح: لا يتم إعادة الاتصال التلقائي - الاتصال فقط عبر connectForOrder()
        debugPrint('WebSocket: ⏸️ تم تخطي إعادة الاتصال التلقائي عند العودة للمقدمة');
        debugPrint('WebSocket: ℹ️ الاتصال يجب أن يكون فقط عبر connectForOrder() مع orderId');
        break;
      case AppLifecycleState.paused:
        // 🚨 إصلاح فوري: عدم قطع الاتصال عند الذهاب للخلفية أثناء التنقل
        debugPrint('WebSocket: ⏸️ التطبيق في الخلفية - الحفاظ على الاتصال للتنقل');
        // فقط إيقاف heartbeat مؤقتاً بدلاً من قطع الاتصال
        _stopHeartbeat();
        break;
      case AppLifecycleState.inactive:
        debugPrint('WebSocket: 😴 التطبيق غير نشط - إيقاف heartbeat مؤقتاً');
        _stopHeartbeat();
        break;
      case AppLifecycleState.detached:
        // قطع الاتصال نهائياً عند إغلاق التطبيق
        debugPrint('WebSocket: 🚪 إغلاق التطبيق - قطع الاتصال نهائياً');
        _shouldReconnect = false;
        disconnect();
        break;
      case AppLifecycleState.hidden:
        // حالة جديدة في Flutter - لا نفعل شيء
        break;
    }
  }

  /// تنظيف الاشتراكات المغلقة وإعادة تهيئتها
  void _cleanupClosedSubscriptions() {
    try {
      // تنظيف اشتراكات المطاعم المغلقة
      final businessIds = _businessStatusStreams.keys.toList();
      for (final businessId in businessIds) {
        final controller = _businessStatusStreams[businessId]!;
        if (controller.isClosed) {
          debugPrint('WebSocket: إزالة اشتراك مغلق للمطعم: $businessId');
          _businessStatusStreams.remove(businessId);
        }
      }
      
      // تنظيف اشتراكات الطلبات المغلقة
      final orderIds = _orderStreams.keys.toList();
      for (final orderId in orderIds) {
        final controller = _orderStreams[orderId]!;
        if (controller.isClosed) {
          debugPrint('WebSocket: إزالة اشتراك مغلق للطلب: $orderId');
          _orderStreams.remove(orderId);
        }
      }
    } catch (e) {
      debugPrint('WebSocket: خطأ في تنظيف الاشتراكات المغلقة: $e');
    }
  }

  /// فحص دوري لحالة الاشتراكات وإعادة تفعيلها إذا لزم الأمر
  void _startSubscriptionMonitoring() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _cleanupClosedSubscriptions();
        
        // إعادة الاشتراك في الاشتراكات المفقودة إذا كان هناك طلب عليها
        _resubscribeToExistingSubscriptions();
      }
    });
  }

  /// مسح كاش المطعم فوراً عند تحديث ساعات العمل
  void _invalidateRestaurantCache(String businessId) {
    try {
      debugPrint('WebSocket: 🗑️ مسح كاش المطعم $businessId لإجبار إعادة فحص الحالة');
      
      // مسح كاش حالة المطعم
      BusinessStatusCache.clearCachedBusinessStatus(businessId);
      
      // إجبار RestaurantAvailabilityService على إعادة فحص الحالة
      RestaurantAvailabilityService.instance.invalidateBusinessCache(businessId);
      
      debugPrint('WebSocket: ✅ تم مسح كاش المطعم $businessId بنجاح');
      
    } catch (e) {
      debugPrint('WebSocket: ❌ خطأ في مسح كاش المطعم $businessId: $e');
    }
  }
}
