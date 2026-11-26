import 'address_model.dart';
/// Enum representing the source of a delivery address
/// مصدر عنوان التوصيل
enum AddressSource {
  /// Address obtained from GPS location (guest users)
  /// عنوان من الموقع الحالي GPS
  gps,

  /// Address loaded from cache (guest users - subsequent launches)
  /// عنوان محفوظ مؤقتاً في الذاكرة المؤقتة
  cache,

  /// Address from user's saved addresses (registered users)
  /// عنوان من العناوين المحفوظة للمستخدم المسجل
  saved,

  /// Address entered manually by user
  /// عنوان تم إدخاله يدوياً
  manual,
}

/// Model representing a delivery address
/// نموذج عنوان التوصيل - المفهوم الأساسي للنظام
class DeliveryAddress {
  /// Unique identifier (only for saved addresses)
  /// معرّف فريد (للعناوين المحفوظة فقط)
  final String? addressId;

  /// User ID (only for registered users)
  /// معرّف المستخدم (للمستخدمين المسجلين فقط)
  final String? userId;

  /// Address label (e.g., "المنزل", "المكتب")
  /// تسمية العنوان
  final String? label;

  /// Formatted address string
  /// العنوان المنسق كنص
  final String formattedAddress;

  /// Latitude
  /// دائرة العرض
  final double latitude;

  /// Longitude
  /// خط الطول
  final double longitude;

  /// Region ID from WizzCentral_Regions
  /// معرّف المنطقة
  final String? regionId;

  /// Region name in Arabic
  /// اسم المنطقة بالعربية
  final String? regionNameAr;

  /// Region name in English
  /// اسم المنطقة بالإنجليزية
  final String? regionNameEn;

  /// Neighborhood/sub-region
  /// الحي
  final String? neighborhood;

  /// City name
  /// اسم المدينة
  final String city;

  /// Address source
  /// مصدر العنوان
  final AddressSource source;

  /// Is this the default address? (for registered users)
  /// هل هذا العنوان الافتراضي؟
  final bool isDefault;

  /// Timestamp when address was created/cached
  /// وقت إنشاء أو حفظ العنوان
  final DateTime timestamp;

  /// Expiry timestamp (for cached guest addresses)
  /// وقت انتهاء الصلاحية (للعناوين المؤقتة)
  final DateTime? expiryTimestamp;

