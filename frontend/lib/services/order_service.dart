// lib/services/order_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/order_model.dart';
import '../models/address_model.dart';
import '../models/store_discount.dart';
import '../models/platform_promo.dart';
import "session_service.dart";
import '../config/api_config.dart';

class OrderService extends ChangeNotifier {
  static final OrderService _instance = OrderService._internal();
  factory OrderService() => _instance;
  OrderService._internal();

  // Base URL for orders API
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }
  
  List<OrderModel> _orders = [];
  OrderModel? _currentOrder;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<OrderModel> get orders => List.unmodifiable(_orders);
  OrderModel? get currentOrder => _currentOrder;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// إنشاء طلب جديد
  Future<Map<String, dynamic>> createOrder({
    required String storeId,
    required String storeName,
    String? storeAddress, // عنوان المطعم للسائقين
    String? storeImage, // صورة المطعم للسائقين
    required List<Map<String, dynamic>> cartItems,
    required DetailedAddress deliveryAddress,
    required PaymentMethod paymentMethod,
    double deliveryFee = 10.0,
    double taxRate = 0.0,
    double discount = 0.0,
    String? deliveryInstructions,
    String? promoCode,
    String? discountId,
    // معلومات المستخدم الإضافية
    String? userId, // null للضيوف
    String? customerName,
    String? customerPhone,
    String? customerEmail,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      // التحقق من المعلومات المطلوبة
      if (customerName == null || customerName.isEmpty) {
        throw Exception('اسم العميل مطلوب');
      }
      if (customerPhone == null || customerPhone.isEmpty) {
        throw Exception('رقم هاتف العميل مطلوب');
      }

      // حساب الإجمالي المحلي كنسخة احتياطية
      double calculateSubtotal() {
        return cartItems.fold(0.0, (sum, item) {
          final price = double.tryParse(item['price'].toString()) ?? 0.0;
          final quantity = item['quantity'] ?? 1;
          return sum + (price * quantity);
        });
      }

      final calculatedSubtotal = calculateSubtotal();
      final calculatedTax = calculatedSubtotal * taxRate;
      final calculatedTotal = calculatedSubtotal + deliveryFee + calculatedTax - discount;

      print('OrderService: Local calculations:');
      print('- Subtotal: $calculatedSubtotal');
      print('- Delivery Fee: $deliveryFee');
      print('- Tax: $calculatedTax');
      print('- Discount: $discount');
      print('- Total: $calculatedTotal');

      // التأكد من أن العنوان يحتوي على fullAddress صحيح
      String ensureFullAddress(DetailedAddress address) {
        if (address.fullAddress.isNotEmpty && 
            address.fullAddress != 'عنوان غير محدد' && 
            address.fullAddress.trim().isNotEmpty) {
          return address.fullAddress;
        }

        // إعادة بناء العنوان من المكونات
        List<String> parts = [];
        
        if (address.detailedAddress != null && address.detailedAddress!.trim().isNotEmpty) {
          parts.add(address.detailedAddress!.trim());
        }
        if (address.neighborhood.isNotEmpty && address.neighborhood != 'غير محدد') {
          parts.add(address.neighborhood);
        }
        if (address.district.isNotEmpty && address.district != 'غير محدد') {
          parts.add(address.district);
        }
        if (address.province.isNotEmpty && address.province != 'غير محدد') {
          parts.add(address.province);
        }
        if (address.landmark.isNotEmpty && address.landmark != 'غير محدد') {
          parts.add('قرب ${address.landmark}');
        }

        final rebuiltAddress = parts.isNotEmpty ? parts.join('، ') : address.name;
        print('OrderService: Rebuilt address: $rebuiltAddress');
        return rebuiltAddress;
      }

      final validatedFullAddress = ensureFullAddress(deliveryAddress);

      // استخدام API endpoint الصحيح
      final apiUrl = ApiConfig.buildUrl(ApiConfig.ordersEndpoint);

      // تحضير بيانات الطلب للإرسال بالصيغة التي يتوقعها الباك إند الجديد
      final orderData = {
        'storeId': storeId,
        'storeName': storeName,
        'storeAddress': storeAddress ?? 'العنوان غير محدد', // عنوان المطعم للسائقين
        'storeImage': storeImage, // صورة المطعم للسائقين
        'items': cartItems.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'price': item['price'].toString(),
          'quantity': item['quantity'],
          'imageUrl': item['imageUrl'] ?? item['image'] ?? '', // صورة الطبق للسائقين
          'customizations': item['selectedOptions'] ?? [],
          'specialInstructions': item['special_instructions'] ?? '',
        }).toList(),
        'deliveryAddress': {
          'id': deliveryAddress.id,
          'fullAddress': validatedFullAddress,
          'latitude': deliveryAddress.latitude,
          'longitude': deliveryAddress.longitude,
          'phoneNumber': deliveryAddress.phoneNumber,
          'name': deliveryAddress.name,
          'province': deliveryAddress.province,
          'district': deliveryAddress.district,
          'neighborhood': deliveryAddress.neighborhood,
          'landmark': deliveryAddress.landmark,
          'detailed_address': deliveryAddress.detailedAddress,
          'building_number': deliveryAddress.buildingNumber,
          'floor_number': deliveryAddress.floorNumber,
          'apartment_number': deliveryAddress.apartmentNumber,
        },
        'paymentMethod': paymentMethod.value.toLowerCase(),
        'deliveryFee': deliveryFee,
        'taxRate': taxRate,
        'discount': discount,
        'deliveryInstructions': deliveryInstructions,
        'promoCode': promoCode,
        'discountId': discountId,
        'userId': userId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerEmail': customerEmail,
        // إضافة الحسابات المحلية كنسخة احتياطية
        'subtotal': calculatedSubtotal,
        'total': calculatedTotal,
      };

      print('OrderService: Sending order data to backend:');
      print('- API URL: $apiUrl');
      print('- Store ID: $storeId');
      print('- Customer: $customerName ($customerPhone)');
      print('- Items: ${cartItems.length}');
      print('- Delivery Fee: $deliveryFee');
      print('- Validated Address: $validatedFullAddress');
      print('- Order Data: ${jsonEncode(orderData)}');

      // إرسال الطلب للخادم
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (SessionService().accessToken?.isNotEmpty == true)
            'Authorization': 'Bearer ${SessionService().accessToken}',
        },
        body: jsonEncode(orderData),
      );

      print('OrderService: Response status: ${response.statusCode}');
      print('OrderService: Response body: ${response.body}');

      final responseData = jsonDecode(response.body);


      if (response.statusCode == 201 || response.statusCode == 200) {
        // نجح إنشاء الطلب
        if (responseData['success'] == true && responseData['order'] != null) {
          // تحويل البيانات المرجعة إلى OrderModel
          final backendOrder = responseData['order'];
          
          // استخدام قيم الخادم أو الحسابات المحلية كنسخة احتياطية
          final backendSubtotal = backendOrder['subtotal']?.toDouble();
          final backendTotal = backendOrder['totalAmount']?.toDouble() ?? backendOrder['total']?.toDouble();
          final backendDeliveryFee = backendOrder['deliveryFee']?.toDouble();
          final backendTax = backendOrder['tax']?.toDouble();
          final backendDiscount = backendOrder['discount']?.toDouble();

          print('OrderService: Backend response values:');
          print('- Backend Subtotal: $backendSubtotal');
          print('- Backend Total: $backendTotal');
          print('- Backend Delivery Fee: $backendDeliveryFee');
          print('- Backend Tax: $backendTax');
          print('- Backend Discount: $backendDiscount');

          // إنشاء عنوان محدث مع fullAddress صحيح
          final updatedDeliveryAddress = deliveryAddress.copyWith(
            fullAddress: validatedFullAddress,
          );

          // إنشاء OrderModel من البيانات المرجعة مع استخدام القيم المحسوبة محلياً كنسخة احتياطية
          final createdOrder = OrderModel(
            id: backendOrder['id'] ?? backendOrder['orderId'],
            orderNumber: backendOrder['orderNumber'],
            userId: userId ?? 'guest',
            storeId: storeId,
            storeName: storeName,
            items: cartItems.map((item) => OrderItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              dishId: item['id'] ?? '',
              productId: item['id'] ?? '',
              dishName: item['name'] ?? '',
              dishDescription: item['description'] ?? '',
              dishImage: item['image'] ?? '',
              unitPrice: double.tryParse(item['price'].toString()) ?? 0.0,
              quantity: item['quantity'] ?? 1,
              totalPrice: (double.tryParse(item['price'].toString()) ?? 0.0) * (item['quantity'] ?? 1),
              selectedOptions: item['selectedOptions'] != null 
                  ? Map<String, List<String>>.from(
                      (item['selectedOptions'] as Map<String, dynamic>).map(
                        (k, v) => MapEntry(k, List<String>.from(v is List ? v : [v.toString()])),
                      ),
                    )
                  : null,
              specialInstructions: item['special_instructions'] ?? '',
            )).toList(),
            subtotal: backendSubtotal ?? calculatedSubtotal,
            deliveryFee: backendDeliveryFee ?? deliveryFee,
            tax: backendTax ?? calculatedTax,
            discount: backendDiscount ?? discount,
            total: backendTotal ?? calculatedTotal,
            paymentMethod: paymentMethod,
            status: OrderStatus.pending,
            deliveryAddress: updatedDeliveryAddress,
            deliveryInstructions: deliveryInstructions,
            customerPhone: customerPhone,
            customerName: customerName,
            customerEmail: customerEmail,
            createdAt: DateTime.now(),
            estimatedDeliveryTime: backendOrder['estimatedDeliveryTime'] != null 
                ? DateTime.tryParse(backendOrder['estimatedDeliveryTime'])
                : DateTime.now().add(const Duration(minutes: 45)),
          );
          
          _currentOrder = createdOrder;
          _orders.insert(0, createdOrder);
          
          notifyListeners();
          
          print('OrderService: Order created successfully:');
          print('- Order ID: ${createdOrder.id}');
          print('- Order Total: ${createdOrder.total}');
          print('- Address: ${createdOrder.deliveryAddress.fullAddress}');
          
          return {
            'success': true,
            'order': createdOrder,
            'message': 'تم إنشاء الطلب بنجاح'
          };
        } else {
          throw Exception('استجابة غير صالحة من الخادم');
        }
      } else if (response.statusCode == 409) {
        // لديك طلب نشط بالفعل (Conflict) — سياسة الطلب الواحد النشط
        final errorMessage = responseData['error'] ??
            responseData['message'] ??
            'لديك طلب نشط بالفعل. يجب انتظار إتمام الطلب الحالي قبل إنشاء طلب جديد.';
        print('OrderService: Active order conflict (409): $errorMessage');
        _setError(errorMessage);
        return {
          'success': false,
          'message': errorMessage,
          'statusCode': 409,
          'errorType': 'ACTIVE_ORDER_CONFLICT',
          'activeOrderDetails': responseData['activeOrder'],
        };
      } else {
        // فشل في إنشاء الطلب
        final errorMessage = responseData['error'] ??
            responseData['message'] ??
            'فشل في إنشاء الطلب';
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('OrderService: Error creating order: $e');
      _setError('خطأ في إنشاء الطلب: ${e.toString()}');
      return {
        'success': false,
        'message': e.toString(),
      };
    } finally {
      _setLoading(false);
    }
  }

  /// جلب طلبات المستخدم
  Future<void> getOrders({
    int page = 1,
    int limit = 20,
    OrderStatus? status,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final sessionService = SessionService.instance;
      if (!sessionService.isLoggedIn) {
        throw Exception('يجب تسجيل الدخول أولاً');
      }

      final userId = sessionService.currentUserId!;
      final token = sessionService.accessToken;

      if (token == null) {
        throw Exception('لم يتم العثور على رمز المصادقة');
      }

      // تحضير معاملات الاستعلام
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'user_id': userId,
      };

      if (status != null) {
        queryParams['status'] = status.value;
      }

      final uri = Uri.parse('$_baseUrl/orders').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final ordersData = responseData['data'] as List;
        final orders = ordersData.map((orderJson) => OrderModel.fromJson(orderJson)).toList();
        
        if (page == 1) {
          _orders = orders;
        } else {
          _orders.addAll(orders);
        }
        
        notifyListeners();
      } else {
        final errorMessage = responseData['message'] ?? 'فشل في جلب الطلبات';
        throw Exception(errorMessage);
      }
    } catch (e) {
      _setError('خطأ في جلب الطلبات: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  /// جلب تفاصيل طلب محدد
  Future<OrderModel?> getOrderDetails(String orderId) async {
    try {
      _setLoading(true);
      _clearError();

      final sessionService = SessionService.instance;
      if (!sessionService.isLoggedIn) {
        throw Exception('يجب تسجيل الدخول أولاً');
      }

      final token = sessionService.accessToken;

      if (token == null) {
        throw Exception('لم يتم العثور على رمز المصادقة');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/orders/$orderId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final order = OrderModel.fromJson(responseData['data']);
        
        // تحديث الطلب في القائمة إذا كان موجوداً
        final index = _orders.indexWhere((o) => o.id == orderId);
        if (index != -1) {
          _orders[index] = order;
          notifyListeners();
        }
        
        return order;
      } else {
        final errorMessage = responseData['message'] ?? 'فشل في جلب تفاصيل الطلب';
        throw Exception(errorMessage);
      }
    } catch (e) {
      _setError('خطأ في جلب تفاصيل الطلب: ${e.toString()}');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// إلغاء طلب
  Future<bool> cancelOrder(String orderId, {String? reason}) async {
    try {
      _setLoading(true);
      _clearError();

      final sessionService = SessionService.instance;
      if (!sessionService.isLoggedIn) {
        throw Exception('يجب تسجيل الدخول أولاً');
      }

      final token = sessionService.accessToken;

      if (token == null) {
        throw Exception('لم يتم العثور على رمز المصادقة');
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/orders/$orderId/cancel'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reason': reason ?? 'Order cancelled by user',
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // تحديث الطلب في القائمة
        final index = _orders.indexWhere((o) => o.id == orderId);
        if (index != -1) {
          _orders[index] = _orders[index].copyWith(
            status: OrderStatus.cancelled,
            cancelReason: reason ?? 'Order cancelled by user',
          );
          notifyListeners();
        }
        
        return true;
      } else {
        final errorMessage = responseData['message'] ?? 'فشل في إلغاء الطلب';
        throw Exception(errorMessage);
      }
    } catch (e) {
      _setError('خطأ في إلغاء الطلب: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// تتبع طلب (جلب حالة محدثة)
  Future<OrderModel?> trackOrder(String orderId) async {
    try {
      final sessionService = SessionService.instance;
      if (!sessionService.isLoggedIn) {
        return null;
      }

      final token = sessionService.accessToken;

      if (token == null) {
        return null;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/orders/$orderId/track'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final order = OrderModel.fromJson(responseData['data']);
        
        // تحديث الطلب في القائمة
        final index = _orders.indexWhere((o) => o.id == orderId);
        if (index != -1) {
          _orders[index] = order;
          notifyListeners();
        }
        
        return order;
      }
    } catch (e) {
      debugPrint('خطأ في تتبع الطلب: $e');
    }
    
    return null;
  }

  /// الحصول على الطلبات النشطة (غير مكتملة)
  List<OrderModel> get activeOrders {
    return _orders.where((order) => 
      order.status != OrderStatus.delivered && 
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.failed
    ).toList();
  }

  /// الحصول على الطلبات المكتملة
  List<OrderModel> get completedOrders {
    return _orders.where((order) => 
      order.status == OrderStatus.delivered ||
      order.status == OrderStatus.cancelled ||
      order.status == OrderStatus.failed
    ).toList();
  }

  /// جلب أكواد الخصم الفعالة من المنصة المركزية
  Future<List<PlatformPromo>> getActivePromoCodes() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/promo-codes/active'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final list = (responseData['promos'] as List?) ?? const [];
        return list
            .map((p) => PlatformPromo.fromJson(Map<String, dynamic>.from(p)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('خطأ في جلب أكواد الخصم: $e');
      return [];
    }
  }

  /// التحقق من كود خصم منصة وحساب قيمته من الخادم
  Future<Map<String, dynamic>> validatePromoCode({
    required String code,
    required double orderTotal,
    double deliveryFee = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/promo-codes/validate'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'code': code,
          'orderTotal': orderTotal,
          'deliveryFee': deliveryFee,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['valid'] == true) {
        return {
          'success': true,
          'valid': true,
          'discount': (responseData['discountAmount'] as num?)?.toDouble() ?? 0.0,
          'finalTotal': (responseData['finalTotal'] as num?)?.toDouble(),
        };
      }
      return {
        'success': false,
        'valid': false,
        'message': responseData['message'] ?? 'كود الخصم غير صالح',
      };
    } catch (e) {
      return {
        'success': false,
        'valid': false,
        'message': 'خطأ في التحقق من كود الخصم: ${e.toString()}',
      };
    }
  }

  /// جلب العروض/الخصومات الفعالة لمتجر معين
  Future<List<StoreDiscount>> getStoreDiscounts(String storeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/business/$storeId/discounts'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final list = (responseData['discounts'] as List?) ?? const [];
        return list
            .map((d) => StoreDiscount.fromJson(Map<String, dynamic>.from(d)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('خطأ في جلب خصومات المتجر: $e');
      return [];
    }
  }

  /// التحقق من خصم تاجر وحساب قيمته من الخادم
  Future<Map<String, dynamic>> validateDiscount({
    required String storeId,
    required String discountId,
    required double orderTotal,
    required List<Map<String, dynamic>> items,
    double deliveryFee = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/promo-codes/apply'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'businessId': storeId,
          'discountId': discountId,
          'orderTotal': orderTotal,
          'deliveryFee': deliveryFee,
          'items': items.map((item) => {
            'id': item['id'],
            'categoryId': item['categoryId'] ?? item['category_id'],
            'price': item['price'].toString(),
            'quantity': item['quantity'] ?? 1,
          }).toList(),
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['valid'] == true) {
        return {
          'success': true,
          'valid': true,
          'discount': (responseData['discountAmount'] as num?)?.toDouble() ?? 0.0,
          'finalTotal': (responseData['finalTotal'] as num?)?.toDouble(),
        };
      }
      return {
        'success': false,
        'valid': false,
        'message': responseData['message'] ?? 'الخصم غير صالح',
      };
    } catch (e) {
      return {
        'success': false,
        'valid': false,
        'message': 'خطأ في التحقق من الخصم: ${e.toString()}',
      };
    }
  }

  /// مسح البيانات عند تسجيل الخروج
  void clearData() {
    _orders.clear();
    _currentOrder = null;
    _clearError();
    notifyListeners();
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

  /// تحديث حالة طلب (للاستخدام الداخلي أو WebSocket)
  void updateOrderStatus(String orderId, OrderStatus newStatus, {
    DateTime? confirmedAt,
    DateTime? estimatedDeliveryTime,
    DateTime? actualDeliveryTime,
  }) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      _orders[index] = _orders[index].copyWith(
        status: newStatus,
        confirmedAt: confirmedAt,
        estimatedDeliveryTime: estimatedDeliveryTime,
        actualDeliveryTime: actualDeliveryTime,
      );
      notifyListeners();
    }
  }

  /// إضافة طلب للقائمة المحلية
  void addOrderToList(OrderModel order) {
    _orders.insert(0, order);
    notifyListeners();
  }
}
