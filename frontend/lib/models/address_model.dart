// lib/models/address_model.dart

// Simple address model for local use and compatibility
class AddressModel {
  final String id;
  final String name;
  final String fullAddress;
  final double latitude;
  final double longitude;
  final bool isDefault;
  final bool isCurrent;
  final String type; // 'home', 'work', 'other', 'current'

  AddressModel({
    required this.id,
    required this.name,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
    this.isDefault = false,
    this.isCurrent = false,
    this.type = 'other',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fullAddress': fullAddress,
      'latitude': latitude,
      'longitude': longitude,
      'isDefault': isDefault,
      'isCurrent': isCurrent,
      'type': type,
    };
  }

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      fullAddress: json['fullAddress'] ?? '',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      isDefault: json['isDefault'] ?? false,
      isCurrent: json['isCurrent'] ?? false,
      type: json['type'] ?? 'other',
    );
  }

  AddressModel copyWith({
    String? id,
    String? name,
    String? fullAddress,
    double? latitude,
    double? longitude,
    bool? isDefault,
    bool? isCurrent,
    String? type,
  }) {
    return AddressModel(
      id: id ?? this.id,
      name: name ?? this.name,
      fullAddress: fullAddress ?? this.fullAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDefault: isDefault ?? this.isDefault,
      isCurrent: isCurrent ?? this.isCurrent,
      type: type ?? this.type,
    );
  }
}

class AddressType {
  static const String home = 'home';
  static const String work = 'work';
  static const String other = 'other';
  static const String current = 'current';

  static const List<String> values = [home, work, other, current];

  static String getDisplayName(String type) {
    switch (type) {
      case home:
        return 'المنزل';
      case work:
        return 'العمل';
      case other:
        return 'أخرى';
      case current:
        return 'الموقع الحالي';
      default:
        return 'غير محدد';
    }
  }

  static String getIcon(String type) {
    switch (type) {
      case home:
        return '🏠';
      case work:
        return '🏢';
      case current:
        return '📍';
      case other:
      default:
        return '📌';
    }
  }
}

class DetailedAddress {
  final String id;
  final String userId;
  final String name;
  final String province;
  final String district;
  final String neighborhood;
  final String landmark;
  final String? detailedAddress;
  final String fullAddress;
  final double? latitude;
  final double? longitude;
  final String addressType;
  final bool isDefault;
  final String? buildingNumber;
  final String? floorNumber;
  final String? apartmentNumber;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Region System Fields (new)
  final String? regionId;
  final String? regionName;
  final String? regionNameAr;
  final int? regionLevel;
  final bool? regionIsActive;
  final double? deliveryFee;
  final double? minimumOrder;
  final double? maxDistanceKm;
  final double? pricePerKm;

