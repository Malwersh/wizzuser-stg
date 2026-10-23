// lib/models/business_model.dart
import 'dart:math';
import 'dart:developer' as developer;
import 'business_address.dart';

class BusinessModel {
  final String id;
  final String businessName;
  final String address; // العنوان الأصلي كـ string للتوافق
  final BusinessAddress? businessAddress; // العنوان المُحلل للعرض المحسن
  final String businessPhotoUrl;
  final String businessType;
  final bool isActive;
  final double rating;
  final String distance;
  final String deliveryFee;
  final String deliveryTime;
  final String phone;
  final String email;
  final double? latitude; // إحداثيات GPS
  final double? longitude; // إحداثيات GPS
  final Map<String, dynamic>? metadata;

  BusinessModel({
    required this.id,
    required this.businessName,
    required this.address,
    this.businessAddress,
    required this.businessPhotoUrl,
    required this.businessType,
    this.isActive = true,
    this.rating = 0.0,
    this.distance = '',
    this.deliveryFee = '',
    this.deliveryTime = '',
    this.phone = '',
    this.email = '',
    this.latitude,
    this.longitude,
    this.metadata,
  });

  int? get averagePreparationMinutes {
    final value=metadata?['averagePreparationMinutes'] ?? metadata?['orderReceptionSettings']?['defaultPreparationMinutes'];
    return value is int && value>=5 && value<=120 ? value : null;
  }
  int? get reviewCount {
    final raw = metadata?['reviewCount'];
    final value = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    return value != null && value.isFinite && value >= 0 && value == value.roundToDouble() ? value.toInt() : null;
  }

