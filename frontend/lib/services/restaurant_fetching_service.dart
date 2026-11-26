import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/browsing_location.dart';
import '../models/delivery_address.dart';
import '../models/restaurant_list_response.dart';
import '../config.dart';
import 'session_service.dart';

/// Service for fetching restaurants based on delivery address
/// خدمة جلب المطاعم بناءً على عنوان التوصيل
class RestaurantFetchingService {
  // Singleton pattern
  RestaurantFetchingService._();
  static final RestaurantFetchingService instance = RestaurantFetchingService._();

  /// Fetch restaurants by delivery address
  /// جلب المطاعم بناءً على عنوان التوصيل الفعّال
  Future<RestaurantListResponse> fetchRestaurantsByDeliveryAddress({
    required DeliveryAddress deliveryAddress,
    int page = 0,
    int limit = 20,
    String? category,
    bool newOnly = false,
    String? sortBy, // 'rating', 'distance', 'delivery_time'
  }) async {
    debugPrint('🍽️ جلب المطاعم لـ: ${deliveryAddress.formattedAddress}');

    try {
      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'latitude': deliveryAddress.latitude.toString(),
        'longitude': deliveryAddress.longitude.toString(),
      };

      // Use region_id if available (preferred method)
      if (deliveryAddress.regionId != null && deliveryAddress.regionId!.isNotEmpty) {
        queryParams['region_id'] = deliveryAddress.regionId!;
        debugPrint('   🗺️ المنطقة: ${deliveryAddress.regionId}');
      } else {
        // Fallback: use coordinates
        queryParams['latitude'] = deliveryAddress.latitude.toString();
        queryParams['longitude'] = deliveryAddress.longitude.toString();
        queryParams['radius_km'] = '20'; // Default search radius
        debugPrint('   📍 الإحداثيات: ${deliveryAddress.latitude}, ${deliveryAddress.longitude}');
      }

      // Optional filters
      if (category != null && category.isNotEmpty) {
        queryParams['category'] = category;
      }
      if (newOnly) {
        queryParams['new'] = 'true';
      }
      if (sortBy != null && sortBy.isNotEmpty) {
        queryParams['sort'] = sortBy;
      }

      // Build URL - استخدام Smart Delivery APIs الجديدة
      String endpoint;
      if (deliveryAddress.regionId != null && deliveryAddress.regionId!.isNotEmpty) {
        // استخدام endpoint المنطقة
        endpoint = '${ApiConfig.baseUrl}${ApiConfig.getBusinessesByRegionEndpoint}?${_buildQueryString(queryParams)}';
      } else {
        // استخدام endpoint الإحداثيات
        endpoint = '${ApiConfig.baseUrl}${ApiConfig.getNearbyBusinessesEndpoint}?${_buildQueryString(queryParams)}';
      }
      
      var url = Uri.parse(endpoint);
      final headers = await _getHeaders();
      var response = await http.get(url, headers: headers).timeout(ApiConfig.apiTimeout);
      while (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final paging = data?['pagination'];
        final scannedPage = paging?['page'];
        if (paging?['candidateTotal'] == null ||
            paging?['hasMore'] != true ||
            data?['businesses'] is! List ||
            (data['businesses'] as List).isNotEmpty ||
            scannedPage is! int ||
            scannedPage != int.tryParse(url.queryParameters['page'] ?? '')) {
          break;
        }
        url = url.replace(queryParameters: {
          ...url.queryParameters,
          'page': (scannedPage + 1).toString(),
        });
        response = await http.get(url, headers: headers).timeout(ApiConfig.apiTimeout);
      }

      debugPrint('   📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // 🔍 طباعة عدد المطاعم من الـ API مباشرة
        debugPrint('   📊 API Response - success: ${data['success']}');
        final apiBusinesses = (data['data']?['businesses'] as List<dynamic>?) ?? [];
        debugPrint('   📊 API returned ${apiBusinesses.length} restaurants in response');
        for (var i = 0; i < apiBusinesses.length; i++) {
          final b = apiBusinesses[i] as Map<String, dynamic>;
          final name = b['businessName'] ?? b['business_name'] ?? 'unknown';
          final id = b['businessId'] ?? b['business_id'] ?? 'no-id';
          debugPrint('      API [$i]: $name ($id)');
        }

        if (data['success'] == true) {
          final result = RestaurantListResponse.fromApiResponse(data['data']);
          debugPrint('   ✅ تم جلب ${result.length} مطعم (بعد التحويل)');
          return result;
        } else {
          throw Exception(data['message'] ?? 'فشل جلب المطاعم');
        }
      } else if (response.statusCode == 404) {
        debugPrint('   ⚠️ لا توجد مطاعم في هذه المنطقة');
        return RestaurantListResponse.empty(regionId: deliveryAddress.regionId);
      } else {
        throw Exception('خطأ في الخادم: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('   ❌ خطأ في جلب المطاعم: $e');
      rethrow;
    }
  }

  Future<RestaurantListResponse> fetchRestaurantsForBrowsingLocation({
    required BrowsingLocation location,
    int page = 0,
    int limit = 20,
  }) {
    if (!location.hasPoint) {
      return Future.value(RestaurantListResponse.empty(regionId: location.regionId));
    }
    return fetchRestaurantsByDeliveryAddress(
      deliveryAddress: DeliveryAddress(
        formattedAddress: location.addressText ?? location.regionName,
        latitude: location.latitude!,
        longitude: location.longitude!,
        regionId: location.regionId,
        regionNameAr: location.regionName,
        city: location.regionName,
        source: AddressSource.manual,
      ),
      page: page,
      limit: limit,
    );
  }

  /// Fetch nearby restaurants using coordinates directly
  /// جلب المطاعم القريبة باستخدام الإحداثيات مباشرة
  Future<RestaurantListResponse> fetchNearbyRestaurants({
    required double latitude,
    required double longitude,
    double radiusKm = 20.0,
    int limit = 20,
    String? category,
    String sortBy = 'distance',
  }) async {
    debugPrint('🔍 جلب المطاعم القريبة...');
    debugPrint('   📍 الموقع: $latitude, $longitude');
    debugPrint('   📏 نصف القطر: $radiusKm km');

    try {
      final queryParams = <String, String>{
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'radius_km': radiusKm.toString(),
        'limit': limit.toString(),
        'sort': sortBy,
      };

      if (category != null && category.isNotEmpty) {
        queryParams['category'] = category;
      }

      // ✅ Fix: include baseUrl to build absolute URL
      final url = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.getNearbyBusinessesEndpoint}?${_buildQueryString(queryParams)}',
      );
      debugPrint('   🌐 API (nearby): $url');

      final response = await http.get(
        url,
        headers: await _getHeaders(),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          final result = RestaurantListResponse.fromApiResponse(data['data']);
          debugPrint('   ✅ تم جلب ${result.length} مطعم قريب');
          return result;
        } else {
          throw Exception(data['message'] ?? 'فشل جلب المطاعم القريبة');
        }
      } else if (response.statusCode == 404) {
        debugPrint('   ⚠️ لا توجد مطاعم قريبة');
        return RestaurantListResponse.empty();
      } else {
        throw Exception('خطأ في الخادم: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('   ❌ خطأ في جلب المطاعم القريبة: $e');
      rethrow;
    }
  }

