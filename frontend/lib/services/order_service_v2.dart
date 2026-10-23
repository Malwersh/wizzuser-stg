import 'package:uuid/uuid.dart';
import 'live_activity_service.dart';
// lib/services/order_service_v2.dart

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../models/address_model.dart';
import 'session_service.dart';
import 'push_notifications_service.dart';
import '../config/api_config.dart';
import 'cancellation_messages.dart';
import 'discount_item_policy.dart';

class OrderServiceV2 extends ChangeNotifier {
  static final OrderServiceV2 _instance = OrderServiceV2._internal();
  factory OrderServiceV2() => _instance;
  OrderServiceV2._internal() {
    // Load guest token asynchronously on initialization
    _initializeService();
  }

  /// Initialize the service and load guest token
  Future<void> _initializeService() async {
    await _loadGuestTokenFromStorage();
  }

  /// Public method to ensure service is initialized
  Future<void> ensureInitialized() async {
    await _loadGuestTokenFromStorage();
  }

  // Base URL for orders API (User Service - لإنشاء وقراءة الطلبات)
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  // Order Service URL (للإلغاء فقط - cancel/unassign)
  static const String _orderServiceUrl = String.fromEnvironment(
    'ORDER_SERVICE_URL',
    // Staging repo fallback: OrderService API Gateway (staging)
    defaultValue: 'https://mqwom78d3c.execute-api.us-east-1.amazonaws.com/staging',
  );

  List<OrderModel> _orders = [];
  OrderModel? _currentOrder;
  bool _isLoading = false;
  String? _error;
  bool lastCancellationPending = false;
  String? lastCancellationMessage;
  final Map<String,String> _cancellationKeys = {};
  String? _guestToken; // Token for guest order tracking

  // Getters
  List<OrderModel> get orders => List.unmodifiable(_orders);
  OrderModel? get currentOrder => _currentOrder;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get guestToken => _guestToken;

  // Guest token persistence methods
  static const String _guestTokenKey = 'guest_token';

