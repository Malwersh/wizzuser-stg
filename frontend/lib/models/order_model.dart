// lib/models/order_model.dart

import 'package:flutter/foundation.dart';
import 'package:foodapp_user/models/address_model.dart';

/// حالات الطلب المختلفة
enum OrderStatus {
  pending('pending', 'قيد الانتظار'),
  confirmed('confirmed', 'مؤكد'),
  preparing('preparing', 'يتم التحضير'),
  ready('ready', 'جاهز'),  // deprecated - use readyForPickup
  readyForPickup('ready_for_pickup', 'جاهز للاستلام'),
  assigned('assigned', 'تم تعيين سائق'),  // Backend uses this
  accepted('accepted', 'تم قبول الطلب من السائق'),
  reassigning('reassigning', 'جاري البحث عن سائق بديل'),  // When driver unassigns
  headingToStore('heading_to_store', 'السائق في الطريق للمطعم'),
  arrivedAtStore('arrived_at_store', 'السائق وصل للمطعم'),
  pickedUp('picked_up', 'تم استلام الطلب من المطعم'),
  onTheWay('on_the_way', 'في الطريق'),  // Legacy - maps to headingToCustomer
  headingToCustomer('heading_to_customer', 'السائق في الطريق للعميل'),
  arrivedAtCustomer('arrived_at_customer', 'السائق وصل للعميل'),
  returning('returning', 'السائق يعيد الطلب للمطعم'),
  returnArrived('return_arrived', 'بانتظار تأكيد استلام المطعم'),
  returned('returned', 'تم إرجاع الطلب للمطعم'),
  delivered('delivered', 'تم التوصيل'),
  cancelled('cancelled', 'ملغي'),
  failed('failed', 'فشل'),
  expired('expired', 'منتهي الصلاحية'),
  rejected('rejected', 'مرفوض');

  const OrderStatus(this.value, this.arabicName);
  
  final String value;
  final String arabicName;
  
  static OrderStatus fromString(String value) {
    // 🔧 FIX: Handle various cancellation status formats from backend
    // Backend may send: 'cancelled', 'canceled_by_customer', 'canceled_by_restaurant', etc.
    if (value.startsWith('canceled_by_') || value.startsWith('cancelled_by_')) {
      return OrderStatus.cancelled;
    }
    
    return OrderStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => OrderStatus.pending,
    );
  }
}

/// طرق الدفع المتاحة
enum PaymentMethod {
  cash('cash', 'دفع نقدي', true),
  card('card', 'بطاقة ائتمانية (قريباً)', false),
  wallet('wallet', 'محفظة رقمية (قريباً)', false);

  const PaymentMethod(this.value, this.arabicName, this.isEnabled);
  
  final String value;
  final String arabicName;
  final bool isEnabled;
  
