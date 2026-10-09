import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Service for looking up regions by coordinates using H3 geospatial index
/// خدمة البحث عن المناطق باستخدام الإحداثيات والفهرس الجغرافي H3
class RegionLookupService {
  // Singleton pattern
  RegionLookupService._();
  static final RegionLookupService instance = RegionLookupService._();

  // Cache for region lookups
  final Map<String, RegionInfo> _cache = {};
  static const int _cacheDurationMinutes = 60;

  /// Find region by coordinates
  /// إيجاد المنطقة من الإحداثيات
  Future<RegionInfo?> findRegionByCoordinates({
    required double latitude,
    required double longitude,
    int resolution = 9, // H3 resolution level
  }) async {
    debugPrint('🗺️ البحث عن منطقة للإحداثيات...');
    debugPrint('   📍 $latitude, $longitude');

    // Check cache first
    final cacheKey = '${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}';
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.cachedAt).inMinutes < _cacheDurationMinutes) {
        debugPrint('   💾 تم العثور في الذاكرة المؤقتة');
        return cached;
      } else {
        debugPrint('   ⏰ الذاكرة المؤقتة منتهية الصلاحية');
        _cache.remove(cacheKey);
      }
    }

    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/regions/find-by-coordinates'
        '?latitude=$latitude&longitude=$longitude&resolution=$resolution',
      );

      final response = await http.get(url).timeout(Duration(seconds: 10));

      debugPrint('   📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          final regionInfo = RegionInfo.fromJson(data['data']);
          debugPrint('   ✅ تم العثور على المنطقة: ${regionInfo.regionNameAr}');

          // Cache the result
          _cache[cacheKey] = regionInfo;

          return regionInfo;
        } else {
          throw Exception(data['message'] ?? 'فشل إيجاد المنطقة');
        }
      } else if (response.statusCode == 404) {
        debugPrint('   ⚠️ لا توجد منطقة خدمة لهذه الإحداثيات');
        return null;
      } else {
        throw Exception('خطأ في الخادم: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('   ❌ خطأ في البحث عن المنطقة: $e');
      rethrow;
    }
  }

  /// Batch lookup for multiple coordinates
  /// بحث دفعي عن عدة إحداثيات
  Future<Map<String, RegionInfo?>> batchFindRegions({
    required List<CoordinatePair> coordinates,
  }) async {
    debugPrint('🗺️ بحث دفعي عن ${coordinates.length} موقع');

    final results = <String, RegionInfo?>{};

    // Process in parallel (max 5 at a time to avoid overload)
    final futures = <Future<void>>[];
    for (var i = 0; i < coordinates.length; i++) {
      final coord = coordinates[i];
      final key = coord.key ?? 'coord_$i';

      futures.add(
        findRegionByCoordinates(
          latitude: coord.latitude,
          longitude: coord.longitude,
        ).then((result) {
          results[key] = result;
        }).catchError((error) {
          debugPrint('   ⚠️ خطأ في $key: $error');
          results[key] = null;
        }),
      );

      // Process in batches of 5
      if (futures.length >= 5 || i == coordinates.length - 1) {
        await Future.wait(futures);
        futures.clear();
      }
    }

    debugPrint('   ✅ اكتمل البحث الدفعي: ${results.length} نتيجة');
    return results;
  }

  /// Clear cache
  /// مسح الذاكرة المؤقتة
  void clearCache() {
    _cache.clear();
    debugPrint('   🗑️ تم مسح ذاكرة المناطق المؤقتة');
  }

  /// Get cache statistics
  /// الحصول على إحصائيات الذاكرة المؤقتة
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    final validEntries = _cache.values
        .where((entry) => now.difference(entry.cachedAt).inMinutes < _cacheDurationMinutes)
        .length;

    return {
      'totalEntries': _cache.length,
      'validEntries': validEntries,
      'expiredEntries': _cache.length - validEntries,
      'cacheDurationMinutes': _cacheDurationMinutes,
    };
  }
}

/// Model for region information
/// نموذج معلومات المنطقة
class RegionInfo {
  final String regionId;
  final String regionNameAr;
  final String regionNameEn;
  final String city;
  final String h3Cell;
  final double latitude;
  final double longitude;
  final BoundingBox? boundingBox;
  final DateTime cachedAt;

  RegionInfo({
    required this.regionId,
    required this.regionNameAr,
    required this.regionNameEn,
    required this.city,
    required this.h3Cell,
    required this.latitude,
    required this.longitude,
    this.boundingBox,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  factory RegionInfo.fromJson(Map<String, dynamic> json) {
    return RegionInfo(
      regionId: json['region_id'] as String,
      regionNameAr: json['region_name_ar'] as String,
      regionNameEn: json['region_name_en'] as String,
      city: json['city'] as String,
      h3Cell: json['h3Cell'] as String,
      latitude: (json['coordinates']['latitude'] as num).toDouble(),
      longitude: (json['coordinates']['longitude'] as num).toDouble(),
      boundingBox: json['boundingBox'] != null
          ? BoundingBox.fromJson(json['boundingBox'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'region_id': regionId,
      'region_name_ar': regionNameAr,
      'region_name_en': regionNameEn,
      'city': city,
      'h3Cell': h3Cell,
      'coordinates': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'boundingBox': boundingBox?.toJson(),
    };
  }

  @override
  String toString() {
    return 'RegionInfo('
        'regionId: $regionId, '
        'name: $regionNameAr, '
        'city: $city, '
        'h3Cell: $h3Cell'
        ')';
  }
}

/// Bounding box for a region
/// الصندوق المحيط بالمنطقة
class BoundingBox {
  final double north;
  final double south;
  final double east;
  final double west;

  BoundingBox({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      north: (json['north'] as num).toDouble(),
      south: (json['south'] as num).toDouble(),
      east: (json['east'] as num).toDouble(),
      west: (json['west'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'north': north,
      'south': south,
      'east': east,
      'west': west,
    };
  }

  /// Check if coordinates are within this bounding box
  /// التحقق من وجود إحداثيات داخل الصندوق المحيط
  bool contains(double latitude, double longitude) {
    return latitude >= south &&
        latitude <= north &&
        longitude >= west &&
        longitude <= east;
  }

  @override
  String toString() {
    return 'BoundingBox(N:$north, S:$south, E:$east, W:$west)';
  }
}

/// Coordinate pair for batch operations
/// زوج إحداثيات للعمليات الدفعية
class CoordinatePair {
  final double latitude;
  final double longitude;
  final String? key; // Optional identifier

  CoordinatePair({
    required this.latitude,
    required this.longitude,
    this.key,
  });

  @override
  String toString() {
    return 'CoordinatePair(${key ?? ""}lat:$latitude, lng:$longitude)';
  }
}