  /// Load guest token from SharedPreferences
  Future<void> _loadGuestTokenFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _guestToken = prefs.getString(_guestTokenKey);
      if (_guestToken != null) {
        print('OrderService: Loaded guest token from storage: $_guestToken');
      }
    } catch (e) {
      print('OrderService: Error loading guest token from storage: $e');
    }
  }

  /// Save guest token to SharedPreferences
  Future<void> _saveGuestTokenToStorage(String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token != null) {
        await prefs.setString(_guestTokenKey, token);
        print('OrderService: Saved guest token to storage: $token');
      } else {
        await prefs.remove(_guestTokenKey);
        print('OrderService: Removed guest token from storage');
      }
    } catch (e) {
      print('OrderService: Error saving guest token to storage: $e');
    }
  }

  // Helper method to get headers with authentication
  Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Get authentication token
    try {
      final token = SessionService.instance.accessToken;
      if (token != null &&
          token.isNotEmpty &&
          token != 'placeholder_access_token') {
        headers['Authorization'] = 'Bearer $token';
        print('OrderService: Added Authorization header');
      } else {
        print(
          'OrderService: No valid token found - checking if user is logged in',
        );
        final isLoggedIn = SessionService.instance.isLoggedIn;
        if (isLoggedIn) {
          print('OrderService: User is logged in but token not available');
        } else {
          print('OrderService: User is guest - proceeding without auth');
        }
      }
    } catch (e) {
      print('OrderService: Error getting token: $e');
      print('OrderService: Proceeding without authentication for guest user');
    }

    return headers;
  }

  /// إنشاء طلب جديد
  Future<Map<String, dynamic>> createOrder({
    required String storeId,
    required String storeName,
    String? storeAddress, // عنوان المطعم للسائقين
    required List<Map<String, dynamic>> cartItems,
    required DetailedAddress deliveryAddress,
    required PaymentMethod paymentMethod,
    double deliveryFee = 10.0,
    double taxRate = 0.0,
    double discount = 0.0,
    String? deliveryInstructions,
    String? promoCode,
    // معلومات المستخدم الإضافية
    String? userId, // null للضيوف
    String? customerName,
    String? customerPhone,
    String? customerEmail,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      // التحقق من صحة عناصر السلة وتحويلها للصيغة المطلوبة للباك إند
      List<Map<String, dynamic>> transformedCartItems = [];
      for (int i = 0; i < cartItems.length; i++) {
        final item = cartItems[i];

        // التحقق من الحقول المطلوبة
        if (item['id'] == null ||
            item['name'] == null ||
            item['price'] == null ||
            item['quantity'] == null) {
          _setError('عنصر في السلة يحتوي على بيانات ناقصة');
          return {
            'success': false,
            'message': 'عنصر في السلة يحتوي على بيانات ناقصة',
          };
        }

        // تحويل عنصر السلة للصيغة المطلوبة للباك إند
        String specialInstructions =
            item['special_instructions'] ??
            item['specialInstructions'] ??
            item['notes'] ??
            '';

        final transformedItem = {
          'id': item['id'],
          'name': item['name'],
          'price': item['price'],
          'quantity': item['quantity'],
          'customizations':
              item['selected_options'] ?? item['selectedOptions'] ?? item['customizations'] ?? [],
          ...discountSelectionFields(item),
          // تحويل special_instructions إلى specialInstructions للباك إند
          'specialInstructions': specialInstructions,
        };

        // إضافة تسجيل للملاحظات إذا كانت موجودة
        if (specialInstructions.isNotEmpty) {
          print(
            'OrderService: Item "${item['name']}" has special instructions: "$specialInstructions"',
          );
        }

        transformedCartItems.add(transformedItem);
      }

      final orderData = {
        'storeId': storeId,
        'storeName': storeName,
        'storeAddress':
            storeAddress ?? 'العنوان غير محدد', // عنوان المطعم للسائقين
        'cartItems': transformedCartItems,
        'deliveryAddress': {
          'id': deliveryAddress.id,
          'fullAddress': deliveryAddress.fullAddress,
          'latitude': deliveryAddress.latitude,
          'longitude': deliveryAddress.longitude,
          'phoneNumber': deliveryAddress.phoneNumber,
          'name': deliveryAddress.name,
          'province': deliveryAddress.province,
          'district': deliveryAddress.district,
          'neighborhood': deliveryAddress.neighborhood,
          'landmark': deliveryAddress.landmark,
        },
        'paymentMethod': paymentMethod.value,
        'deliveryFee': deliveryFee,
        'taxRate': taxRate,
        'discount': discount,
        'deliveryInstructions': deliveryInstructions,
        'promoCode': promoCode,
        'userId': userId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerEmail': customerEmail,
      };

      // التحقق من البيانات قبل الإرسال
      if (orderData['storeId'] == null ||
          orderData['storeId'].toString().isEmpty) {
        _setError('معرف المطعم مطلوب');
        return {'success': false, 'message': 'معرف المطعم مطلوب'};
      }

      if (orderData['cartItems'] == null ||
          (orderData['cartItems'] as List).isEmpty) {
        _setError('عناصر السلة مطلوبة');
        return {'success': false, 'message': 'عناصر السلة مطلوبة'};
      }

      String requestBody;
      try {
        requestBody = json.encode(orderData);
        print('OrderService: Sending request to: $_baseUrl/orders');
        print('OrderService: Request body: $requestBody');
      } catch (jsonEncodeError) {
        print('OrderService: JSON encoding error: $jsonEncodeError');
        final errorMessage = 'خطأ في تحضير البيانات للإرسال';
        _setError(errorMessage);
        return {'success': false, 'message': errorMessage};
      }

      print('OrderService: Making HTTP POST request...');
      print(
        'OrderService: Total cart items with special instructions: ${transformedCartItems.where((item) => (item['specialInstructions'] as String).isNotEmpty).length}',
      );
      final headers = await _getHeaders();
      print('OrderService: Headers: $headers');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/orders'),
            headers: headers,
            body: requestBody,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('OrderService: Request timed out');
              throw TimeoutException(
                'انتهت مهلة الاتصال بالخادم',
                const Duration(seconds: 30),
              );
            },
          );

      print('OrderService: Response status code: ${response.statusCode}');
      print('OrderService: Response body: ${response.body}');

      if (response.body.isEmpty) {
        final errorMessage = 'الخادم لم يرجع أي بيانات';
        _setError(errorMessage);
        return {'success': false, 'message': errorMessage};
      }

      Map<String, dynamic> responseData;
      try {
        responseData = json.decode(response.body);
      } catch (jsonError) {
        final errorMessage = 'خطأ في تحليل استجابة الخادم';
        _setError(errorMessage);
        return {'success': false, 'message': errorMessage};
      }

      if (response.statusCode == 201 && responseData['success'] == true) {
        final orderInfo = responseData['order'];

        // حساب المبالغ
        final subtotal = cartItems.fold(
          0.0,
          (sum, item) =>
              sum + ((item['price'] ?? 0.0) * (item['quantity'] ?? 1)),
        );
        final tax = subtotal * taxRate;
        final total = subtotal + deliveryFee + tax - discount;

        // إنشاء كائن OrderModel من البيانات المرجعة
        final orderId =
            orderInfo['id'] ??
            orderInfo['orderId'] ??
            DateTime.now().millisecondsSinceEpoch.toString();
        final orderNumber =
            orderInfo['orderNumber'] ??
            orderInfo['order_number'] ??
            'ORD${DateTime.now().millisecondsSinceEpoch}';

        // Save guestToken for guest orders
        if (userId == null && responseData.containsKey('guestToken')) {
          _guestToken = responseData['guestToken'];
          print('🎫 OrderService: Guest token saved: $_guestToken');
          await _saveGuestTokenToStorage(
            _guestToken,
          ); // Save guest token to storage

          // Register push token for guest tracking once we have a stable guestToken.
          if (_guestToken != null && _guestToken!.isNotEmpty) {
            await PushNotificationsService.onGuestTokenAvailable(_guestToken!);
          }
        }

        print('✅ OrderService: Order created successfully');
        print('🆔 OrderService: Order ID: $orderId');
        print('🔢 OrderService: Order Number: $orderNumber');

        final order = OrderModel(
          id: orderId,
          orderNumber: orderNumber,
          userId: userId ?? 'guest',
          storeId: storeId,
          storeName: storeName,
          items: cartItems.map((item) => OrderItem.fromCartItem(item)).toList(),
          subtotal: subtotal,
          deliveryFee: deliveryFee,
          tax: tax,
          discount: discount,
          total: total,
          status: OrderStatus.pending,
          paymentMethod: paymentMethod,
          deliveryAddress: deliveryAddress,
          deliveryInstructions: deliveryInstructions,
          customerPhone: customerPhone,
          customerName: customerName,
          customerEmail: customerEmail,
          isGuestOrder: userId == null,
          createdAt: DateTime.now(),
          estimatedDeliveryTime: DateTime.tryParse(orderInfo['estimatedDeliveryTime']?.toString() ?? ''),
        );

        _currentOrder = order;

        // Start iOS Live Activity for this order
        LiveActivityService.startForOrder(order);

        // إضافة الطلب للقائمة
        final existingIndex = _orders.indexWhere((o) => o.id == order.id);
        if (existingIndex != -1) {
          _orders[existingIndex] = order;
        } else {
          _orders.insert(0, order);
        }
        notifyListeners();

        return {
          'success': true,
          'message': responseData['message'] ?? 'تم إنشاء الطلب بنجاح',
          'order': order,
        };
      } else if (response.statusCode == 409) {
        // معالجة خاصة لحالة وجود طلب نشط بالفعل (Conflict)
        final errorMessage =
            responseData['message'] ??
            'لديك طلب نشط بالفعل. يجب انتظار إتمام الطلب الحالي قبل إنشاء طلب جديد.';
        print(
          '⚠️ OrderService: Active order conflict - ${response.statusCode}',
        );
        print('📄 OrderService: Error message: $errorMessage');

        // إضافة معلومات الطلب النشط إذا كانت متوفرة
        if (responseData['activeOrder'] != null) {
          final activeOrder = responseData['activeOrder'];
          print('🔄 OrderService: Active order ID: ${activeOrder['orderId']}');
          print(
            '📊 OrderService: Active order status: ${activeOrder['status']}',
          );
        }

        _setError(errorMessage);
        return {
          'success': false,
          'message': errorMessage,
          'statusCode': 409,
          'errorType': 'ACTIVE_ORDER_CONFLICT',
          'activeOrderDetails': responseData['activeOrder'],
        };
      } else {
        final errorMessage = responseData['message'] ?? 'فشل في إنشاء الطلب';
        _setError(errorMessage);
        return {'success': false, 'message': errorMessage};
      }
    } on TimeoutException catch (e) {
      print('OrderService: Timeout exception: $e');
      const errorMessage =
          'انتهت مهلة الاتصال بالخادم - يرجى المحاولة مرة أخرى';
      _setError(errorMessage);
      return {'success': false, 'message': errorMessage};
    } on FormatException catch (e) {
      print('OrderService: Format exception: $e');
      const errorMessage = 'خطأ في تنسيق البيانات المرسلة';
      _setError(errorMessage);
      return {'success': false, 'message': errorMessage};
    } catch (e) {
      print('OrderService: General exception: $e');
      print('OrderService: Exception type: ${e.runtimeType}');
      String errorMessage;
      final eStr = e.toString();
      if (eStr.isEmpty ||
          eStr == '{}' ||
          eStr == '{().toString()}' ||
          eStr == 'null') {
        errorMessage = 'خطأ في الاتصال بالخادم - يرجى المحاولة مرة أخرى';
      } else {
        errorMessage = 'خطأ في الاتصال بالخادم: $eStr';
      }
      _setError(errorMessage);
      return {'success': false, 'message': errorMessage};
    } finally {
      _setLoading(false);
    }
  }

  /// إضافة طلب جديد إلى القائمة المحلية (استخدام بعد إنشاء الطلب بنجاح)
  void addOrderToList(OrderModel order) {
    print('➕ OrderService: إضافة طلب جديد إلى القائمة المحلية');
    print('   - معرف الطلب: ${order.id}');
    print('   - رقم الطلب: ${order.orderNumber}');
    print('   - حالة الطلب: ${order.status.value}');
    print('   - عدد الطلبات قبل الإضافة: ${_orders.length}');

    final existingIndex = _orders.indexWhere((o) => o.id == order.id);
    if (existingIndex != -1) {
      _orders[existingIndex] = order;
      print('   - تم تحديث طلب موجود في الفهرس: $existingIndex');
    } else {
      _orders.insert(0, order);
      print('   - تم إدراج طلب جديد في بداية القائمة');
    }

    _currentOrder = order;
    print('   - تم تعيين الطلب كطلب حالي');
    print('   - عدد الطلبات بعد الإضافة: ${_orders.length}');

    // طباعة الطلبات النشطة
    final activeOrders = getActiveOrdersLocal();
    print('   - عدد الطلبات النشطة الآن: ${activeOrders.length}');

    notifyListeners();
  }

  /// الحصول على الطلبات الحالية فقط
  List<OrderModel> getCurrentOrders() {
    return _orders
        .where((order) => !terminalStatuses.contains(order.status.value))
        .toList();
  }

  /// الحصول على الطلبات السابقة فقط
  List<OrderModel> getPastOrders() {
    return _orders
        .where((order) => terminalStatuses.contains(order.status.value))
        .toList();
  }

  /// جلب تفاصيل طلب محدد
  Future<OrderModel?> getOrderDetails(String orderId) async {
    try {
      _setLoading(true);
      _clearError();

      print('🔍 OrderService: Getting order details for ID: $orderId');
      print('🌐 OrderService: Using base URL: $_baseUrl');

      final headers = await _getHeaders();
      final fullUrl = '$_baseUrl/orders/$orderId';

      print('📡 OrderService: Making GET request to: $fullUrl');


      final response = await http
          .get(Uri.parse(fullUrl), headers: headers)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              print('⏰ OrderService: Request timeout for order $orderId');
              throw TimeoutException(
                'انتهت مهلة الاتصال بالخادم',
                const Duration(seconds: 15),
              );
            },
          );

      print('📄 OrderService: getOrderDetails response body: ${response.body}');

      if (response.body.isEmpty) {
        print('❌ OrderService: Empty response body');
        _setError('الخادم لم يرجع أي بيانات');
        return null;
      }

      Map<String, dynamic> responseData;
      try {
        responseData = json.decode(response.body);
      } catch (jsonError) {
        print('❌ OrderService: JSON parsing error: $jsonError');
        _setError('خطأ في تحليل استجابة الخادم');
        return null;
      }

      if (response.statusCode == 200 && responseData['success'] == true) {
        final orderData = responseData['order'];
        if (orderData == null) {
          print('❌ OrderService: Order data is null in response');
          _setError('بيانات الطلب مفقودة في الاستجابة');
          return null;
        }

        print('📦 OrderService: Order data keys: ${orderData.keys.toList()}');
        print('🆔 OrderService: Order ID in response: ${orderData['id']}');
        print(
          '🔢 OrderService: Order Number in response: ${orderData['orderNumber']}',
        );
        print(
          '🏠 OrderService: deliveryAddress in response: ${orderData['deliveryAddress']}',
        );
        print('💰 OrderService: pricing in response: ${orderData['pricing']}');

        try {
          final order = OrderModel.fromJson(orderData);
          print(
            '📊 OrderService: OrderModel details - ID: ${order.id}, Number: ${order.orderNumber}, Status: ${order.status}',
          );
          print(
            '🏠 OrderService: OrderModel deliveryAddress: ${order.deliveryAddress.fullAddress}',
          );
          print('💰 OrderService: OrderModel total: ${order.total}');

          // تحديث الطلب في القائمة إذا كان موجوداً
          final index = _orders.indexWhere((o) => o.id == orderId);
          if (index != -1) {
            _orders[index] = order;
          } else {
            _orders.insert(0, order);
            print('➕ OrderService: Added new order to list');
          }
          unawaited(LiveActivityService.syncOrder(order));
          notifyListeners();

          return order;
        } catch (modelError) {
          print('❌ OrderService: Error creating OrderModel: $modelError');
          _setError('خطأ في معالجة بيانات الطلب: $modelError');
          return null;
        }
      } else {
        print(
          '❌ OrderService: getOrderDetails failed with response: $responseData',
        );
        final errorMessage =
            responseData['message'] ?? 'فشل في جلب تفاصيل الطلب';
        _setError(errorMessage);
        return null;
      }
    } on TimeoutException catch (e) {
      print('⏰ OrderService: Timeout exception: $e');
      _setError('انتهت مهلة الاتصال بالخادم - يرجى المحاولة مرة أخرى');
      return null;
    } catch (e) {
      print('❌ OrderService: getOrderDetails error: $e');
      print('🔍 OrderService: Error type: ${e.runtimeType}');
      _setError('خطأ في جلب تفاصيل الطلب: ${e.toString()}');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// جلب طلبات المستخدم
  Future<void> getUserOrders(String? userId) async {
    try {
      _setLoading(true);
      _clearError();

      // مسح الطلبات القديمة قبل تحميل الجديدة
      final oldOrdersCount = _orders.length;
      _orders.clear();
      print('OrderService: 🗑️ تم مسح ${oldOrdersCount} طلب قديم');

      // Determine how to fetch orders based on user type
      String url;
      if (userId != null && userId != 'guest') {
        // Registered user - use userId
        url = '$_baseUrl/users/$userId/orders';
        print('OrderService: 📡 طلب GET للمستخدم المسجل إلى: $url');
      } else if (_guestToken != null && _guestToken!.isNotEmpty) {
        // Guest user with guestToken
        url = '$_baseUrl/users/guest/orders?guestToken=$_guestToken';
        print('OrderService: 📡 طلب GET للضيف باستخدام guestToken إلى: $url');
      } else {
        // No valid identifier for fetching orders
        print('OrderService: ⚠️ لا توجد معرفات صالحة لجلب الطلبات');
        _orders = [];
        notifyListeners();
        return;
      }

      final response = await http
          .get(Uri.parse(url), headers: await _getHeaders())
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⏰ OrderService: انتهت مهلة طلب الطلبات');
              throw TimeoutException(
                'انتهت مهلة الاتصال',
                const Duration(seconds: 10),
              );
            },
          );

      if (response.body.isEmpty) {
        print('OrderService: ⚠️ محتوى الاستجابة فارغ');
        _setError('الخادم لم يرجع أي بيانات');
        return;
      }

      print('OrderService: 📄 محتوى الاستجابة: ${response.body}');

      Map<String, dynamic> responseData;
      try {
        responseData = json.decode(response.body);
      } catch (jsonError) {
        print('OrderService: ❌ خطأ في تحليل JSON: $jsonError');
        _setError('خطأ في تحليل استجابة الخادم');
        return;
      }

      if (response.statusCode == 200 && responseData['success'] == true) {
        final ordersData = responseData['orders'] as List?;

        if (ordersData == null) {
          print('OrderService: ⚠️ قائمة الطلبات فارغة في الاستجابة');
          _orders = [];
        } else {
          print(
            'OrderService: 📊 تم العثور على ${ordersData.length} طلب في API',
          );

          try {
            _orders =
                ordersData.map((orderData) {
                  return OrderModel.fromJson(orderData);
                }).toList();

            // طباعة تفاصيل الطلبات المحملة
            final activeOrders = getActiveOrdersLocal();
            final completedOrders = getCompletedOrdersLocal();
            print('OrderService: 📋 الطلبات النشطة: ${activeOrders.length}');
            print(
              'OrderService: 📋 الطلبات المكتملة: ${completedOrders.length}',
            );

            // طباعة أرقام الطلبات للتأكد
            for (final order in _orders) {
              print(
                'OrderService: 📦 طلب ${order.orderNumber} - حالة: ${order.status.value}',
              );
            }
          } catch (modelError) {
            print(
              'OrderService: ❌ خطأ في تحويل البيانات إلى OrderModel: $modelError',
            );
            _setError('خطأ في معالجة بيانات الطلبات');
            return;
          }
        }

        notifyListeners();
        print('OrderService: 🔔 تم إرسال إشعار التحديث');
      } else {
        final errorMessage = responseData['message'] ?? 'فشل في جلب الطلبات';
        print('OrderService: ❌ فشل في الاستجابة - $errorMessage');
        _setError(errorMessage);
      }
    } on TimeoutException catch (e) {
      print('OrderService: ⏰ انتهت مهلة الطلب: $e');
      _setError('انتهت مهلة الاتصال بالخادم - يرجى المحاولة مرة أخرى');
    } catch (e) {
      print('OrderService: ❌ خطأ عام في getUserOrders: $e');
      print('OrderService: 🔍 نوع الخطأ: ${e.runtimeType}');
      _setError('خطأ في جلب الطلبات: ${e.toString()}');
    } finally {
      _setLoading(false);
      print('OrderService: 🏁 انتهى تحميل الطلبات');
    }
  }

  /// جلب الطلبات النشطة فقط (إذا لم تكن محملة بالفعل، حمل جميع الطلبات)
  Future<void> getActiveOrders(String userId) async {
    try {
      _setLoading(true);
      _clearError();

      // إذا لم يكن لدينا طلبات، حمل جميع الطلبات أولاً
      if (_orders.isEmpty) {
        print(
          'OrderService: 📦 لا توجد طلبات محملة - تحميل جميع الطلبات أولاً',
        );
        await getUserOrders(userId);
        return;
      }

      // إذا كان لدينا طلبات بالفعل، تحديث الطلبات النشطة فقط
      final url = '$_baseUrl/users/$userId/orders';
      print('OrderService: 🔗 URL لتحديث الطلبات: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      print('OrderService: استجابة تحديث الطلبات: ${response.statusCode}');

      if (response.body.isNotEmpty) {
        final responseData = json.decode(response.body);

        if (response.statusCode == 200 && responseData['success'] == true) {
          final ordersData = responseData['orders'] as List;

          final newOrders =
              ordersData
                  .map((orderData) => OrderModel.fromJson(orderData))
                  .toList();

          // دمج الطلبات الجديدة مع الموجودة (بدلاً من الاستبدال)
          for (final newOrder in newOrders) {
            final existingIndex = _orders.indexWhere(
              (o) => o.id == newOrder.id,
            );
            if (existingIndex != -1) {
              // تحديث الطلب الموجود
              _orders[existingIndex] = newOrder;
            } else {
              // إضافة طلب جديد
              _orders.insert(0, newOrder);
              print(
                'OrderService: ➕ تم إضافة طلب جديد: ${newOrder.orderNumber}',
              );
            }
          }

          print('OrderService: إجمالي الطلبات الآن: ${_orders.length}');
          print(
            'OrderService: الطلبات النشطة: ${getActiveOrdersLocal().length}',
          );
          notifyListeners();
        } else {
          print(
            'OrderService: ⚠️ فشلت الاستجابة: ${responseData['message'] ?? 'خطأ غير معروف'}',
          );
        }
      }
    } catch (e) {
      print('OrderService: ❌ خطأ في تحديث الطلبات النشطة: $e');
      // لا نعرض خطأ للمستخدم في حال فشل التحديث
      // _setError('خطأ في تحديث الطلبات: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  /// جلب الطلبات المكتملة فقط
  Future<void> getCompletedOrders(String userId) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await http.get(
        Uri.parse('$_baseUrl/users/$userId/orders?status=completed&limit=50'),
        headers: await _getHeaders(),
      );

      print('OrderService: استجابة الطلبات المكتملة: ${response.statusCode}');

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final ordersData = responseData['orders'] as List;

        final completedOrders =
            ordersData
                .map((orderData) => OrderModel.fromJson(orderData))
                .toList();

        // تحديث فقط الطلبات المكتملة في القائمة
        _orders.removeWhere(
          (order) =>
              ['delivered', 'cancelled', 'failed', 'returned'].contains(order.status.value),
        );
        _orders.addAll(completedOrders);

        print('OrderService: تم تحميل ${completedOrders.length} طلب مكتمل');
        notifyListeners();
      } else {
        _setError(responseData['message'] ?? 'فشل في جلب الطلبات المكتملة');
      }
    } catch (e) {
      print('OrderService: خطأ في جلب الطلبات المكتملة: $e');
      _setError('خطأ في جلب الطلبات المكتملة: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  /// الحالات النهائية (الطلب انتهى) — أي حالة خارج هذه القائمة تُعتبر نشطة
  static const List<String> terminalStatuses = [
    'delivered',
    'cancelled',
    'failed',
    'expired',
    'rejected',
    'returned',
  ];

  /// الحصول على الطلبات النشطة من القائمة المحلية
  /// يُعتبر الطلب نشطاً إذا لم يكن في حالة نهائية، حتى تظهر الطلبات في جميع
  /// مراحل التوصيل (ready_for_pickup, assigned, accepted, picked_up,
  /// heading_to_customer ... إلخ) وليس فقط مراحل التحضير الأولى.
  List<OrderModel> getActiveOrdersLocal() {
    final activeOrders =
        _orders
            .where((order) => !terminalStatuses.contains(order.status.value))
            .toList();

    print('🔍 OrderService.getActiveOrdersLocal():');
    print('   - إجمالي الطلبات في الذاكرة: ${_orders.length}');
    print('   - الحالات النهائية المستثناة: $terminalStatuses');
    print('   - عدد الطلبات النشطة الموجودة: ${activeOrders.length}');

    // طباعة تفاصيل جميع الطلبات للتشخيص
    if (_orders.isNotEmpty) {
      print('   - تفاصيل جميع الطلبات:');
      for (final order in _orders) {
        print(
          '     • ${order.orderNumber}: ${order.status.value} (${order.status.arabicName})',
        );
      }
    }

    return activeOrders;
  }

  /// الحصول على الطلبات المكتملة من القائمة المحلية
  List<OrderModel> getCompletedOrdersLocal() {
    return _orders
        .where((order) => terminalStatuses.contains(order.status.value))
        .toList();
  }

  /// تحديث حالة طلب
  Future<bool> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/orders/$orderId/status'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': newStatus.value}),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        if (responseData['cancellationStatus'] == 'REQUESTED' && responseData['cancelled'] == false) {
          lastCancellationPending = true;
          lastCancellationMessage = responseData['message'] as String?;
          notifyListeners();
          return true;
        }
        // تحديث الطلب في القائمة المحلية
        final index = _orders.indexWhere((o) => o.id == orderId);
        if (index != -1) {
          _orders[index] = _orders[index].copyWith(status: newStatus);
          notifyListeners();
          _syncLiveActivity(_orders[index]);
        }
        return true;
      } else {
        _setError(responseData['message'] ?? 'فشل في تحديث حالة الطلب');
        return false;
      }
    } catch (e) {
      _setError('خطأ في تحديث حالة الطلب: ${e.toString()}');
      return false;
    }
  }

  /// إلغاء طلب
  Future<bool> cancelOrder(String orderId, String reason) async {
    lastCancellationPending = false;
    lastCancellationMessage = null;
    print('🔴 OrderService.cancelOrder():');
    print('   - معرف الطلب: $orderId');
    print('   - سبب الإلغاء: $reason');

    try {
      // Get user ID from session
      final sessionService = SessionService.instance;
      final userId = sessionService.currentUserId;

      if (userId == null && _guestToken == null) {
        throw Exception('User ID not found in session');
      }

      final requestBody = json.encode({
        'orderId': orderId,
        'canceledBy': 'customer',
        'reason': reason,
        'cancellationProtocolVersion': 1,
        'idempotencyKey': _cancellationKeys.putIfAbsent(orderId, () => const Uuid().v4()),
        'requestedBy': userId ?? _guestToken,
        if (_guestToken != null) 'guestToken': _guestToken,
      });



      final headers = await _getHeaders();
      print('🔴 Request URL: $_orderServiceUrl/order/cancel');

      final response = await http
          .post(
            Uri.parse('$_orderServiceUrl/order/cancel'),
            headers: headers,
            body: requestBody,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException(
                'انتهت مهلة الاتصال بالخادم',
                const Duration(seconds: 30),
              );
            },
          );

      print('🔴 Response status: ${response.statusCode}');
      print('🔴 Response body: ${response.body}');

      if (response.body.isEmpty) {
        throw Exception('الخادم لم يرجع أي بيانات');
      }

      final responseData = json.decode(response.body);
      print(
        '   - استجابة API: ${responseData['success']} - ${responseData['message']}',
      );

      if (response.statusCode == 200 && responseData['success'] == true) {
        // تحديث الطلب في القائمة المحلية
        final index = _orders.indexWhere((o) => o.id == orderId);
        print('   - موقع الطلب في القائمة: $index من ${_orders.length}');

        if (index != -1) {
          final oldStatus = _orders[index].status;
          _orders[index] = _orders[index].copyWith(
            status: OrderStatus.cancelled,
            cancelReason: reason,
          );
          print('   - تم تحديث الطلب: $oldStatus → ${_orders[index].status}');

          // تحديث الطلب الحالي أيضاً إذا كان نفس الطلب الملغى
          if (_currentOrder?.id == orderId) {
            _currentOrder = _orders[index];
            print('   - تم تحديث _currentOrder أيضاً');
          }

          print('   - استدعاء notifyListeners()...');
          notifyListeners();
          _syncLiveActivity(_orders[index]);
          print('   ✅ تم إلغاء الطلب بنجاح!');
        } else {
          print('   ⚠️ لم يتم العثور على الطلب في القائمة المحلية');
        }
        return true;
      } else {
        _setError(cancellationMessage(responseData['code'], fallback: responseData['message']));
        return false;
      }
    } catch (e) {
      print('   ❌ خطأ في إلغاء الطلب: $e');
      _setError('خطأ في إلغاء الطلب: ${e.toString()}');
      return false;
    }
  }

  /// الحصول على الطلبات النشطة (غير مكتملة)
  List<OrderModel> get activeOrders {
    return _orders
        .where(
          (order) =>
              order.status != OrderStatus.delivered &&
              order.status != OrderStatus.returned &&
              order.status != OrderStatus.cancelled &&
              order.status != OrderStatus.failed,
        )
        .toList();
  }

  /// الحصول على الطلبات المكتملة
  List<OrderModel> get completedOrders {
    return _orders
        .where(
          (order) =>
              order.status == OrderStatus.delivered ||
              order.status == OrderStatus.returned ||
              order.status == OrderStatus.cancelled ||
              order.status == OrderStatus.failed ||
              order.status == OrderStatus.expired ||
              order.status == OrderStatus.rejected,
        )
        .toList();
  }

  /// البحث في الطلبات
  List<OrderModel> searchOrders(String query) {
    final lowerQuery = query.toLowerCase();
    return _orders
        .where(
          (order) =>
              order.orderNumber.toLowerCase().contains(lowerQuery) ||
              order.storeName.toLowerCase().contains(lowerQuery) ||
              order.items.any(
                (item) => item.dishName.toLowerCase().contains(lowerQuery),
              ),
        )
        .toList();
  }

  /// فلترة الطلبات حسب الحالة
  List<OrderModel> getOrdersByStatus(OrderStatus status) {
    return _orders.where((order) => order.status == status).toList();
  }

  /// مسح البيانات عند تسجيل الخروج
  void clearData() {
    unawaited(LiveActivityService.endAll());
    _orders.clear();
    _currentOrder = null;
    _clearError();
    notifyListeners();
  }

  /// مسح جميع الطلبات (عند تغيير المستخدم أو تسجيل الخروج)
  void clearOrders() {
    unawaited(LiveActivityService.endAll());
    final oldCount = _orders.length;
    _orders.clear();
    _currentOrder = null;
    _clearError();
    notifyListeners();
    print('🗑️ OrderService: تم مسح ${oldCount} طلب من الذاكرة');
  }

  /// تحديث طلب من WebSocket
  void updateOrderFromWebSocket(Map<String, dynamic> orderData) {
    try {
      final updatedOrder = OrderModel.fromJson(orderData);
      unawaited(LiveActivityService.syncOrder(updatedOrder));
      final index = _orders.indexWhere((o) => o.id == updatedOrder.id);

      if (index != -1) {
        _orders[index] = updatedOrder;
      } else {
        _orders.insert(0, updatedOrder);
      }

      if (_currentOrder?.id == updatedOrder.id) {
        _currentOrder = updatedOrder;
      }

      notifyListeners();
      _syncLiveActivity(updatedOrder);

      // 🔧 NEW: Log order status changes for debugging
      debugPrint(
        '📲 OrderService: Order ${updatedOrder.id} updated via WebSocket to status: ${updatedOrder.status.arabicName}',
      );
    } catch (e) {
      debugPrint('Error updating order from WebSocket: $e');
    }
  }

  /// معالجة إشعار WebSocket لإلغاء الطلب
  void handleOrderCancellationNotification(
    Map<String, dynamic> notificationData,
  ) {
    try {
      final orderId = notificationData['orderId'] as String;
      final orderData = notificationData['order'] as Map<String, dynamic>;

      debugPrint(
        '🚫 OrderService: Processing order cancellation notification for order $orderId',
      );

      // تحديث الطلب في القائمة
      updateOrderFromWebSocket(orderData);

      // إشعار المستمعين بالتغيير
      notifyListeners();
    } catch (e) {
      debugPrint('Error handling order cancellation notification: $e');
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  static double _statusProgress(OrderStatus status) =>
      LiveActivityService.statusProgress(status);

  static bool _isTerminalStatus(OrderStatus status) =>
      LiveActivityService.isTerminal(status);

  static String _etaText(OrderModel order) => LiveActivityService.etaText(order);

  void _syncLiveActivity(OrderModel order) {
    LiveActivityService.syncOrder(order);
  }

  /// تحديث الطلب الحالي
  void setCurrentOrder(OrderModel? order) {
    _currentOrder = order;
    notifyListeners();
  }

  /// البحث عن طلب بالـ ID
  OrderModel? findOrderById(String orderId) {
    try {
      return _orders.firstWhere((order) => order.id == orderId);
    } catch (e) {
      return null;
    }
  }

  /// الحصول على عدد الطلبات النشطة
  int get activeOrdersCount => activeOrders.length;

  /// الحصول على عدد الطلبات المكتملة
  int get completedOrdersCount => completedOrders.length;

  // ===== Guest Order Management Functions =====

  /// جلب طلبات الضيف باستخدام guestToken
  Future<List<OrderModel>> getGuestOrders({
    String? guestToken,
    String status = 'all', // 'active', 'completed', 'all'
    int limit = 20,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final token = guestToken ?? _guestToken;
      if (token == null || token.isEmpty) {
        throw Exception('لا يوجد رمز تتبع للضيف');
      }

      final uri = Uri.parse('$_baseUrl/orders').replace(
        queryParameters: {
          'guestToken': token,
          'status': status,
          'limit': limit.toString(),
        },
      );

      print('OrderService: Fetching guest orders from: $uri');

      final headers = await _getHeaders();
      final response = await http
          .get(uri, headers: headers)
          .timeout(
            const Duration(seconds: 30),
            onTimeout:
                () =>
                    throw TimeoutException(
                      'انتهت مهلة الاتصال',
                      const Duration(seconds: 30),
                    ),
          );

      print(
        'OrderService: Guest orders response status: ${response.statusCode}',
      );
      print('OrderService: Guest orders response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          final List<dynamic> ordersData = responseData['orders'] ?? [];
          final List<OrderModel> guestOrders =
              ordersData
                  .map((orderData) => OrderModel.fromJson(orderData))
                  .toList();

          print('✅ OrderService: Found ${guestOrders.length} guest orders');
          return guestOrders;
        } else {
          throw Exception(responseData['message'] ?? 'فشل في جلب طلبات الضيف');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'خطأ في جلب طلبات الضيف');
      }
    } catch (e) {
      print('❌ OrderService: Error fetching guest orders: $e');
      _setError('خطأ في جلب طلبات الضيف: $e');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  /// دمج طلبات الضيف مع حساب المستخدم عند تسجيل الدخول
  Future<bool> mergeGuestOrders({
    required String userId,
    String? guestToken,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final token = guestToken ?? _guestToken;
      if (token == null || token.isEmpty) {
        print('OrderService: No guest token found, skipping merge');
        return true; // No guest orders to merge
      }

      final mergeData = {'guestToken': token};

      print('OrderService: Merging guest orders for user: $userId');
      print('OrderService: Guest token: $token');

      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/users/$userId/merge-guest'),
            headers: headers,
            body: json.encode(mergeData),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout:
                () =>
                    throw TimeoutException(
                      'انتهت مهلة الاتصال',
                      const Duration(seconds: 30),
                    ),
          );

      print('OrderService: Merge response status: ${response.statusCode}');
      print('OrderService: Merge response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          // Clear guest token after successful merge
          _guestToken = null;
          await _saveGuestTokenToStorage(
            _guestToken,
          ); // Clear guest token from storage

          final mergedCount = responseData['mergedCount'] ?? 0;
          print(
            '✅ OrderService: Successfully merged $mergedCount guest orders',
          );

          // Refresh user orders to include merged orders
          await getUserOrders(userId);

          return true;
        } else {
          throw Exception(responseData['message'] ?? 'فشل في دمج طلبات الضيف');
        }
      } else if (response.statusCode == 404) {
        // No guest orders found - this is not an error
        print('OrderService: No guest orders found to merge');
        _guestToken = null;
        await _saveGuestTokenToStorage(
          _guestToken,
        ); // Clear guest token from storage
        return true;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'خطأ في دمج طلبات الضيف');
      }
    } catch (e) {
      print('❌ OrderService: Error merging guest orders: $e');
      _setError('خطأ في دمج طلبات الضيف: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// تحديث guestToken يدوياً (مفيد للاختبار)
  void setGuestToken(String? token) {
    _guestToken = token;
    _saveGuestTokenToStorage(token); // Save guest token to storage
    if(token!=null) unawaited(LiveActivityService.setGuestToken(token));
    debugPrint('OrderService: Guest session updated');
  }

  /// مسح guestToken
  void clearGuestToken() {
    _guestToken = null;
    _saveGuestTokenToStorage(_guestToken); // Clear guest token from storage
    print('OrderService: Guest token cleared');
  }

  /// التحقق من وجود طلبات ضيف مُحتملة للدمج
  bool get hasGuestOrdersToMerge =>
      _guestToken != null && _guestToken!.isNotEmpty;

  /// التحقق من وجود guest token
  bool get hasGuestToken => _guestToken != null && _guestToken!.isNotEmpty;

  /// تحديث طلب في القائمة المحلية (للتحديثات الفورية)
  void updateOrderInList(OrderModel updatedOrder) {
    unawaited(LiveActivityService.syncOrder(updatedOrder));
    final index = _orders.indexWhere((order) => order.id == updatedOrder.id);
    if (index != -1) {
      final oldStatus = _orders[index].status;
      _orders[index] = updatedOrder;

      print(
        '✅ OrderService: تم تحديث الطلب ${updatedOrder.orderNumber} في القائمة المحلية',
      );
      print('   - الحالة القديمة: ${oldStatus.arabicName}');
      print('   - الحالة الجديدة: ${updatedOrder.status.arabicName}');

      // 🔔 إشعار جميع المستمعين بالتحديث الفوري
      notifyListeners();
      _syncLiveActivity(updatedOrder);
      print('📡 OrderService: تم إرسال notifyListeners() للتحديث الفوري');
    } else {
      print(
        '⚠️ OrderService: الطلب ${updatedOrder.id} غير موجود في القائمة المحلية',
      );
      // إضافة الطلب إذا لم يكن موجود
      addOrderToLocal(updatedOrder);
    }
  }

  /// إضافة طلب جديد للقائمة المحلية (للتحديثات الفورية)
  void addOrderToLocal(OrderModel newOrder) {
    final index = _orders.indexWhere((order) => order.id == newOrder.id);
    if (index == -1) {
      _orders.add(newOrder);

      print(
        '✅ OrderService: تم إضافة الطلب الجديد ${newOrder.orderNumber} للقائمة المحلية',
      );
      print('   - حالة الطلب: ${newOrder.status.arabicName}');
      print('   - إجمالي الطلبات الآن: ${_orders.length}');

      // 🔔 إشعار جميع المستمعين بالإضافة الفورية
      notifyListeners();
      print('📡 OrderService: تم إرسال notifyListeners() للإضافة الفورية');
    } else {
      print(
        '⚠️ OrderService: الطلب ${newOrder.id} موجود بالفعل في القائمة المحلية',
      );
    }
  }
}