  factory BusinessModel.fromJson(Map<String, dynamic> json) {
    // دالة مساعدة لتحويل التقييم من String أو num
    double parseRating(dynamic ratingValue) {
      if (ratingValue == null) return 0.0;
      if (ratingValue is num) return ratingValue.toDouble();
      if (ratingValue is String) {
        return double.tryParse(ratingValue) ?? 0.0;
      }
      return 0.0;
    }

    final rating = parseRating(json['customerRating'] ?? json['rating']);
    
    // تحليل العنوان المحسن
    String addressString = 'العنوان غير متوفر';
    BusinessAddress? parsedAddress;
    
    try {
      if (json['address'] is Map<String, dynamic>) {
        // إذا كان العنوان object، نحتاج لتحويله لنص قابل للقراءة
        final addressMap = json['address'] as Map<String, dynamic>;
        parsedAddress = BusinessAddress.fromDynamoDBJson(addressMap);
        
        // بناء نص العنوان من components
        List<String> addressParts = [];
        if (addressMap['street'] != null && addressMap['street'].toString().isNotEmpty) {
          addressParts.add(addressMap['street'].toString());
        }
        if (addressMap['district'] != null && addressMap['district'].toString().isNotEmpty) {
          addressParts.add(addressMap['district'].toString());
        }
        if (addressMap['city'] != null && addressMap['city'].toString().isNotEmpty) {
          addressParts.add(addressMap['city'].toString());
        }
        if (addressMap['country'] != null && addressMap['country'].toString().isNotEmpty) {
          addressParts.add(addressMap['country'].toString());
        }
        
        if (addressParts.isNotEmpty) {
          addressString = addressParts.join('، ');
        }
        
        developer.log('🏠 تم تحويل object العنوان إلى نص: "$addressString"');
      } else if (json['address'] is String) {
        // إذا كان العنوان string جاهز
        addressString = json['address'] as String;
        if (addressString.isNotEmpty && addressString != 'العنوان غير متوفر') {
          parsedAddress = BusinessAddress.fromString(addressString);
        }
        developer.log('🏠 تم استخدام العنوان النصي: "$addressString"');
      }
    } catch (e) {
      developer.log('❌ خطأ في تحليل العنوان: $e');
      addressString = 'العنوان غير متوفر';
    }

    // دالة مساعدة لتحويل القيم Boolean من DynamoDB
    bool parseBool(dynamic value, {bool defaultValue = true}) {
      if (value == null) return defaultValue;
      if (value is bool) return value;
      if (value is String) {
        final lower = value.toLowerCase();
        if (lower == 'true' || lower == '1') return true;
        if (lower == 'false' || lower == '0') return false;
        return defaultValue;
      }
      if (value is num) return value != 0;
      return defaultValue;
    }

    return BusinessModel(
      id: json['business_id']?.toString() ?? json['businessId']?.toString() ?? '',
      businessName: json['business_name']?.toString() ?? 
                   json['businessName']?.toString() ?? 
                   json['name']?.toString() ?? 
                   json['store_name']?.toString() ?? 
                   json['storeName']?.toString() ?? 
                   'اسم المطعم غير متوفر',
      address: addressString,
      businessAddress: parsedAddress,
      businessPhotoUrl: json['businessPhotoUrl']?.toString() ?? json['business_photo_url']?.toString() ?? '',
      businessType: json['businessType']?.toString() ?? json['business_type']?.toString() ?? 'restaurant',
      isActive: parseBool(json['isActive'] ?? json['is_active'], defaultValue: true),
      rating: rating, // استخدام التقييم المحلل
      distance: json['distance']?.toString() ?? '', // مسافة افتراضية
      deliveryFee: json['deliveryFee']?.toString() ?? json['delivery_fee']?.toString() ?? '',
      deliveryTime: json['deliveryTime']?.toString() ?? json['delivery_time']?.toString() ?? '',
      phone: json['phoneNumber']?.toString() ?? json['phone_number']?.toString() ?? json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
      metadata: {
        'minimumOrderAmountIqd': json['minimumOrderAmountIqd'] ?? json['minimum_order'] ?? json['metadata']?['minimumOrderAmountIqd'],
        'storefrontDeliveryAgreements': json['storefrontDeliveryAgreements'] ?? json['metadata']?['storefrontDeliveryAgreements'] ?? [],
        'averagePreparationMinutes':json['averagePreparationMinutes'] ?? json['orderReceptionSettings']?['defaultPreparationMinutes'] ?? json['metadata']?['averagePreparationMinutes'],
        'orderReceptionSettings':json['orderReceptionSettings'],
        'reviewCount': json['customerRatingCount'] ?? json['reviewCount'] ?? json['reviewsCount'] ?? json['ratingCount'] ?? json['metadata']?['reviewCount'],
        'sponsored': parseBool(json['sponsored'], defaultValue: false),
        'popular': rating >= 4.0,
        'owner_name': json['ownerName']?.toString() ?? json['owner_name']?.toString() ?? '',
        'status': json['status']?.toString() ?? 'active',
        'created_at': json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
        'updated_at': json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
        'createdAt': json['createdAt'] is int ? json['createdAt'] : (json['created_at'] is int ? json['created_at'] : null),
        // معلومات حالة المطعم الجديدة
        // ✅ إضافة حالة الإغلاق الكامل لليوم (من الـ API مباشرة)
        'isClosed': parseBool(json['isClosed'] ?? json['is_closed'], defaultValue: false),
        // ⚠️ isOnline لا يعتمد على isClosed - المطاعم المغلقة يجب أن تظهر في القائمة
        'isOnline': parseBool(json['isOnline'] ?? json['is_online'], defaultValue: true),
        'acceptingOrders': parseBool(json['acceptingOrders'] ?? json['accepting_orders'], defaultValue: true),
        'isBusy': parseBool(json['isBusy'] ?? json['is_busy'], defaultValue: false),
        'businessMode': json['businessMode']?.toString() ?? 'auto',
        'currentOrdersCount': json['currentOrdersCount'] ?? 0,
        'maxOrdersCapacity': json['maxOrdersCapacity'] ?? 10,
        'statusMessage': json['statusMessage']?.toString() ?? '',
        'lastStatusUpdate': json['lastStatusUpdate']?.toString(),
        'businessStatus': json['businessStatus'] as Map<String, dynamic>?,
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_name': businessName,
      'address': address,
      'business_photo_url': businessPhotoUrl,
      'business_type': businessType,
      'is_active': isActive,
      'rating': rating,
      'reviewCount': reviewCount,
      'distance': distance,
      'delivery_fee': deliveryFee,
      'delivery_time': deliveryTime,
      'phone': phone,
      'email': email,
      'latitude': latitude,
      'longitude': longitude,
      'metadata': metadata,
    };
  }

  // Methods للحصول على القيم المتوافقة مع Store model
  String get name => businessName;
  String get image => businessPhotoUrl;
  String get logoUrl => businessPhotoUrl;
  bool get isOpen => isActive;
  String get fee => deliveryFee;
  String get ratingString => rating.toStringAsFixed(1);
  String get reviews => '0'; // يمكن إضافة هذا الحقل لاحقاً
  String get time => deliveryTime;
  String get category => businessType;

  double get ratingValue => rating;
  
  // دوال للعنوان المحسن
  String get formattedAddress {
    if (businessAddress?.isNotEmpty == true) {
      return businessAddress!.getFormattedAddress();
    }
    return address;
  }
  
  String get shortAddress {
    if (businessAddress?.isNotEmpty == true) {
      return businessAddress!.getShortAddress();
    }
    return address;
  }

  // حساب المسافة من نقطة معينة (بالكيلومتر)
  double? calculateDistanceFrom(double userLat, double userLng) {
    if (latitude == null || longitude == null) return null;
    
    return _calculateHaversineDistance(userLat, userLng, latitude!, longitude!);
  }

  // دالة Haversine لحساب المسافة بين نقطتين على الأرض
  static double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // نصف قطر الأرض بالكيلومتر
    
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);
    
