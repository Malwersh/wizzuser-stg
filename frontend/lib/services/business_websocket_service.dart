import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'business_status_cache.dart';
import '../config/api_config.dart';

/// خدمة WebSocket لتحديثات حالة المطاعم الفورية
class BusinessWebSocketService {
  static BusinessWebSocketService? _instance;
  static BusinessWebSocketService get instance => _instance ??= BusinessWebSocketService._();
  
  BusinessWebSocketService._();

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _reconnectDelay = Duration(seconds: 5);

  // Stream controllers لتحديثات الحالة
  final _businessStatusController = StreamController<BusinessStatusUpdate>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();

  static String get _wsEndpoint {
    final url = ApiConfig.webSocketUrl;
    if (url.isEmpty) {
      throw StateError('Missing WEBSOCKET_URL (dart-define)');
    }
    return url;
  }

  /// Stream لتحديثات حالة المطاعم
  Stream<BusinessStatusUpdate> get businessStatusUpdates => _businessStatusController.stream;
  
  /// Stream لحالة الاتصال
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  /// الحصول على حالة الاتصال
  bool get isConnected => _isConnected;

  /// الاتصال بـ WebSocket
  Future<void> connect({String? userId, String? deviceId}) async {
    if (_isConnected || _isConnecting) {
      developer.log('🔌 WebSocket: الاتصال موجود مسبقاً أو جاري');
      return;
    }

    _isConnecting = true;
    developer.log('🔌 WebSocket: بدء الاتصال بخدمة حالة المطاعم');

    try {
      // إنشاء اتصال WebSocket
      final uri = Uri.parse(_wsEndpoint);
      _channel = WebSocketChannel.connect(uri);

      // إرسال رسالة التعريف
      final authMessage = {
        'type': 'auth',
        'userType': 'customer',
        'userId': userId,
        'deviceId': deviceId,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      _channel!.sink.add(json.encode(authMessage));

      // الاستماع للرسائل
      _channel!.stream.listen(
        _handleMessage,
        onDone: _handleDisconnection,
        onError: _handleError,
      );

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStatusController.add(true);
      
      // بدء heartbeat
      _startHeartbeat();
      
      developer.log('✅ WebSocket: تم الاتصال بنجاح');

    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _connectionStatusController.add(false);
      developer.log('❌ WebSocket: فشل الاتصال - $e');
      _scheduleReconnect();
    }
  }


  /// قطع الاتصال
  Future<void> disconnect() async {
    developer.log('🔌 WebSocket: قطع الاتصال');
    
    _isConnected = false;
    _isConnecting = false;
    _reconnectAttempts = 0;
    
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    
    await _channel?.sink.close(status.goingAway);
    _channel = null;
    
    _connectionStatusController.add(false);
  }

  /// معالجة الرسائل الواردة
  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String);
      final messageType = data['type'] as String?;

      developer.log('📨 WebSocket: رسالة واردة - النوع: $messageType');