  /// Check if a restaurant serves a specific address
  /// التحقق من إمكانية توصيل مطعم لعنوان محدد
  Future<DeliveryAvailabilityResult> doesRestaurantServeAddress({
    required String businessId,
    required DeliveryAddress address,
  }) async {
    debugPrint('🚚 التحقق من تغطية التوصيل...');
    debugPrint('   مطعم: $businessId');
    debugPrint('   عنوان: ${address.formattedAddress}');

    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/businesses/$businessId/serves-address',
      );

      final body = jsonEncode({
        'latitude': address.latitude,
        'longitude': address.longitude,
        'region_id': address.regionId,
      });

      final response = await http.post(
        url,
        headers: await _getHeaders(),
        body: body,
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          final result = data['data'] as Map<String, dynamic>;
          debugPrint('   ${result['serves'] == true ? "✅" : "❌"} ${result['message']}');

          return DeliveryAvailabilityResult.fromJson(result);
        } else {
          throw Exception(data['message'] ?? 'فشل التحقق');
        }
      } else {
        throw Exception('خطأ في الخادم: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('   ❌ خطأ في التحقق: $e');
      rethrow;
    }
  }

  /// Fetch restaurants with neighbor regions included
  /// جلب المطاعم مع المناطق المجاورة
  Future<RestaurantListResponse> fetchRestaurantsWithNeighbors({
    required String regionId,
    int page = 0,
    int limit = 20,
    double maxDistanceKm = 10.0,
  }) async {
    debugPrint('🌐 جلب المطاعم مع المناطق المجاورة...');
    debugPrint('   المنطقة: $regionId');

    try {
      final queryParams = <String, String>{
        'region_id': regionId,
        'include_neighbors': 'true',
        'max_distance_km': maxDistanceKm.toString(),
        'page': page.toString(),
        'limit': limit.toString(),
      };

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/businesses?${_buildQueryString(queryParams)}',
      );
      debugPrint('   🌐 API (neighbors): $url');

      final response = await http.get(
        url,
        headers: await _getHeaders(),
      ).timeout(Duration(seconds: 15)); // Longer timeout for complex query

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          final result = RestaurantListResponse.fromApiResponse(data['data']);
          debugPrint('   ✅ تم جلب ${result.length} مطعم (مع المجاورة)');
          return result;
        } else {
          throw Exception(data['message'] ?? 'فشل جلب المطاعم');
        }
      } else {
        throw Exception('خطأ في الخادم: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('   ❌ خطأ: $e');
      rethrow;
    }
  }

  /// Build query string from parameters
  /// بناء query string من المعاملات
  String _buildQueryString(Map<String, String> params) {
    return params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// Get HTTP headers
  /// الحصول على HTTP headers
  Future<Map<String, String>> _getHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // إضافة توكن المصادقة إذا كان متاحاً لإتاحة الوصول لنقاط الجيران وNearby
    try {
      // انتظر جاهزية الجلسة بشكل خفيف لتجنب السباق عند بدء التطبيق
      await SessionService.instance.waitForSessionReady();
      final token = await SessionService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // تجاهل أخطاء الجلسة هنا؛ الطلبات العامة ستظل تعمل بدون التوكن
    }

    return headers;
  }
}