  static PaymentMethod fromString(String value) {
    return PaymentMethod.values.firstWhere(
      (method) => method.value == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

/// عنصر واحد في الطلب
class OrderItem {
  final String id;
  final String dishId;
  final String productId; // إضافة productId
  final String dishName;
  final String? dishDescription;
  final String? dishImage;
  final double unitPrice;
  final int quantity;
  final double totalPrice;
  final Map<String, List<String>>? selectedOptions;
  final String? specialInstructions;

  OrderItem({
    required this.id,
    required this.dishId,
    required this.productId, // إضافة productId للـ constructor
    required this.dishName,
    this.dishDescription,
    this.dishImage,
    required this.unitPrice,
    required this.quantity,
    required this.totalPrice,
    this.selectedOptions,
    this.specialInstructions,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    // Handle customizations as both list and map
    Map<String, List<String>>? parsedOptions;
    final customizations = json['customizations'] ?? json['selected_options'];
    if (customizations != null) {
      if (customizations is List) {
        // If customizations is a list, convert to map
        parsedOptions = <String, List<String>>{};
        for (var item in customizations) {
          if (item is Map<String, dynamic>) {
            final key = item['name'] ?? item['option'] ?? 'option';
            final value = item['value'] ?? item['selection'] ?? '';
            if (parsedOptions[key] == null) {
              parsedOptions[key] = [];
            }
            parsedOptions[key]!.add(value.toString());
          }
        }
      } else if (customizations is Map<String, dynamic>) {
        // If customizations is a map, convert to correct format
        parsedOptions = Map<String, List<String>>.from(
          customizations.map(
            (key, value) => MapEntry(key, List<String>.from(value is List ? value : [value.toString()])),
          ),
        );
      }
    }

    return OrderItem(
      id: json['id'] ?? json['productId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      dishId: json['dish_id'] ?? json['productId'] ?? json['id'] ?? '',
      productId: json['product_id'] ?? json['productId'] ?? json['dish_id'] ?? json['id'] ?? '',
      dishName: json['dish_name'] ?? json['productName'] ?? json['name'] ?? 'طبق غير محدد',
      dishDescription: json['dish_description'] ?? json['description'],
      dishImage: json['dish_image'] ?? json['image'],
      unitPrice: json['unit_price'] != null || json['price'] != null
          ? (json['unit_price'] ?? json['price'] as num).toDouble()
          : ((json['unitPrice'] ?? 0) as num).toDouble() / 1000,
      quantity: (json['quantity'] ?? 1) as int,
      totalPrice: (json['total_price'] ?? json['totalPrice']) != null
          ? ((json['total_price'] ?? json['totalPrice']) as num).toDouble()
          : json['unitPrice'] != null && json['unit_price'] == null && json['price'] == null
              ? (json['unitPrice'] as num).toDouble() / 1000 * ((json['quantity'] ?? 1) as num)
              : ((json['price'] ?? 0) as num).toDouble(),
      selectedOptions: parsedOptions,
      specialInstructions: json['special_instructions'] ?? json['specialInstructions'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dish_id': dishId,
      'product_id': productId,
      'dish_name': dishName,
      'dish_description': dishDescription,
      'dish_image': dishImage,
      'unit_price': unitPrice,
      'quantity': quantity,
      'total_price': totalPrice,
      'selected_options': selectedOptions,
      'special_instructions': specialInstructions,
    };
  }

  /// إنشاء OrderItem من CartItem
  factory OrderItem.fromCartItem(Map<String, dynamic> cartItem) {
    return OrderItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dishId: cartItem['id'] ?? cartItem['dish_id'] ?? '',
      productId: cartItem['productId'] ?? cartItem['id'] ?? cartItem['dish_id'] ?? '',
      dishName: cartItem['name'] ?? 'طبق غير محدد',
      dishDescription: cartItem['description'],
      dishImage: cartItem['image'],
      unitPrice: (cartItem['base_price'] as num?)?.toDouble() ?? 
                 (cartItem['price'] as num?)?.toDouble() ?? 0.0,
      quantity: cartItem['quantity'] ?? 1,
      totalPrice: (cartItem['price'] as num?)?.toDouble() ?? 0.0,
      selectedOptions: cartItem['selected_options'] != null
          ? Map<String, List<String>>.from(cartItem['selected_options'])
          : null,
      specialInstructions: cartItem['special_instructions'],
    );
  }
}

/// نموذج الطلب الكامل
class OrderModel {
  final String id;
  final String orderNumber;
  final String userId;
  final String storeId;
  final String storeName;
  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double serviceFee;
  final double tip;
  final double tax;
  final double discount;
  final double total;
  final OrderStatus status;
  final String? returnStatus;
  final PaymentMethod paymentMethod;
  final String? paymentStatus;
  final bool driverSearchUnavailable;
  final DetailedAddress deliveryAddress;
  final String? deliveryInstructions;
  final String? customerPhone;
  final String? customerName;
  final String? customerEmail;
  final bool isGuestOrder;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? confirmedAt;
  final DateTime? estimatedDeliveryTime;
  final Map<String, dynamic>? deliveryEstimate;
  final DateTime? estimatedReadyAt;
  final int? estimatedPreparationTime;
  final DateTime? actualDeliveryTime;
  final String? cancelReason;
  final String? cancellationStatus;
  final String? cancellationCaseId;
  final Map<String, dynamic>? metadata;
  
  // معلومات السائق
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleType;
  final String? vehiclePlate;

  OrderModel({
    required this.id,
    required this.orderNumber,
    required this.userId,
    required this.storeId,
    required this.storeName,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    this.serviceFee = 0,
    this.tip = 0,
    required this.tax,
    required this.discount,
    required this.total,
    required this.status,
    this.returnStatus,
    required this.paymentMethod,
    this.paymentStatus,
    this.driverSearchUnavailable = false,
    required this.deliveryAddress,
    this.deliveryInstructions,
    this.customerPhone,
    this.customerName,
    this.customerEmail,
    this.isGuestOrder = false,
    required this.createdAt,
    this.updatedAt,
    this.confirmedAt,
    this.estimatedDeliveryTime,
    this.deliveryEstimate,
    this.estimatedReadyAt,
    this.estimatedPreparationTime,
    this.actualDeliveryTime,
    this.cancelReason,
    this.cancellationStatus,
    this.cancellationCaseId,
    this.metadata,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.vehicleType,
    this.vehiclePlate,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // Parse items safely
    List<OrderItem> orderItems = [];
    final itemsData = json['items'];
    if (itemsData is List) {
      orderItems = itemsData
          .where((item) => item != null)
          .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    // Handle pricing structure from backend - new format has pricing object
    final pricing = json['pricing'] as Map<String, dynamic>?;
    
    final model = OrderModel(
      id: json['id'] ?? json['orderId'] ?? '',
      orderNumber: json['order_number'] ?? json['orderNumber'] ?? 'غير محدد',
      userId: json['user_id'] ?? json['userId'] ?? '',
      storeId: json['store_id'] ?? json['storeId'] ?? '',
      storeName: json['store_name'] ?? json['storeName'] ?? 'متجر غير محدد',
      items: orderItems,
      subtotal: pricing != null 
          ? (pricing['goodsSubtotal'] ?? 0 as num).toDouble() / 1000  // Convert from fils to IQD
          : (json['subtotal'] ?? 0 as num).toDouble(),
      deliveryFee: pricing != null 
          ? (pricing['deliveryFee'] ?? 0 as num).toDouble() / 1000  // Convert from fils to IQD
          : (json['delivery_fee'] ?? json['deliveryFee'] ?? 0 as num).toDouble(),
      serviceFee: pricing != null ? ((pricing['serviceFee'] ?? 0) as num).toDouble() / 1000 : ((json['service_fee'] ?? 0) as num).toDouble(),
      tip: pricing != null ? ((pricing['tip'] ?? 0) as num).toDouble() / 1000 : ((json['tip'] ?? 0) as num).toDouble(),
      tax: pricing != null 
          ? (pricing['tax'] ?? 0 as num).toDouble() / 1000  // Convert from fils to IQD
          : (json['tax'] ?? 0 as num).toDouble(),
      discount: pricing != null 
          ? (pricing['discount'] ?? 0 as num).toDouble() / 1000  // Convert from fils to IQD
          : (json['discount'] ?? 0 as num).toDouble(),
      total: pricing != null 
          ? (pricing['total'] ?? 0 as num).toDouble() / 1000  // Convert from fils to IQD
          : (json['total'] ?? json['totalAmount'] ?? 0 as num).toDouble(),
      status: OrderStatus.fromString(json['status'] ?? 'pending'),
      returnStatus: json['returnStatus']?.toString(),
      paymentMethod: PaymentMethod.fromString(json['payment_method'] ?? json['paymentMethod'] ?? 'cash'),
      paymentStatus: json['payment_status'] ?? json['paymentStatus'],
      driverSearchUnavailable: json['driverSearchUnavailable'] == true &&
          (json['driver_id'] ?? json['driverId'] ?? json['assignedDriverId']) == null &&
          ['ready_for_pickup', 'ready', 'reassigning'].contains(json['status']),
      deliveryAddress: DetailedAddress.fromJson(json['deliveryAddress'] ?? json['delivery_address'] ?? {}),
      deliveryInstructions: json['delivery_instructions'] ?? json['deliveryInstructions'],
      customerPhone: json['customer_phone'] ?? json['customerPhone'],
      customerName: json['customer_name'] ?? json['customerName'],
      customerEmail: json['customer_email'] ?? json['customerEmail'],
      isGuestOrder: json['is_guest_order'] ?? json['isGuestOrder'] ?? false,
      updatedAt: DateTime.tryParse((json['updatedAt']??json['updated_at']??'').toString()),
      createdAt: DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? json['orderDate'] ?? '') ?? DateTime.now(),
      confirmedAt: (json['confirmed_at'] ?? json['confirmedAt']) != null
          ? DateTime.tryParse(json['confirmed_at'] ?? json['confirmedAt'])
          : null,
      estimatedDeliveryTime: (json['estimated_delivery_time'] ?? json['estimatedDeliveryTime']) != null
          ? DateTime.tryParse(json['estimated_delivery_time'] ?? json['estimatedDeliveryTime'])
          : null,
      deliveryEstimate: json['deliveryEstimate'] is Map ? Map<String,dynamic>.from(json['deliveryEstimate']) : null,
      estimatedReadyAt: DateTime.tryParse(json['estimatedReadyAt']?.toString() ?? ''),
      estimatedPreparationTime: (json['estimatedPreparationTime'] as num?)?.toInt(),
      actualDeliveryTime: (json['actual_delivery_time'] ?? json['actualDeliveryTime']) != null
          ? DateTime.tryParse(json['actual_delivery_time'] ?? json['actualDeliveryTime'])
          : null,
      cancelReason: json['cancel_reason'] ?? json['cancelReason'],
      cancellationStatus: json['exceptionCancellation'] is Map ? json['exceptionCancellation']['state'] as String? : null,
      cancellationCaseId: json['exceptionCancellation'] is Map ? json['exceptionCancellation']['caseId'] as String? : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
      driverId: json['driver_id'] ?? json['driverId'],
      driverName: json['driver_name'] ?? json['driverName'] ?? json['name'],
      driverPhone: json['driver_phone'] ?? json['driverPhone'],
      vehicleType: json['vehicle_type'] ?? json['vehicleType'],
      vehiclePlate: json['vehicle_plate'] ?? json['vehiclePlate'] ?? json['license_number'] ?? json['licenseNumber'],
    );
    
    debugPrint('🚗 OrderModel.fromJson - Driver Info:'
        '\n   driverId: ${json['driver_id'] ?? json['driverId']}'
        '\n   driverName: ${json['driver_name'] ?? json['driverName'] ?? json['name']}'
        '\n   vehicleType: ${json['vehicle_type'] ?? json['vehicleType']}'
        '\n   vehiclePlate: ${json['vehicle_plate'] ?? json['vehiclePlate'] ?? json['license_number'] ?? json['licenseNumber']}');
    
    return model;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'user_id': userId,
      'store_id': storeId,
      'store_name': storeName,
      'driverSearchUnavailable': driverSearchUnavailable,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'delivery_fee': deliveryFee,
      'service_fee': serviceFee,
      'tip': tip,
      'tax': tax,
      'discount': discount,
      'total': total,
      'status': status.value,
      'returnStatus': returnStatus,
      'payment_method': paymentMethod.value,
      'payment_status': paymentStatus,
      'delivery_address': deliveryAddress.toJson(),
      'delivery_instructions': deliveryInstructions,
      'customer_phone': customerPhone,
      'customer_name': customerName,
      'customer_email': customerEmail,
      'is_guest_order': isGuestOrder,
      'created_at': createdAt.toIso8601String(),
      'confirmed_at': confirmedAt?.toIso8601String(),
      'estimated_delivery_time': estimatedDeliveryTime?.toIso8601String(),
      'deliveryEstimate': deliveryEstimate,
      'estimatedReadyAt': estimatedReadyAt?.toIso8601String(),
      'estimatedPreparationTime': estimatedPreparationTime,
      'actual_delivery_time': actualDeliveryTime?.toIso8601String(),
      'cancel_reason': cancelReason,
      if(cancellationStatus != null) 'exceptionCancellation': {'state':cancellationStatus,'caseId':cancellationCaseId},
      'metadata': metadata,
    };
  }

  /// إنشاء طلب جديد من السلة
  factory OrderModel.fromCart({
    required String userId,
    required String storeId,
    required String storeName,
    required List<Map<String, dynamic>> cartItems,
    required DetailedAddress deliveryAddress,
    required PaymentMethod paymentMethod,
    double deliveryFee = 10.0,
    double taxRate = 0.0,
    double discount = 0.0,
    String? deliveryInstructions,
    String? customerPhone,
    String? customerName,
  }) {
    final orderItems = cartItems
        .map((cartItem) => OrderItem.fromCartItem(cartItem))
        .toList();

    final subtotal = orderItems.fold<double>(
      0.0,
      (sum, item) => sum + item.totalPrice,
    );

    final tax = subtotal * taxRate;
    final total = subtotal + deliveryFee + tax - discount;

    final now = DateTime.now();
    final orderNumber = 'ORD${now.millisecondsSinceEpoch}';

    return OrderModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      orderNumber: orderNumber,
      userId: userId,
      storeId: storeId,
      storeName: storeName,
      items: orderItems,
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
      createdAt: now,
      estimatedDeliveryTime: null,
    );
  }

  /// نسخة محدثة من الطلب
  OrderModel copyWith({
    OrderStatus? status,
    String? returnStatus,
    String? paymentStatus,
    DateTime? confirmedAt,
    DateTime? estimatedDeliveryTime,
    DateTime? actualDeliveryTime,
    String? cancelReason,
    Map<String, dynamic>? metadata,
  }) {
    return OrderModel(
      id: id,
      orderNumber: orderNumber,
      userId: userId,
      storeId: storeId,
      storeName: storeName,
      items: items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      serviceFee: serviceFee,
      tip: tip,
      tax: tax,
      discount: discount,
      total: total,
      status: status ?? this.status,
      returnStatus: returnStatus ?? this.returnStatus,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      driverSearchUnavailable: driverSearchUnavailable,
      deliveryAddress: deliveryAddress,
      deliveryInstructions: deliveryInstructions,
      customerPhone: customerPhone,
      customerName: customerName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      estimatedDeliveryTime: estimatedDeliveryTime ?? this.estimatedDeliveryTime,
      deliveryEstimate: deliveryEstimate,
      estimatedReadyAt: estimatedReadyAt,
      estimatedPreparationTime: estimatedPreparationTime,
      customerEmail: customerEmail,
      isGuestOrder: isGuestOrder,
      driverId: driverId,
      driverName: driverName,
      driverPhone: driverPhone,
      vehicleType: vehicleType,
      vehiclePlate: vehiclePlate,
      actualDeliveryTime: actualDeliveryTime ?? this.actualDeliveryTime,
      cancelReason: cancelReason ?? this.cancelReason,
      cancellationStatus: cancellationStatus,
      cancellationCaseId: cancellationCaseId,
      metadata: metadata ?? this.metadata,
    );
  }

  /// التحقق من إمكانية إلغاء الطلب
  bool get canBeCancelled {
    return [OrderStatus.pending,OrderStatus.confirmed,OrderStatus.preparing,OrderStatus.ready,OrderStatus.readyForPickup,OrderStatus.reassigning,OrderStatus.assigned,OrderStatus.accepted,OrderStatus.headingToStore,OrderStatus.arrivedAtStore].contains(status);
  }

  /// التحقق من إمكانية تتبع الطلب
  bool get canBeTracked {
    return status != OrderStatus.cancelled && 
           status != OrderStatus.failed && 
           status != OrderStatus.delivered;
  }

  /// وقت التوصيل المتوقع بصيغة نصية
  String get estimatedDeliveryText {
    if (estimatedDeliveryTime == null) return 'غير محدد';
    
    final now = DateTime.now();
    final difference = estimatedDeliveryTime!.difference(now);
    
    if (difference.isNegative) return 'متأخر';
    
    final minutes = difference.inMinutes;
    if (minutes < 60) {
      return '$minutes دقيقة';
    } else {
      final hours = difference.inHours;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '$hours ساعة';
      } else {
        return '$hours ساعة و $remainingMinutes دقيقة';
      }
    }
  }
}
