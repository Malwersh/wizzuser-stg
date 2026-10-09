import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Service for checking version updates of menus and restaurant listings
/// خدمة للتحقق من تحديثات نسخ المنيو وقوائم المطاعم
class VersionCheckService {
  static final String baseUrl = '${ApiConfig.baseUrl}/api';
  
  /// Check if a business menu or inventory needs update
  /// التحقق من تحديثات المنيو أو المخزون لمطعم
  Future<MenuVersionCheckResult> checkMenuVersion({
    required String businessId,
    int? clientMenuVersion,
    int? clientInventoryVersion,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/check-menu-version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'businessId': businessId,
          if (clientMenuVersion != null) 'clientMenuVersion': clientMenuVersion,
          if (clientInventoryVersion != null) 'clientInventoryVersion': clientInventoryVersion,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MenuVersionCheckResult.fromJson(data);
      } else if (response.statusCode == 404) {
        throw BusinessNotFoundException(businessId);
      } else {
        throw VersionCheckException('Failed to check menu version: ${response.statusCode}');
      }
    } catch (e) {
      if (e is BusinessNotFoundException || e is VersionCheckException) rethrow;
      throw VersionCheckException('Network error: $e');
    }
  }

  /// Check if a regional restaurant listing needs update
  /// التحقق من تحديثات قائمة المطاعم في منطقة
  Future<ListingVersionCheckResult> checkListingVersion({
    required String regionId,
    int? clientListingVersion,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/check-listing-version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'regionId': regionId,
          if (clientListingVersion != null) 'clientListingVersion': clientListingVersion,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ListingVersionCheckResult.fromJson(data);
      } else if (response.statusCode == 404) {
        throw RegionNotFoundException(regionId);
      } else {
        throw VersionCheckException('Failed to check listing version: ${response.statusCode}');
      }
    } catch (e) {
      if (e is RegionNotFoundException || e is VersionCheckException) rethrow;
      throw VersionCheckException('Network error: $e');
    }
  }

  /// Batch check multiple businesses and regions at once
  /// فحص دفعة من المطاعم والمناطق دفعة واحدة
  Future<BatchVersionCheckResult> batchCheckVersions({
    List<BusinessVersionInfo>? businesses,
    List<RegionVersionInfo>? regions,
  }) async {
    if ((businesses == null || businesses.isEmpty) && 
        (regions == null || regions.isEmpty)) {
      throw ArgumentError('At least one business or region must be provided');
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/batch-check-versions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (businesses != null && businesses.isNotEmpty)
            'businesses': businesses.map((b) => b.toJson()).toList(),
          if (regions != null && regions.isNotEmpty)
            'regions': regions.map((r) => r.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BatchVersionCheckResult.fromJson(data);
      } else {
        throw VersionCheckException('Failed to batch check versions: ${response.statusCode}');
      }
    } catch (e) {
      if (e is VersionCheckException) rethrow;
      throw VersionCheckException('Network error: $e');
    }
  }
}

/// Result of menu/inventory version check
/// نتيجة فحص نسخة المنيو/المخزون
class MenuVersionCheckResult {
  final String businessId;
  final String? businessName;
  final int menuVersion;
  final int inventoryVersion;
  final bool menuNeedsUpdate;
  final bool inventoryNeedsUpdate;
  final bool needsUpdate;
  final bool isActive;
  final bool acceptingOrders;
  final String? menuLastUpdated;
  final String? inventoryLastUpdated;

  MenuVersionCheckResult({
    required this.businessId,
    this.businessName,
    required this.menuVersion,
    required this.inventoryVersion,
    required this.menuNeedsUpdate,
    required this.inventoryNeedsUpdate,
    required this.needsUpdate,
    required this.isActive,
    required this.acceptingOrders,
    this.menuLastUpdated,
    this.inventoryLastUpdated,
  });

  factory MenuVersionCheckResult.fromJson(Map<String, dynamic> json) {
    return MenuVersionCheckResult(
      businessId: json['businessId'],
      businessName: json['businessName'],
      menuVersion: json['menuVersion'],
      inventoryVersion: json['inventoryVersion'],
      menuNeedsUpdate: json['menuNeedsUpdate'] ?? false,
      inventoryNeedsUpdate: json['inventoryNeedsUpdate'] ?? false,
      needsUpdate: json['needsUpdate'] ?? false,
      isActive: json['isActive'] ?? true,
      acceptingOrders: json['acceptingOrders'] ?? false,
      menuLastUpdated: json['menuLastUpdated'],
      inventoryLastUpdated: json['inventoryLastUpdated'],
    );
  }
}