    double a = 
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  // نسخة محدثة من المطعم مع مسافة محسوبة
  BusinessModel copyWithCalculatedDistance(double userLat, double userLng) {
    final calculatedDistance = calculateDistanceFrom(userLat, userLng);
    final distanceText = calculatedDistance != null 
        ? '${calculatedDistance.toStringAsFixed(1)} كم' 
        : distance;
    
    return BusinessModel(
      id: id,
      businessName: businessName,
      address: address,
      businessAddress: businessAddress,
      businessPhotoUrl: businessPhotoUrl,
      businessType: businessType,
      isActive: isActive,
      rating: rating,
      distance: distanceText,
      deliveryFee: deliveryFee,
      deliveryTime: deliveryTime,
      phone: phone,
      email: email,
      latitude: latitude,
      longitude: longitude,
      metadata: metadata,
    );
  }

  // دالة مساعدة آمنة لقراءة bool من metadata
  bool _parseBoolFromMetadata(String key, {bool defaultValue = false}) {
    final value = metadata?[key];
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    if (value is num) return value != 0;
    return defaultValue;
  }

  // خصائص للوصول لحالة المطعم من metadata
  bool get isBusy => _parseBoolFromMetadata('isBusy', defaultValue: false);
  bool get isOnline => _parseBoolFromMetadata('isOnline', defaultValue: true);
  bool get acceptingOrders => _parseBoolFromMetadata('acceptingOrders', defaultValue: true);
  String get status => metadata?['status']?.toString() ?? 'active';
  String get businessMode => metadata?['businessMode']?.toString() ?? 'auto';
  String get statusMessage => metadata?['statusMessage']?.toString() ?? '';
  int get currentOrdersCount => (metadata?['currentOrdersCount'] is int) ? metadata!['currentOrdersCount'] : 0;
  int get maxOrdersCapacity => (metadata?['maxOrdersCapacity'] is int) ? metadata!['maxOrdersCapacity'] : 10;

