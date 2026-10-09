// lib/services/availability_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../config/api_config.dart';

/// Service for managing restaurant availability and real-time updates
class AvailabilityService {
  static String get _availabilityBaseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  /// Check individual store availability with configurable depth
  static Future<Map<String, dynamic>?> checkStoreAvailability({
    required String storeId,
    String depth = 'basic', // basic, detailed, pricing, scheduling
    double? userLat,
    double? userLng,
  }) async {
    try {
      final uri = Uri.parse('$_availabilityBaseUrl/availability/store/$storeId')
          .replace(queryParameters: {
        'depth': depth,
        if (userLat != null) 'lat': userLat.toString(),
        if (userLng != null) 'lng': userLng.toString(),
      });

      final response = await http.get(
        uri,
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['availability'];
        }
      }

      debugPrint('فشل في التحقق من توفر المتجر: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('خطأ في التحقق من توفر المتجر: $e');
      return null;
    }
  }

  /// Get enhanced business listings with availability filtering
  static Future<Map<String, dynamic>> getBusinessesWithAvailability({
    int page = 1,
    int limit = 20,
    String? category,
    bool? available,
    double? userLat,
    double? userLng,
    String? search,
    bool newOnly = false,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (category != null) 'category': category,
        if (available != null) 'available': available.toString(),
        if (userLat != null) 'lat': userLat.toString(),
        if (userLng != null) 'lng': userLng.toString(),
        if (search != null) 'search': search,
        if (newOnly) 'new': 'true',
      };

      final uri = Uri.parse('$_availabilityBaseUrl/businesses/enhanced')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return {
            'businesses': data['businesses'] ?? [],
            'count': data['count'] ?? 0,
            'total': data['total'] ?? 0,
            'page': data['page'] ?? page,
            'hasMore': data['hasMore'] ?? false,
            'availabilityMetrics': data['availabilityMetrics'] ?? {},
          };
        }
      }

      debugPrint('فشل في جلب المطاعم مع التوفر: ${response.statusCode}');
      return _getEmptyResult();
    } catch (e) {
      debugPrint('خطأ في جلب المطاعم مع التوفر: $e');
      return _getEmptyResult();
    }
  }

  /// Get current user location with permission handling
  static Future<Position?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        return null;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      debugPrint('موقع المستخدم: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      debugPrint('خطأ في الحصول على الموقع: $e');
      return null;
    }
  }

  /// Calculate distance between user and store
  static double calculateDistance({
    required double userLat,
    required double userLng,
    required double storeLat,
    required double storeLng,
  }) {
    return Geolocator.distanceBetween(
      userLat,
      userLng,
      storeLat,
      storeLng,
    ) / 1000; // Convert to kilometers
  }

  /// Check if store is within delivery radius
  static bool isWithinDeliveryRadius({
    required double userLat,
    required double userLng,
    required double storeLat,
    required double storeLng,
    required double deliveryRadiusKm,
  }) {
    final distance = calculateDistance(
      userLat: userLat,
      userLng: userLng,
      storeLat: storeLat,
      storeLng: storeLng,
    );
    return distance <= deliveryRadiusKm;
  }

  /// Filter businesses by availability status
  static List<Map<String, dynamic>> filterByAvailability(
    List<Map<String, dynamic>> businesses, {
    bool? onlyAvailable,
    bool? onlyOpen,
    bool? onlyAcceptingOrders,
  }) {
    return businesses.where((business) {
      final availability = business['availability'] as Map<String, dynamic>?;
      if (availability == null) return false;

      if (onlyAvailable == true && availability['isAvailable'] != true) {
        return false;
      }

      if (onlyOpen == true && availability['isOpen'] != true) {
        return false;
      }

      if (onlyAcceptingOrders == true && availability['acceptingOrders'] != true) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Sort businesses by availability priority
  static List<Map<String, dynamic>> sortByAvailability(
    List<Map<String, dynamic>> businesses, {
    double? userLat,
    double? userLng,
  }) {
    return List.from(businesses)..sort((a, b) {
      final aAvailability = a['availability'] as Map<String, dynamic>?;
      final bAvailability = b['availability'] as Map<String, dynamic>?;

      // Available stores first
      final aAvailable = aAvailability?['isAvailable'] == true;
      final bAvailable = bAvailability?['isAvailable'] == true;

      if (aAvailable && !bAvailable) return -1;
      if (!aAvailable && bAvailable) return 1;

      // If both available or both unavailable, sort by capacity
      if (aAvailable && bAvailable) {
        final aCapacity = aAvailability?['capacityUtilization'] as double? ?? 100;
        final bCapacity = bAvailability?['capacityUtilization'] as double? ?? 100;
        
        final capacityComparison = aCapacity.compareTo(bCapacity);
        if (capacityComparison != 0) return capacityComparison;
      }

      // Finally sort by distance if user location is available
      if (userLat != null && userLng != null) {
        final aLat = a['latitude'] as double?;
        final aLng = a['longitude'] as double?;
        final bLat = b['latitude'] as double?;
        final bLng = b['longitude'] as double?;

        if (aLat != null && aLng != null && bLat != null && bLng != null) {
          final aDistance = calculateDistance(
            userLat: userLat,
            userLng: userLng,
            storeLat: aLat,
            storeLng: aLng,
          );
          final bDistance = calculateDistance(
            userLat: userLat,
            userLng: userLng,
            storeLat: bLat,
            storeLng: bLng,
          );
          return aDistance.compareTo(bDistance);
        }
      }

      return 0;
    });
  }

  /// Get availability status text for display
  static String getAvailabilityStatusText(Map<String, dynamic>? availability) {
    if (availability == null) return 'غير معروف';

    if (availability['isAvailable'] == true) {
      return 'متوفر الآن';
    } else if (availability['isOpen'] == false) {
      final nextOpenTime = availability['nextAvailableTime'] as String?;
      if (nextOpenTime != null) {
        return 'مغلق - يفتح في $nextOpenTime';
      }
      return 'مغلق';
    } else if (availability['acceptingOrders'] == false) {
      return 'لا يستقبل طلبات';
    } else {
      return 'غير متوفر';
    }
  }

  /// Get availability color for UI display
  static String getAvailabilityColor(Map<String, dynamic>? availability) {
    if (availability == null) return '#CCCCCC';

    if (availability['isAvailable'] == true) {
      final utilization = availability['capacityUtilization'] as double? ?? 0;
      if (utilization < 50) return '#4CAF50'; // Green
      if (utilization < 80) return '#FF9800'; // Orange
      return '#F44336'; // Red (busy)
    }

    return '#CCCCCC'; // Grey (unavailable)
  }

  /// Format estimated delivery time
  static String formatDeliveryTime(Map<String, dynamic>? availability) {
    if (availability == null) return 'غير محدد';

    final deliveryTime = availability['estimatedDeliveryTime'] as int?;
    if (deliveryTime != null) {
      return '$deliveryTime دقيقة';
    }

    final leadTime = availability['leadTime'] as int?;
    if (leadTime != null) {
      return '$leadTime دقيقة';
    }

    return 'غير محدد';
  }

  /// Private helper methods
  static Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  static Map<String, dynamic> _getEmptyResult() {
    return {
      'businesses': <Map<String, dynamic>>[],
      'count': 0,
      'total': 0,
      'page': 1,
      'hasMore': false,
      'availabilityMetrics': {},
    };
  }
}

/// Data models for availability responses
class StoreAvailability {
  final bool isAvailable;
  final bool isOpen;
  final bool acceptingOrders;
  final double capacityUtilization;
  final int? estimatedDeliveryTime;
  final int? leadTime;
  final String? nextAvailableTime;
  final String? reason;
  final Map<String, dynamic>? deliveryZone;
  final Map<String, dynamic>? pricing;

  StoreAvailability({
    required this.isAvailable,
    required this.isOpen,
    required this.acceptingOrders,
    required this.capacityUtilization,
    this.estimatedDeliveryTime,
    this.leadTime,
    this.nextAvailableTime,
    this.reason,
    this.deliveryZone,
    this.pricing,
  });

  factory StoreAvailability.fromJson(Map<String, dynamic> json) {
    return StoreAvailability(
      isAvailable: json['isAvailable'] ?? false,
      isOpen: json['isOpen'] ?? false,
      acceptingOrders: json['acceptingOrders'] ?? false,
      capacityUtilization: (json['capacityUtilization'] ?? 0).toDouble(),
      estimatedDeliveryTime: json['estimatedDeliveryTime'],
      leadTime: json['leadTime'],
      nextAvailableTime: json['nextAvailableTime'],
      reason: json['reason'],
      deliveryZone: json['deliveryZone'],
      pricing: json['pricing'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isAvailable': isAvailable,
      'isOpen': isOpen,
      'acceptingOrders': acceptingOrders,
      'capacityUtilization': capacityUtilization,
      'estimatedDeliveryTime': estimatedDeliveryTime,
      'leadTime': leadTime,
      'nextAvailableTime': nextAvailableTime,
      'reason': reason,
      'deliveryZone': deliveryZone,
      'pricing': pricing,
    };
  }
}
