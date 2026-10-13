import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/google_places_config.dart';

/// Region Resolver Service
/// يتواصل مع WizzCentral API لتحويل GPS إلى معلومات المنطقة
class RegionResolutionException implements Exception {
  @override
  String toString() => 'تعذر التحقق من تغطية العنوان الآن. حاول مرة أخرى.';
}

class RegionResolverService {
  final http.Client? _client;
  RegionResolverService({http.Client? client}) : _client = client;
  /// Resolve GPS coordinates to region information
  /// 
  /// Returns region data including:
  /// - regionId, name, name_ar
  /// - pricing (base_fee, minimum_order, per_km)
  /// - limits (max_delivery_distance_km)
  /// - isActive status
  Future<RegionResolveResult?> resolvePoint({
    required double lat,
    required double lng,
    bool throwOnFailure = false,
  }) async {
    try {
      print('🗺️ Resolving region for: lat=$lat, lng=$lng');

      final baseUrl = GooglePlacesConfig.regionResolverUrl;
      if (baseUrl.isEmpty) {
        throw StateError('Missing REGION_RESOLVER_URL and API_URL fallback produced an empty URL');
      }

      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          'latitude': lat.toString(),
          'longitude': lng.toString(),
        },
      );

      print('🌐 Region resolver URL: $uri');

      final response = await (_client?.get ?? http.get)(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      
      print('📡 Response status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        if (throwOnFailure) {
          final body = jsonDecode(response.body);
          if (response.statusCode != 404 || body is! Map || body['error'] != 'REGION_NOT_FOUND') { throw RegionResolutionException(); }
        }
        return null;
      }

      final payload = jsonDecode(response.body);

      // Backend shape (WizzUser): { success: true, data: { region_id, region_name_ar, ... }, timestamp }
      final data = payload is Map<String, dynamic> ? payload['data'] : null;
      if (payload is Map<String, dynamic> && payload['success'] == true && data is Map<String, dynamic>) {
        final regionId = data['region_id']?.toString() ?? '';
        if (regionId.isEmpty) {
          print('❌ Resolution failed: missing region_id in response');
          return null;
        }

        final regionNameAr = (data['region_name_ar'] ?? regionId).toString();
        final regionNameEn = (data['region_name_en'] ?? regionId).toString();

        return RegionResolveResult(
          success: true,
          region: RegionInfo(
            id: regionId,
            name: regionNameEn,
            nameAr: regionNameAr,
            level: 0,
          ),
          // This endpoint only indicates whether a region exists.
          // To keep existing UX intact, treat "region found" as active + delivery available.
          effective: EffectiveState(
            isActive: true,
            service: ServiceInfo(
              delivery: DeliveryServiceInfo(available: true),
            ),
          ),
          resolvedAt: DateTime.tryParse(payload['timestamp']?.toString() ?? '') ?? DateTime.now(),
        );
      }

      // Legacy shape (WizzCentral): { success: true, region: {...}, effective: {...}, resolvedAt }
      if (payload is Map<String, dynamic> && payload['success'] == true) {
        return RegionResolveResult.fromJson(payload);
      }

      if (throwOnFailure) { throw RegionResolutionException(); }
      return null;
    } catch (e) {
      if (throwOnFailure) { throw RegionResolutionException(); }
      return null;
    }
  }
}

/// Region Resolve Result Model
class RegionResolveResult {
  final bool success;
  final RegionInfo region;
  final EffectiveState effective;
  final DateTime resolvedAt;
  
  RegionResolveResult({
    required this.success,
    required this.region,
    required this.effective,
    required this.resolvedAt,
  });
  