  // 🔥 دالة copyWith عامة لتحديث أي حقل
  BusinessModel copyWith({
    String? id,
    String? businessName,
    String? address,
    BusinessAddress? businessAddress,
    String? businessPhotoUrl,
    String? businessType,
    bool? isActive,
    double? rating,
    String? distance,
    String? deliveryFee,
    String? deliveryTime,
    String? phone,
    String? email,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? metadata,
    // حقول إضافية للحالة من polling
    bool? isAvailable,
    bool? acceptingOrders,
    bool? isWithinWorkingHours,
  }) {
    final updatedMetadata = Map<String, dynamic>.from(this.metadata ?? {});
    
    // تحديث الحقول الخاصة بالحالة في metadata
    if (isAvailable != null) updatedMetadata['isAvailable'] = isAvailable;
    if (acceptingOrders != null) updatedMetadata['acceptingOrders'] = acceptingOrders;
    if (isWithinWorkingHours != null) updatedMetadata['isWithinWorkingHours'] = isWithinWorkingHours;
    
    // دمج metadata الجديدة إذا تم تمريرها
    if (metadata != null) {
      updatedMetadata.addAll(metadata);
    }
    
    // إضافة timestamp للتحديث
    updatedMetadata['lastStatusUpdate'] = DateTime.now().toIso8601String();

    return BusinessModel(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      address: address ?? this.address,
      businessAddress: businessAddress ?? this.businessAddress,
      businessPhotoUrl: businessPhotoUrl ?? this.businessPhotoUrl,
      businessType: businessType ?? this.businessType,
      isActive: isActive ?? this.isActive,
      rating: rating ?? this.rating,
      distance: distance ?? this.distance,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      metadata: updatedMetadata,
    );
  }

  // دالة لإنشاء نسخة محدثة مع تغيير حالة المطعم
  BusinessModel copyWithBusinessStatus({
    bool? isBusy,
    bool? isOnline,
    bool? acceptingOrders,
    String? status,
    String? businessMode,
    String? statusMessage,
    int? currentOrdersCount,
    int? maxOrdersCapacity,
  }) {
    final updatedMetadata = Map<String, dynamic>.from(metadata ?? {});
    
    if (isBusy != null) updatedMetadata['isBusy'] = isBusy;
    if (isOnline != null) updatedMetadata['isOnline'] = isOnline;
    if (acceptingOrders != null) updatedMetadata['acceptingOrders'] = acceptingOrders;
    if (status != null) updatedMetadata['status'] = status;
    if (businessMode != null) updatedMetadata['businessMode'] = businessMode;
    if (statusMessage != null) updatedMetadata['statusMessage'] = statusMessage;
    if (currentOrdersCount != null) updatedMetadata['currentOrdersCount'] = currentOrdersCount;
    if (maxOrdersCapacity != null) updatedMetadata['maxOrdersCapacity'] = maxOrdersCapacity;
    
    // إضافة timestamp للتحديث
    updatedMetadata['lastStatusUpdate'] = DateTime.now().toIso8601String();

    return BusinessModel(
      id: id,
      businessName: businessName,
      address: address,
      businessAddress: businessAddress,
      businessPhotoUrl: businessPhotoUrl,
      businessType: businessType,
      isActive: isActive,
      rating: rating,
      distance: distance,
      deliveryFee: deliveryFee,
      deliveryTime: deliveryTime,
      phone: phone,
      email: email,
      latitude: latitude,
      longitude: longitude,
      metadata: updatedMetadata,
    );
  }

  // دالة لتحديث الحالة بناءً على WebSocket update
  BusinessModel copyWithWebSocketUpdate(Map<String, dynamic> updateData) {
    return copyWithBusinessStatus(
      isBusy: updateData['isBusy'] as bool?,
      status: updateData['status'] as String?,
      statusMessage: updateData['statusMessage'] as String?,
      acceptingOrders: updateData['canAcceptOrders'] as bool?,
    );
  }
}