  DetailedAddress({
    required this.id,
    required this.userId,
    required this.name,
    required this.province,
    required this.district,
    required this.neighborhood,
    required this.landmark,
    this.detailedAddress,
    required this.fullAddress,
    this.latitude,
    this.longitude,
    required this.addressType,
    this.isDefault = false,
    this.buildingNumber,
    this.floorNumber,
    this.apartmentNumber,
    this.phoneNumber,
    // Region fields
    this.regionId,
    this.regionName,
    this.regionNameAr,
    this.regionLevel,
    this.regionIsActive,
    this.deliveryFee,
    this.minimumOrder,
    this.maxDistanceKm,
    this.pricePerKm,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DetailedAddress.fromJson(Map<String, dynamic> json) {
    // دالة مساعدة لتحويل قيم Boolean من مصادر مختلفة
    bool parseBoolean(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is String) {
        final lowerValue = value.toLowerCase().trim();
        return lowerValue == 'true' || lowerValue == '1' || lowerValue == 'yes';
      }
      if (value is int) return value == 1;
      if (value is num) return value != 0;
      return false;
    }
    
    // Handle empty or null json gracefully
    if (json.isEmpty) {
      final now = DateTime.now();
      return DetailedAddress(
        id: '',
        userId: '',
        name: 'عنوان غير محدد',
        province: 'غير محدد',
        district: 'غير محدد',
        neighborhood: 'غير محدد',
        landmark: 'غير محدد',
        fullAddress: 'عنوان غير محدد',
        addressType: AddressType.other,
        createdAt: now,
        updatedAt: now,
      );
    }
    
    return DetailedAddress(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'عنوان غير محدد',
      province: json['province'] ?? json['state'] as String? ?? 'غير محدد',
      district: json['district'] ?? json['city'] as String? ?? 'غير محدد',
      neighborhood: json['neighborhood'] ?? json['area'] as String? ?? 'غير محدد',
      landmark: json['landmark'] as String? ?? 'غير محدد',
      detailedAddress: json['detailed_address'] ?? json['street'] ?? json['addressLine1'] as String?,
      fullAddress: _buildFullAddress(json),
      latitude: (json['latitude'] ?? json['lat'])?.toDouble(),
      longitude: (json['longitude'] ?? json['lng'])?.toDouble(),
      addressType: json['address_type'] as String? ?? AddressType.other,
      isDefault: parseBoolean(json['is_default']),
      buildingNumber: json['building_number'] as String?,
      floorNumber: json['floor_number'] as String?,
      apartmentNumber: json['apartment_number'] as String?,
      phoneNumber: json['phone_number'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      // Region fields
      regionId: json['region_id'] as String?,
      regionName: json['region_name'] as String?,
      regionNameAr: json['region_name_ar'] as String?,
      regionLevel: json['region_level'] as int?,
      regionIsActive: json['region_is_active'] != null 
          ? parseBoolean(json['region_is_active']) 
          : null,
      deliveryFee: (json['delivery_fee'])?.toDouble(),
      minimumOrder: (json['minimum_order'])?.toDouble(),
      maxDistanceKm: (json['max_distance_km'])?.toDouble(),
      pricePerKm: (json['price_per_km'])?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'province': province,
      'district': district,
      'neighborhood': neighborhood,
      'landmark': landmark,
      'detailed_address': detailedAddress,
      'full_address': fullAddress,
      'latitude': latitude,
      'longitude': longitude,
      'address_type': addressType,
      'is_default': isDefault,
      'building_number': buildingNumber,
      'floor_number': floorNumber,
      'apartment_number': apartmentNumber,
      'phone_number': phoneNumber,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      // Region fields
      'region_id': regionId,
      'region_name': regionName,
      'region_name_ar': regionNameAr,
      'region_level': regionLevel,
      'region_is_active': regionIsActive,
      'delivery_fee': deliveryFee,
      'minimum_order': minimumOrder,
      'max_distance_km': maxDistanceKm,
      'price_per_km': pricePerKm,
    };
  }

  DetailedAddress copyWith({
    String? id,
    String? userId,
    String? name,
    String? province,
    String? district,
    String? neighborhood,
    String? landmark,
    String? detailedAddress,
    String? fullAddress,
    double? latitude,
    double? longitude,
    String? addressType,
    bool? isDefault,
    String? buildingNumber,
    String? floorNumber,
    String? apartmentNumber,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    // Region fields
    String? regionId,
    String? regionName,
    String? regionNameAr,
    int? regionLevel,
    bool? regionIsActive,
    double? deliveryFee,
    double? minimumOrder,
    double? maxDistanceKm,
    double? pricePerKm,
  }) {
    return DetailedAddress(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      province: province ?? this.province,
      district: district ?? this.district,
      neighborhood: neighborhood ?? this.neighborhood,
      landmark: landmark ?? this.landmark,
      detailedAddress: detailedAddress ?? this.detailedAddress,
      fullAddress: fullAddress ?? this.fullAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      addressType: addressType ?? this.addressType,
      isDefault: isDefault ?? this.isDefault,
      buildingNumber: buildingNumber ?? this.buildingNumber,
      floorNumber: floorNumber ?? this.floorNumber,
      apartmentNumber: apartmentNumber ?? this.apartmentNumber,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      // Region fields
      regionId: regionId ?? this.regionId,
      regionName: regionName ?? this.regionName,
      regionNameAr: regionNameAr ?? this.regionNameAr,
      regionLevel: regionLevel ?? this.regionLevel,
      regionIsActive: regionIsActive ?? this.regionIsActive,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      minimumOrder: minimumOrder ?? this.minimumOrder,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      pricePerKm: pricePerKm ?? this.pricePerKm,
    );
  }

  String get typeDisplayName => AddressType.getDisplayName(addressType);
  String get typeIcon => AddressType.getIcon(addressType);
  
  String get shortAddress {
    List<String> parts = [];
    if (neighborhood.isNotEmpty) parts.add(neighborhood);
    if (district.isNotEmpty) parts.add(district);
    if (province.isNotEmpty) parts.add(province);
    return parts.take(2).join('، ');
  }

  bool get hasCoordinates => latitude != null && longitude != null;
  
  // Helper method to build full address safely with enhanced mapping
  static String _buildFullAddress(Map<String, dynamic> json) {
    print('🏠 DetailedAddress._buildFullAddress: Input JSON keys: ${json.keys.toList()}');
    print('🏠 DetailedAddress._buildFullAddress: Full JSON: $json');
    
    // Priority 1: Check if full_address or fullAddress is provided directly
    if (json['full_address'] != null && json['full_address'].toString().isNotEmpty) {
      final address = json['full_address'].toString().trim();
      if (address != 'عنوان غير محدد' && address.isNotEmpty) {
        print('🏠 DetailedAddress._buildFullAddress: Using full_address: $address');
        return address;
      }
    }
    if (json['fullAddress'] != null && json['fullAddress'].toString().isNotEmpty) {
      final address = json['fullAddress'].toString().trim();
      if (address != 'عنوان غير محدد' && address.isNotEmpty) {
        print('🏠 DetailedAddress._buildFullAddress: Using fullAddress: $address');
        return address;
      }
    }
    
    // Priority 2: Build from frontend format (used in checkout)
    List<String> frontendParts = [];
    
    if (json['province'] != null && json['province'].toString().trim().isNotEmpty && json['province'].toString() != 'غير محدد') {
      frontendParts.add(json['province'].toString().trim());
    }
    if (json['district'] != null && json['district'].toString().trim().isNotEmpty && json['district'].toString() != 'غير محدد') {
      frontendParts.add(json['district'].toString().trim());
    }
    if (json['neighborhood'] != null && json['neighborhood'].toString().trim().isNotEmpty && json['neighborhood'].toString() != 'غير محدد') {
      frontendParts.add(json['neighborhood'].toString().trim());
    }
    if (json['landmark'] != null && json['landmark'].toString().trim().isNotEmpty && json['landmark'].toString() != 'غير محدد') {
      frontendParts.add('قرب ' + json['landmark'].toString().trim());
    }
    
    // If we have parts from frontend format, join them
    if (frontendParts.isNotEmpty) {
      final frontendAddress = frontendParts.join('، ').trim();
      print('🏠 DetailedAddress._buildFullAddress: Using frontend format: $frontendAddress');
      return frontendAddress;
    }
    
    // Priority 3: Build from backend order format (used by create-order function)
    List<String> backendParts = [];
    
    if (json['addressLine1'] != null && json['addressLine1'].toString().trim().isNotEmpty) {
      backendParts.add(json['addressLine1'].toString().trim());
    }
    if (json['addressLine2'] != null && json['addressLine2'].toString().trim().isNotEmpty) {
      backendParts.add(json['addressLine2'].toString().trim());
    }
    if (json['area'] != null && json['area'].toString().trim().isNotEmpty) {
      backendParts.add(json['area'].toString().trim());
    }
    if (json['city'] != null && json['city'].toString().trim().isNotEmpty) {
      backendParts.add(json['city'].toString().trim());
    }
    
    // If we have parts from backend format, join them
    if (backendParts.isNotEmpty) {
      final backendAddress = backendParts.join('، ').trim();
      print('🏠 DetailedAddress._buildFullAddress: Using backend format: $backendAddress');
      return backendAddress;
    }
    
    // Priority 4: Build from component parts (legacy format)
    List<String> legacyParts = [];
    
    if (json['street'] != null && json['street'].toString().trim().isNotEmpty) {
      legacyParts.add(json['street'].toString().trim());
    }
    if (json['city'] != null && json['city'].toString().trim().isNotEmpty) {
      legacyParts.add(json['city'].toString().trim());
    }
    if (json['state'] != null && json['state'].toString().trim().isNotEmpty) {
      legacyParts.add(json['state'].toString().trim());
    }
    
    // If we have parts from legacy format, join them
    if (legacyParts.isNotEmpty) {
      final legacyAddress = legacyParts.join('، ').trim();
      print('🏠 DetailedAddress._buildFullAddress: Using legacy format: $legacyAddress');
      return legacyAddress;
    }
    
    // Priority 5: Build from detailed address components
    List<String> detailedParts = [];
    
    if (json['detailed_address'] != null && json['detailed_address'].toString().trim().isNotEmpty) {
      detailedParts.add(json['detailed_address'].toString().trim());
    }
    
    if (detailedParts.isNotEmpty) {
      final detailedAddress = detailedParts.join('، ').trim();
      print('🏠 DetailedAddress._buildFullAddress: Using detailed format: $detailedAddress');
      return detailedAddress;
    }
    
    // Final fallback - try to construct from name
    String fallbackAddress = '';
    if (json['name'] != null && json['name'].toString().trim().isNotEmpty && json['name'].toString() != 'عنوان غير محدد') {
      fallbackAddress = json['name'].toString().trim();
      print('🏠 DetailedAddress._buildFullAddress: Using name fallback: $fallbackAddress');
      return fallbackAddress;
    }
    
    print('🏠 DetailedAddress._buildFullAddress: No valid address found, using default');
    return 'عنوان غير محدد';
  }
}

class AddressCreateRequest {
  final String name;
  final String province;
  final String district;
  final String neighborhood;
  final String landmark;
  final String? detailedAddress;
  final double? latitude;
  final double? longitude;
  final String addressType;
  final bool isDefault;
  final String? buildingNumber;
  final String? floorNumber;
  final String? apartmentNumber;
  final String? phoneNumber;
  
  // 🔥 Region System Fields
  final String? idempotencyKey;
  final bool saveToAddressBook;
  final String? regionId;
  final String? regionName;
  final String? regionNameAr;
  final int? regionLevel;
  final bool? regionIsActive;
  final double? deliveryFee;
  final double? minimumOrder;
  final double? maxDistanceKm;
  final double? pricePerKm;

  AddressCreateRequest({
    required this.name,
    required this.province,
    required this.district,
    required this.neighborhood,
    required this.landmark,
    this.detailedAddress,
    this.latitude,
    this.longitude,
    this.addressType = AddressType.other,
    this.isDefault = false,
    this.buildingNumber,
    this.floorNumber,
    this.apartmentNumber,
    this.phoneNumber,
    // 🔥 Region System
    this.idempotencyKey,
    this.saveToAddressBook=true,
    this.regionId,
    this.regionName,
    this.regionNameAr,
    this.regionLevel,
    this.regionIsActive,
    this.deliveryFee,
    this.minimumOrder,
    this.maxDistanceKm,
    this.pricePerKm,
  });

  Map<String, dynamic> toJson() {
    return {
      if(idempotencyKey!=null)'idempotency_key':idempotencyKey,
      'save_to_address_book':saveToAddressBook,
      'name': name,
      'province': province,
      'district': district,
      'neighborhood': neighborhood,
      'landmark': landmark,
      'detailed_address': detailedAddress,
      'latitude': latitude,
      'longitude': longitude,
      'address_type': addressType,
      'is_default': isDefault,
      'building_number': buildingNumber,
      'floor_number': floorNumber,
      'apartment_number': apartmentNumber,
      'phone_number': phoneNumber,
      // 🔥 Region System Fields
      'region_id': regionId,
      'region_name': regionName,
      'region_name_ar': regionNameAr,
      'region_level': regionLevel,
      'region_is_active': regionIsActive,
      'delivery_fee': deliveryFee,
      'minimum_order': minimumOrder,
      'max_distance_km': maxDistanceKm,
      'price_per_km': pricePerKm,
    };
  }
}

class AddressUpdateRequest {
  final String? name;
  final String? province;
  final String? district;
  final String? neighborhood;
  final String? landmark;
  final String? detailedAddress;
  final double? latitude;
  final double? longitude;
  final String? addressType;
  final bool? isDefault;
  final String? buildingNumber;
  final String? floorNumber;
  final String? apartmentNumber;
  final String? phoneNumber;
  
  // 🔥 Region System Fields
  final String? regionId;
  final String? regionName;
  final String? regionNameAr;
  final int? regionLevel;
  final bool? regionIsActive;
  final double? deliveryFee;
  final double? minimumOrder;
  final double? maxDistanceKm;
  final double? pricePerKm;

  AddressUpdateRequest({
    this.name,
    this.province,
    this.district,
    this.neighborhood,
    this.landmark,
    this.detailedAddress,
    this.latitude,
    this.longitude,
    this.addressType,
    this.isDefault,
    this.buildingNumber,
    this.floorNumber,
    this.apartmentNumber,
    this.phoneNumber,
    // 🔥 Region System
    this.regionId,
    this.regionName,
    this.regionNameAr,
    this.regionLevel,
    this.regionIsActive,
    this.deliveryFee,
    this.minimumOrder,
    this.maxDistanceKm,
    this.pricePerKm,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    
    if (name != null) data['name'] = name;
    if (province != null) data['province'] = province;
    if (district != null) data['district'] = district;
    if (neighborhood != null) data['neighborhood'] = neighborhood;
    if (landmark != null) data['landmark'] = landmark;
    if (detailedAddress != null) data['detailed_address'] = detailedAddress;
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (addressType != null) data['address_type'] = addressType;
    if (isDefault != null) data['is_default'] = isDefault;
    if (buildingNumber != null) data['building_number'] = buildingNumber;
    if (floorNumber != null) data['floor_number'] = floorNumber;
    if (apartmentNumber != null) data['apartment_number'] = apartmentNumber;
    if (phoneNumber != null) data['phone_number'] = phoneNumber;
    
    // 🔥 Region System Fields
    if (regionId != null) data['region_id'] = regionId;
    if (regionName != null) data['region_name'] = regionName;
    if (regionNameAr != null) data['region_name_ar'] = regionNameAr;
    if (regionLevel != null) data['region_level'] = regionLevel;
    if (regionIsActive != null) data['region_is_active'] = regionIsActive;
    if (deliveryFee != null) data['delivery_fee'] = deliveryFee;
    if (minimumOrder != null) data['minimum_order'] = minimumOrder;
    if (maxDistanceKm != null) data['max_distance_km'] = maxDistanceKm;
    if (pricePerKm != null) data['price_per_km'] = pricePerKm;
    
    return data;
  }
}