  factory RegionResolveResult.fromJson(Map<String, dynamic> json) {
    return RegionResolveResult(
      success: json['success'] ?? false,
      region: RegionInfo.fromJson(json['region'] ?? {}),
      effective: EffectiveState.fromJson(json['effective'] ?? {}),
      resolvedAt: DateTime.parse(json['resolvedAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Region Information
class RegionInfo {
  final String id;
  final String name;
  final String nameAr;
  final int level;
  final String? parentId;
  
  RegionInfo({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.level,
    this.parentId,
  });
  
  factory RegionInfo.fromJson(Map<String, dynamic> json) {
    return RegionInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      nameAr: json['name_ar'] ?? json['name'] ?? '',
      level: json['level'] ?? 0,
      parentId: json['parent_id'],
    );
  }
}

/// Effective State (pricing, limits, service config)
class EffectiveState {
  final bool isActive;
  final PricingInfo? pricing;
  final LimitsInfo? limits;
  final ServiceInfo? service;
  
  EffectiveState({
    required this.isActive,
    this.pricing,
    this.limits,
    this.service,
  });
  
  factory EffectiveState.fromJson(Map<String, dynamic> json) {
    // Handle both integer and boolean for isActive
    bool active = false;
    if (json['isActive'] is bool) {
      active = json['isActive'];
    } else if (json['isActive'] is int) {
      active = json['isActive'] == 1;
    }
    
    return EffectiveState(
      isActive: active,
      pricing: json['pricing'] != null 
          ? PricingInfo.fromJson(json['pricing']) 
          : null,
      limits: json['limits'] != null 
          ? LimitsInfo.fromJson(json['limits']) 
          : null,
      service: json['service'] != null 
          ? ServiceInfo.fromJson(json['service']) 
          : null,
    );
  }
  
  /// Check if delivery service is available
  bool get hasDelivery => service?.delivery?.available ?? false;
  
  /// Check if region is active AND has delivery service
  bool get isDeliveryAvailable => isActive && hasDelivery;
}

/// Pricing Information
class PricingInfo {
  final double baseFee;
  final double minimumOrder;
  final double perKm;
  
  PricingInfo({
    required this.baseFee,
    required this.minimumOrder,
    required this.perKm,
  });
  
  factory PricingInfo.fromJson(Map<String, dynamic> json) {
    return PricingInfo(
      baseFee: (json['base_fee'] ?? 0).toDouble(),
      minimumOrder: (json['minimum_order'] ?? 0).toDouble(),
      perKm: (json['per_km'] ?? 0).toDouble(),
    );
  }
}

/// Limits Information
class LimitsInfo {
  final int maxDeliveryDistanceKm;
  
  LimitsInfo({
    required this.maxDeliveryDistanceKm,
  });
  
  factory LimitsInfo.fromJson(Map<String, dynamic> json) {
    return LimitsInfo(
      maxDeliveryDistanceKm: json['max_delivery_distance_km'] ?? 10,
    );
  }
}

/// Service Information
class ServiceInfo {
  final DeliveryServiceInfo? delivery;
  final bool? pickup;
  final bool? dineIn;
  
  ServiceInfo({
    this.delivery,
    this.pickup,
    this.dineIn,
  });
  
  factory ServiceInfo.fromJson(Map<String, dynamic> json) {
    return ServiceInfo(
      delivery: json.containsKey('delivery') 
          ? DeliveryServiceInfo.fromJson(json['delivery']) 
          : null,
      pickup: _parseBool(json['pickup']),
      dineIn: _parseBool(json['dineIn']),
    );
  }
  
  // Helper function to safely parse boolean values
  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is Map) return null; // إذا كان Map، نعتبره null
    return null;
  }
}

/// Delivery Service Information
class DeliveryServiceInfo {
  final bool available;  // هل الخدمة متوفرة؟
  final int? estimatedTimeMinutes;
  final double? baseFee;
  final double? minimumOrder;
  
  DeliveryServiceInfo({
    required this.available,
    this.estimatedTimeMinutes,
    this.baseFee,
    this.minimumOrder,
  });
  
  factory DeliveryServiceInfo.fromJson(dynamic json) {
    // إذا كانت القيمة false أو null، الخدمة غير متوفرة
    if (json == null || json == false) {
      return DeliveryServiceInfo(available: false);
    }
    
    // إذا كانت true بدون تفاصيل، الخدمة متوفرة بقيم افتراضية
    if (json == true) {
      return DeliveryServiceInfo(available: true);
    }
    
    // إذا كانت Map، نأخذ التفاصيل
    if (json is Map<String, dynamic>) {
      return DeliveryServiceInfo(
        available: true,  // وجود Map يعني الخدمة متوفرة
        estimatedTimeMinutes: json['estimated_time_minutes'] as int?,
        baseFee: json['base_fee'] != null ? (json['base_fee'] as num).toDouble() : null,
        minimumOrder: json['minimum_order'] != null ? (json['minimum_order'] as num).toDouble() : null,
      );
    }
    
    // افتراضياً: غير متوفرة
    return DeliveryServiceInfo(available: false);
  }
}