/// Result of regional listing version check
/// نتيجة فحص نسخة قائمة المنطقة
class ListingVersionCheckResult {
  final String regionId;
  final String? regionName;
  final String? regionNameAr;
  final int listingVersion;
  final bool needsUpdate;
  final int totalBusinesses;
  final int activeBusinesses;
  final int availableBusinesses;
  final bool hasBusinesses;
  final bool hasAvailableBusinesses;
  final String? lastUpdated;

  ListingVersionCheckResult({
    required this.regionId,
    this.regionName,
    this.regionNameAr,
    required this.listingVersion,
    required this.needsUpdate,
    required this.totalBusinesses,
    required this.activeBusinesses,
    required this.availableBusinesses,
    required this.hasBusinesses,
    required this.hasAvailableBusinesses,
    this.lastUpdated,
  });

  factory ListingVersionCheckResult.fromJson(Map<String, dynamic> json) {
    return ListingVersionCheckResult(
      regionId: json['regionId'],
      regionName: json['regionName'],
      regionNameAr: json['regionName_ar'],
      listingVersion: json['listingVersion'],
      needsUpdate: json['needsUpdate'] ?? false,
      totalBusinesses: json['totalBusinesses'] ?? 0,
      activeBusinesses: json['activeBusinesses'] ?? 0,
      availableBusinesses: json['availableBusinesses'] ?? 0,
      hasBusinesses: json['hasBusinesses'] ?? false,
      hasAvailableBusinesses: json['hasAvailableBusinesses'] ?? false,
      lastUpdated: json['lastUpdated'],
    );
  }
}

/// Batch check result
/// نتيجة الفحص الدفعي
class BatchVersionCheckResult {
  final List<MenuVersionCheckResult> businesses;
  final List<ListingVersionCheckResult> regions;
  final BatchSummary summary;

  BatchVersionCheckResult({
    required this.businesses,
    required this.regions,
    required this.summary,
  });

  factory BatchVersionCheckResult.fromJson(Map<String, dynamic> json) {
    return BatchVersionCheckResult(
      businesses: (json['businesses'] as List?)
              ?.map((b) => MenuVersionCheckResult.fromJson(b))
              .toList() ??
          [],
      regions: (json['regions'] as List?)
              ?.map((r) => ListingVersionCheckResult.fromJson(r))
              .toList() ??
          [],
      summary: BatchSummary.fromJson(json['summary'] ?? {}),
    );
  }
}

class BatchSummary {
  final int totalChecked;
  final int needsUpdate;

  BatchSummary({
    required this.totalChecked,
    required this.needsUpdate,
  });

  factory BatchSummary.fromJson(Map<String, dynamic> json) {
    return BatchSummary(
      totalChecked: json['totalChecked'] ?? 0,
      needsUpdate: json['needsUpdate'] ?? 0,
    );
  }
}

/// Business version info for batch checking
/// معلومات نسخة المطعم للفحص الدفعي
class BusinessVersionInfo {
  final String businessId;
  final int? menuVersion;
  final int? inventoryVersion;

  BusinessVersionInfo({
    required this.businessId,
    this.menuVersion,
    this.inventoryVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'businessId': businessId,
      if (menuVersion != null) 'menuVersion': menuVersion,
      if (inventoryVersion != null) 'inventoryVersion': inventoryVersion,
    };
  }
}

/// Region version info for batch checking
/// معلومات نسخة المنطقة للفحص الدفعي
class RegionVersionInfo {
  final String regionId;
  final int? listingVersion;

  RegionVersionInfo({
    required this.regionId,
    this.listingVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'regionId': regionId,
      if (listingVersion != null) 'listingVersion': listingVersion,
    };
  }
}

/// Exceptions
class VersionCheckException implements Exception {
  final String message;
  VersionCheckException(this.message);

  @override
  String toString() => 'VersionCheckException: $message';
}

class BusinessNotFoundException implements Exception {
  final String businessId;
  BusinessNotFoundException(this.businessId);

  @override
  String toString() => 'Business not found: $businessId';
}

class RegionNotFoundException implements Exception {
  final String regionId;
  RegionNotFoundException(this.regionId);

  @override
  String toString() => 'Region not found: $regionId';
}
