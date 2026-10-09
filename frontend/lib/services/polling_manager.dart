import 'dart:async';
import 'package:flutter/foundation.dart';
import 'version_check_service.dart';

/// Manager for version checking polling
/// مدير لعملية polling فحص النسخ
class PollingManager {
  final VersionCheckService _versionCheckService = VersionCheckService();
  
  Timer? _menuPollTimer;
  Timer? _listingPollTimer;
  Timer? _batchPollTimer;

  // Polling intervals (in seconds)
  static const int menuPollingInterval = 30; // 30 seconds for menu
  static const int inventoryPollingInterval = 30; // 30 seconds for inventory
  static const int listingPollingInterval = 60; // 60 seconds for listings
  static const int batchPollingInterval = 45; // 45 seconds for batch

  bool _isPollingMenu = false;
  bool _isPollingListing = false;
  bool _isPollingBatch = false;

  /// Start polling for menu/inventory updates
  /// بدء polling لتحديثات المنيو/المخزون
  void startMenuPolling({
    required String businessId,
    required int? currentMenuVersion,
    required int? currentInventoryVersion,
    required Function(MenuVersionCheckResult) onUpdate,
    int? customInterval,
  }) {
    if (_isPollingMenu) {
      debugPrint('⚠️ Menu polling already active for $businessId');
      return;
    }

    _isPollingMenu = true;
    final interval = customInterval ?? menuPollingInterval;
    
    debugPrint('✅ Started menu polling for $businessId (every ${interval}s)');

    _menuPollTimer = Timer.periodic(
      Duration(seconds: interval),
      (timer) async {
        try {
          final result = await _versionCheckService.checkMenuVersion(
            businessId: businessId,
            clientMenuVersion: currentMenuVersion,
            clientInventoryVersion: currentInventoryVersion,
          );

          if (result.needsUpdate) {
            debugPrint('🔄 Update detected for $businessId');
            debugPrint('   Menu: ${result.menuNeedsUpdate ? "YES" : "NO"}');
            debugPrint('   Inventory: ${result.inventoryNeedsUpdate ? "YES" : "NO"}');
            onUpdate(result);
          } else {
            debugPrint('✓ No updates for $businessId');
          }
        } catch (e) {
          debugPrint('❌ Menu polling error for $businessId: $e');
        }
      },
    );
  }

  /// Stop menu polling
  /// إيقاف polling المنيو
  void stopMenuPolling() {
    _menuPollTimer?.cancel();
    _menuPollTimer = null;
    _isPollingMenu = false;
    debugPrint('🛑 Stopped menu polling');
  }

  /// Start polling for regional listing updates
  /// بدء polling لتحديثات قائمة المنطقة
  void startListingPolling({
    required String regionId,
    required int? currentListingVersion,
    required Function(ListingVersionCheckResult) onUpdate,
    int? customInterval,
  }) {
    if (_isPollingListing) {
      debugPrint('⚠️ Listing polling already active for $regionId');
      return;
    }

    _isPollingListing = true;
    final interval = customInterval ?? listingPollingInterval;
    
    debugPrint('✅ Started listing polling for $regionId (every ${interval}s)');

    _listingPollTimer = Timer.periodic(
      Duration(seconds: interval),
      (timer) async {
        try {
          final result = await _versionCheckService.checkListingVersion(
            regionId: regionId,
            clientListingVersion: currentListingVersion,
          );

          if (result.needsUpdate) {
            debugPrint('🔄 Listing update detected for $regionId');
            debugPrint('   Total businesses: ${result.totalBusinesses}');
            debugPrint('   Available: ${result.availableBusinesses}');
            onUpdate(result);
          } else {
            debugPrint('✓ No listing updates for $regionId');
          }
        } catch (e) {
          debugPrint('❌ Listing polling error for $regionId: $e');
        }
      },
    );
  }

  /// Stop listing polling
  /// إيقاف polling القائمة
  void stopListingPolling() {
    _listingPollTimer?.cancel();
    _listingPollTimer = null;
    _isPollingListing = false;
    debugPrint('🛑 Stopped listing polling');
  }

  /// Start batch polling for multiple items
  /// بدء polling دفعي لعدة عناصر
  void startBatchPolling({
    required List<BusinessVersionInfo> businesses,
    required List<RegionVersionInfo> regions,
    required Function(BatchVersionCheckResult) onUpdate,
    int? customInterval,
  }) {
    if (_isPollingBatch) {
      debugPrint('⚠️ Batch polling already active');
      return;
    }

    if (businesses.isEmpty && regions.isEmpty) {
      debugPrint('⚠️ No items to poll in batch');
      return;
    }

    _isPollingBatch = true;
    final interval = customInterval ?? batchPollingInterval;
    
    debugPrint('✅ Started batch polling (${businesses.length} businesses, ${regions.length} regions) every ${interval}s');

    _batchPollTimer = Timer.periodic(
      Duration(seconds: interval),
      (timer) async {
        try {
          final result = await _versionCheckService.batchCheckVersions(
            businesses: businesses,
            regions: regions,
          );

          if (result.summary.needsUpdate > 0) {
            debugPrint('🔄 Batch updates detected: ${result.summary.needsUpdate}/${result.summary.totalChecked}');
            onUpdate(result);
          } else {
            debugPrint('✓ No batch updates (checked ${result.summary.totalChecked} items)');
          }
        } catch (e) {
          debugPrint('❌ Batch polling error: $e');
        }
      },
    );
  }

  /// Stop batch polling
  /// إيقاف polling الدفعي
  void stopBatchPolling() {
    _batchPollTimer?.cancel();
    _batchPollTimer = null;
    _isPollingBatch = false;
    debugPrint('🛑 Stopped batch polling');
  }

  /// Stop all polling
  /// إيقاف جميع عمليات polling
  void stopAll() {
    stopMenuPolling();
    stopListingPolling();
    stopBatchPolling();
    debugPrint('🛑 Stopped all polling');
  }

  /// Check if any polling is active
  /// التحقق من وجود أي polling نشط
  bool get isAnyPollingActive =>
      _isPollingMenu || _isPollingListing || _isPollingBatch;

  /// Get polling status
  /// الحصول على حالة polling
  Map<String, bool> get pollingStatus => {
        'menu': _isPollingMenu,
        'listing': _isPollingListing,
        'batch': _isPollingBatch,
      };

  /// Dispose and cleanup
  /// تنظيف الموارد
  void dispose() {
    stopAll();
    debugPrint('🗑️ PollingManager disposed');
  }
}

/// Mixin for easy polling management in widgets/providers
/// Mixin لإدارة polling سهلة في الويدجتس/providers
mixin PollingMixin {
  PollingManager? _pollingManager;

  PollingManager get pollingManager {
    _pollingManager ??= PollingManager();
    return _pollingManager!;
  }

  /// Clean up polling when disposing
  /// تنظيف polling عند dispose
  void disposePolling() {
    _pollingManager?.dispose();
    _pollingManager = null;
  }
}