  DeliveryAddress({
    this.addressId,
    this.userId,
    this.label,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.regionId,
    this.regionNameAr,
    this.regionNameEn,
    this.neighborhood,
    required this.city,
    required this.source,
    this.isDefault = false,
    DateTime? timestamp,
    this.expiryTimestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Check if this address is expired (for cached guest addresses)
  /// التحقق من انتهاء صلاحية العنوان
  bool get isExpired {
    if (expiryTimestamp == null) return false;
    return DateTime.now().isAfter(expiryTimestamp!);
  }

  /// Check if this is a guest address
  /// التحقق من كون العنوان لمستخدم ضيف
  bool get isGuestAddress {
    return source == AddressSource.gps || source == AddressSource.cache;
  }

  /// Check if this is a registered user address
  /// التحقق من كون العنوان لمستخدم مسجل
  bool get isRegisteredAddress {
    return source == AddressSource.saved && userId != null;
  }

  /// Get display name for the address
  /// الحصول على الاسم المعروض للعنوان
  String get displayName {
    if (label != null && label!.isNotEmpty) {
      return label!;
    }
    if (source == AddressSource.gps) {
      return '📍 الموقع الحالي';
    }
    if (neighborhood != null && neighborhood!.isNotEmpty) {
      return neighborhood!;
    }
    return city;
  }

  /// Get full display address
  /// الحصول على العنوان الكامل المعروض
  String get fullDisplayAddress {
    final parts = <String>[];
    if (label != null && label!.isNotEmpty) {
      parts.add(label!);
    }
    if (neighborhood != null && neighborhood!.isNotEmpty) {
      parts.add(neighborhood!);
    }
    parts.add(city);
    return parts.join(' • ');
  }

  /// Convert to JSON
  /// تحويل إلى JSON
  Map<String, dynamic> toJson() {
    return {
      'addressId': addressId,
      'userId': userId,
      'label': label,
      'formattedAddress': formattedAddress,
      'latitude': latitude,
      'longitude': longitude,
      'regionId': regionId,
      'regionNameAr': regionNameAr,
      'regionNameEn': regionNameEn,
      'neighborhood': neighborhood,
      'city': city,
      'source': source.name,
      'isDefault': isDefault,
      'timestamp': timestamp.toIso8601String(),
      'expiryTimestamp': expiryTimestamp?.toIso8601String(),
    };
  }

  factory DeliveryAddress.fromSavedAddress(DetailedAddress address) {
    final lat=address.latitude,lng=address.longitude;
    if(address.id.isEmpty||lat==null||lng==null||!lat.isFinite||!lng.isFinite||lat.abs()>90||lng.abs()>180)throw const FormatException('Invalid saved delivery address');
    return DeliveryAddress(addressId:address.id,userId:address.userId,label:address.name,formattedAddress:address.fullAddress,
      latitude:lat,longitude:lng,regionId:address.regionId,regionNameAr:address.regionNameAr,neighborhood:address.neighborhood,
      city:address.province,source:AddressSource.saved,isDefault:address.isDefault,timestamp:address.updatedAt);
  }

  /// Create from JSON
  /// إنشاء من JSON
  factory DeliveryAddress.fromJson(Map<String, dynamic> json) {
    return DeliveryAddress(
      addressId: json['addressId'] as String?,
      userId: json['userId'] as String?,
      label: json['label'] as String?,
      formattedAddress: json['formattedAddress'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      regionId: json['regionId'] as String?,
      regionNameAr: json['regionNameAr'] as String?,
      regionNameEn: json['regionNameEn'] as String?,
      neighborhood: json['neighborhood'] as String?,
      city: json['city'] as String,
      source: AddressSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => AddressSource.manual,
      ),
      isDefault: json['isDefault'] as bool? ?? false,
      timestamp: DateTime.parse(json['timestamp'] as String),
      expiryTimestamp: json['expiryTimestamp'] != null
          ? DateTime.parse(json['expiryTimestamp'] as String)
          : null,
    );
  }

  /// Create a copy with modified fields
  /// إنشاء نسخة مع تعديل بعض الحقول
  DeliveryAddress copyWith({
    String? addressId,
    String? userId,
    String? label,
    String? formattedAddress,
    double? latitude,
    double? longitude,
    String? regionId,
    String? regionNameAr,
    String? regionNameEn,
    String? neighborhood,
    String? city,
    AddressSource? source,
    bool? isDefault,
    DateTime? timestamp,
    DateTime? expiryTimestamp,
  }) {
    return DeliveryAddress(
      addressId: addressId ?? this.addressId,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      regionId: regionId ?? this.regionId,
      regionNameAr: regionNameAr ?? this.regionNameAr,
      regionNameEn: regionNameEn ?? this.regionNameEn,
      neighborhood: neighborhood ?? this.neighborhood,
      city: city ?? this.city,
      source: source ?? this.source,
      isDefault: isDefault ?? this.isDefault,
      timestamp: timestamp ?? this.timestamp,
      expiryTimestamp: expiryTimestamp ?? this.expiryTimestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DeliveryAddress &&
        other.addressId == addressId &&
        other.userId == userId &&
        other.label == label &&
        other.formattedAddress == formattedAddress &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.regionId == regionId &&
        other.regionNameAr == regionNameAr &&
        other.regionNameEn == regionNameEn &&
        other.neighborhood == neighborhood &&
        other.city == city &&
        other.source == source &&
        other.isDefault == isDefault;
  }

  @override
  int get hashCode {
    return Object.hash(
      addressId,
      userId,
      label,
      formattedAddress,
      latitude,
      longitude,
      regionId,
      regionNameAr,
      regionNameEn,
      neighborhood,
      city,
      source,
      isDefault,
    );
  }

  @override
  String toString() {
    return 'DeliveryAddress('
        'addressId: $addressId, '
        'label: $label, '
        'city: $city, '
        'regionId: $regionId, '
        'source: ${source.name}, '
        'isDefault: $isDefault'
        ')';
  }
}