      switch (messageType) {
        case 'business_status_update':
        case 'BUSINESS_STATUS_UPDATE':
          _handleBusinessStatusUpdate(data);
          break;
        
        case 'working_hours_update':
        case 'WORKING_HOURS_UPDATE':
          _handleWorkingHoursUpdate(data);
          break;
        
        case 'pong':
          developer.log('💓 WebSocket: Pong مستلم');
          break;
          
        case 'auth_success':
          developer.log('🔐 WebSocket: تم التوثيق بنجاح');
          break;
          
        case 'error':
          developer.log('❌ WebSocket: خطأ من الخادم - ${data['message']}');
          break;
          
        default:
          developer.log('⚠️ WebSocket: نوع رسالة غير معروف - $messageType');
      }
    } catch (e) {
      developer.log('❌ WebSocket: خطأ في معالجة الرسالة - $e');
    }
  }

  /// معالجة تحديثات حالة المطاعم
  void _handleBusinessStatusUpdate(Map<String, dynamic> data) {
    try {
      final businessId = data['businessId'] as String?;
      final statusData = data['status'] as Map<String, dynamic>?;
      
      if (businessId == null || statusData == null) {
        developer.log('⚠️ WebSocket: بيانات تحديث الحالة ناقصة');
        return;
      }

      developer.log('🔄 WebSocket: تحديث حالة المطعم $businessId');

      // إنشاء كائن التحديث
      final update = BusinessStatusUpdate(
        businessId: businessId,
        status: statusData['status'] as String? ?? 'UNKNOWN',
        statusText: statusData['statusText'] as String? ?? '',
        statusMessage: statusData['statusMessage'] as String? ?? '',
        canAcceptOrders: statusData['canAcceptOrders'] as bool? ?? false,
        isOnline: statusData['isOnline'] as bool? ?? false,
        acceptingOrders: statusData['acceptingOrders'] as bool? ?? false,
        isBusy: statusData['isBusy'] as bool? ?? false,
        currentOrdersCount: statusData['currentOrdersCount'] as int? ?? 0,
        maxOrdersCapacity: statusData['maxOrdersCapacity'] as int? ?? 10,
        timestamp: DateTime.now(),
      );

      // تحديث الـ cache
      BusinessStatusCache.cacheBusinessStatus(businessId, {
        'status': update.status,
        'statusText': update.statusText,
        'statusMessage': update.statusMessage,
        'canAcceptOrders': update.canAcceptOrders,
        'iconName': _getIconForStatus(update.status),
        'colorCode': _getColorForStatus(update.status),
      });

      // إرسال التحديث للمستمعين
      _businessStatusController.add(update);

    } catch (e) {
      developer.log('❌ WebSocket: خطأ في معالجة تحديث الحالة - $e');
    }
  }

  /// معالجة تحديثات ساعات العمل
  void _handleWorkingHoursUpdate(Map<String, dynamic> data) {
    try {
      final businessId = data['businessId'] as String?;
      final updateData = data['updateData'] as Map<String, dynamic>?;
      
      if (businessId == null) {
        developer.log('⚠️ WebSocket: معرف المطعم مفقود في تحديث ساعات العمل');
        return;
      }

      developer.log('🕒 WebSocket: تحديث ساعات عمل المطعم $businessId');
      developer.log('📋 WebSocket: بيانات التحديث: $updateData');

      // تحديث الـ cache بساعات العمل الجديدة
      if (updateData != null) {
        final workingHours = updateData['workingHours'] as Map<String, dynamic>?;
        if (workingHours != null) {
          BusinessStatusCache.updateBusinessWorkingHours(businessId, workingHours);
          developer.log('✅ WebSocket: تم تحديث ساعات العمل في الذاكرة المؤقتة');
        }
      }

      // إنشاء تحديث حالة مؤقت لإشعار UI
      final statusUpdate = BusinessStatusUpdate(
        businessId: businessId,
        status: 'WORKING_HOURS_UPDATED',
        statusText: 'تم تحديث ساعات العمل',
        statusMessage: updateData?['businessName'] ?? '',
        canAcceptOrders: true,
        isOnline: true,
        acceptingOrders: true,
        isBusy: false,
        currentOrdersCount: 0,
        maxOrdersCapacity: 10,
        timestamp: DateTime.now(),
      );

      // إرسال التحديث للمستمعين
      _businessStatusController.add(statusUpdate);
      
      developer.log('✅ WebSocket: تم إشعار UI بتحديث ساعات العمل');

    } catch (e) {
      developer.log('❌ WebSocket: خطأ في معالجة تحديث ساعات العمل - $e');
    }
  }

  /// معالجة قطع الاتصال
  void _handleDisconnection() {
    developer.log('🔌 WebSocket: تم قطع الاتصال');
    _isConnected = false;
    _connectionStatusController.add(false);
    _heartbeatTimer?.cancel();
    _scheduleReconnect();
  }

  /// معالجة الأخطاء
  void _handleError(error) {
    developer.log('❌ WebSocket: خطأ في الاتصال - $error');
    _isConnected = false;
    _connectionStatusController.add(false);
    _scheduleReconnect();
  }

  /// بدء heartbeat
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isConnected && _channel != null) {
        try {
          final pingMessage = {
            'type': 'ping',
            'timestamp': DateTime.now().toIso8601String(),
          };
          _channel!.sink.add(json.encode(pingMessage));
          developer.log('💓 WebSocket: Ping مرسل');
        } catch (e) {
          developer.log('❌ WebSocket: فشل إرسال ping - $e');
          _handleDisconnection();
        }
      }
    });
  }

  /// جدولة إعادة الاتصال
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      developer.log('❌ WebSocket: تم الوصول للحد الأقصى لمحاولات إعادة الاتصال');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectAttempts++;
      developer.log('🔄 WebSocket: محاولة إعادة الاتصال #$_reconnectAttempts');
      connect();
    });
  }

  /// اشتراك في تحديثات مطعم معين
  void subscribeToBusinessStatus(String businessId) {
    if (!_isConnected || _channel == null) {
      developer.log('⚠️ WebSocket: لا يوجد اتصال - لا يمكن الاشتراك');
      return;
    }

    try {
      final subscribeMessage = {
        'type': 'subscribe',
        'businessId': businessId,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      _channel!.sink.add(json.encode(subscribeMessage));
      developer.log('📝 WebSocket: تم الاشتراك في تحديثات المطعم $businessId');
    } catch (e) {
      developer.log('❌ WebSocket: فشل الاشتراك - $e');
    }
  }

  /// إلغاء الاشتراك في تحديثات مطعم معين
  void unsubscribeFromBusinessStatus(String businessId) {
    if (!_isConnected || _channel == null) {
      return;
    }

    try {
      final unsubscribeMessage = {
        'type': 'unsubscribe',
        'businessId': businessId,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      _channel!.sink.add(json.encode(unsubscribeMessage));
      developer.log('🚫 WebSocket: تم إلغاء الاشتراك في المطعم $businessId');
    } catch (e) {
      developer.log('❌ WebSocket: فشل إلغاء الاشتراك - $e');
    }
  }

  /// تنظيف الموارد
  void dispose() {
    developer.log('🗑️ WebSocket: تنظيف الموارد');
    disconnect();
    _businessStatusController.close();
    _connectionStatusController.close();
  }

  // دوال مساعدة
  String _getIconForStatus(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE': return 'check_circle';
      case 'BUSY': return 'schedule';
      case 'CLOSED': return 'access_time';
      case 'OFFLINE': return 'wifi_off';
      case 'INACTIVE': return 'block';
      default: return 'error';
    }
  }

  String _getColorForStatus(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE': return '#4CAF50';
      case 'BUSY': return '#FF5722';
      case 'CLOSED': return '#FF9800';
      case 'OFFLINE': return '#f44336';
      case 'INACTIVE': return '#9E9E9E';
      default: return '#9E9E9E';
    }
  }
}

/// كلاس لتحديثات حالة المطاعم
class BusinessStatusUpdate {
  final String businessId;
  final String status;
  final String statusText;
  final String statusMessage;
  final bool canAcceptOrders;
  final bool isOnline;
  final bool acceptingOrders;
  final bool isBusy;
  final int currentOrdersCount;
  final int maxOrdersCapacity;
  final DateTime timestamp;

  BusinessStatusUpdate({
    required this.businessId,
    required this.status,
    required this.statusText,
    required this.statusMessage,
    required this.canAcceptOrders,
    required this.isOnline,
    required this.acceptingOrders,
    required this.isBusy,
    required this.currentOrdersCount,
    required this.maxOrdersCapacity,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'BusinessStatusUpdate(businessId: $businessId, status: $status, canAcceptOrders: $canAcceptOrders)';
  }
}