/// Result of delivery availability check
/// نتيجة التحقق من تغطية التوصيل
class DeliveryAvailabilityResult {
  final bool serves;
  final String businessId;
  final String businessName;
  final double distance;
  final String? estimatedDeliveryTime;
  final int? deliveryFee;
  final String message;
  final String? reason;
  final double? maxDeliveryDistance;

  DeliveryAvailabilityResult({
    required this.serves,
    required this.businessId,
    required this.businessName,
    required this.distance,
    this.estimatedDeliveryTime,
    this.deliveryFee,
    required this.message,
    this.reason,
    this.maxDeliveryDistance,
  });

  factory DeliveryAvailabilityResult.fromJson(Map<String, dynamic> json) {
    return DeliveryAvailabilityResult(
      serves: json['serves'] as bool,
      businessId: json['businessId'] as String,
      businessName: json['businessName'] as String,
      distance: (json['distance'] as num).toDouble(),
      estimatedDeliveryTime: json['estimatedDeliveryTime'] as String?,
      deliveryFee: json['deliveryFee'] as int?,
      message: json['message'] as String,
      reason: json['reason'] as String?,
      maxDeliveryDistance: json['maxDeliveryDistance'] != null
          ? (json['maxDeliveryDistance'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serves': serves,
      'businessId': businessId,
      'businessName': businessName,
      'distance': distance,
      'estimatedDeliveryTime': estimatedDeliveryTime,
      'deliveryFee': deliveryFee,
      'message': message,
      'reason': reason,
      'maxDeliveryDistance': maxDeliveryDistance,
    };
  }

  @override
  String toString() {
    return 'DeliveryAvailabilityResult('
        'serves: $serves, '
        'business: $businessName, '
        'distance: ${distance.toStringAsFixed(2)} km'
        ')';
  }
}
