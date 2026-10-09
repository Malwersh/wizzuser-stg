import 'package:flutter/foundation.dart';
import '../services/version_check_service.dart';
import '../services/polling_manager.dart';
import '../services/restaurant_fetching_service.dart';
import '../services/delivery_address_manager.dart';

/// Provider with version checking and polling support
/// مثال على Provider مع دعم فحص النسخ وpolling
class MenuProviderWithVersioning with ChangeNotifier, PollingMixin {
  // Version tracking
  int? _menuVersion;
  int? _inventoryVersion;
  
  // Data
  Map<String, dynamic>? _menuData;
  bool _isLoading = false;
  String? _error;

  // Getters
  int? get menuVersion => _menuVersion;
  int? get inventoryVersion => _inventoryVersion;
  Map<String, dynamic>? get menuData => _menuData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasData => _menuData != null;

  /// Start polling for menu updates
  /// بدء polling لتحديثات المنيو
  void startPolling(String businessId) {
    
    pollingManager.startMenuPolling(
      businessId: businessId,
      currentMenuVersion: _menuVersion,
      currentInventoryVersion: _inventoryVersion,
      onUpdate: (result) async {
        debugPrint('📱 Menu update received in provider');
        
        if (result.menuNeedsUpdate || result.inventoryNeedsUpdate) {
          // Fetch fresh data
          await fetchFreshMenu(businessId);
          
          // Show notification to user (optional)
          _showUpdateNotification(result);
        }
      },
      customInterval: 30, // Poll every 30 seconds
    );
  }

  /// Stop polling
  /// إيقاف polling
  void stopPolling() {
    pollingManager.stopMenuPolling();
  }

  /// Fetch fresh menu data
  /// جلب بيانات المنيو الجديدة
  Future<void> fetchFreshMenu(String businessId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // TODO: Replace with your actual menu fetch logic
      // final menuData = await yourMenuService.getMenu(businessId);
      
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      // Update data and versions
      _menuData = {
        'businessId': businessId,
        'items': [],
        'lastFetched': DateTime.now().toIso8601String(),
      };
      
      // Update versions (these would come from the API response)
      _menuVersion = DateTime.now().millisecondsSinceEpoch;
      _inventoryVersion = DateTime.now().millisecondsSinceEpoch;
      
      debugPrint('✅ Menu data refreshed');
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      debugPrint('❌ Error fetching menu: $e');
      notifyListeners();
    }
  }

  /// Show update notification
  /// عرض إشعار بالتحديث
  void _showUpdateNotification(MenuVersionCheckResult result) {
    String message = '';
    
    if (result.menuNeedsUpdate && result.inventoryNeedsUpdate) {
      message = 'تم تحديث المنيو والمخزون';
    } else if (result.menuNeedsUpdate) {
      message = 'تم تحديث المنيو';
    } else if (result.inventoryNeedsUpdate) {
      message = 'تم تحديث المخزون';
    }
    
    if (message.isNotEmpty) {
      debugPrint('🔔 $message for ${result.businessName ?? result.businessId}');
      // TODO: Show snackbar or notification to user
    }
  }

  /// Check version without polling
  /// فحص النسخة بدون polling
  Future<bool> checkForUpdates(String businessId) async {
    try {
      final service = VersionCheckService();
      final result = await service.checkMenuVersion(
        businessId: businessId,
        clientMenuVersion: _menuVersion,
        clientInventoryVersion: _inventoryVersion,
      );
      
      if (result.needsUpdate) {
        await fetchFreshMenu(businessId);
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Error checking for updates: $e');
      return false;
    }
  }

  @override
  void dispose() {
    stopPolling();
    disposePolling();
    super.dispose();
  }
}

/// Provider for restaurant listings with versioning
/// Provider لقوائم المطاعم مع versioning
class RestaurantListProviderWithVersioning with ChangeNotifier, PollingMixin {
  // Version tracking
  int? _listingVersion;
  
  // Data
  List<dynamic>? _restaurants;
  bool _isLoading = false;
  String? _error;

  // Getters
  int? get listingVersion => _listingVersion;
  List<dynamic>? get restaurants => _restaurants;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasData => _restaurants != null;
  int get restaurantCount => _restaurants?.length ?? 0;

  /// Start polling for listing updates
  /// بدء polling لتحديثات القائمة
  void startPolling(String regionId) {
    
    pollingManager.startListingPolling(
      regionId: regionId,
      currentListingVersion: _listingVersion,
      onUpdate: (result) async {
        debugPrint('📱 Listing update received: ${result.totalBusinesses} restaurants');
        
        if (result.needsUpdate) {
          // Fetch fresh data
          await fetchRestaurants(regionId);
          
          // Show notification
          _showUpdateNotification(result);
        }
      },
      customInterval: 60, // Poll every 60 seconds
    );
  }

  /// Stop polling
  /// إيقاف polling
  void stopPolling() {
    pollingManager.stopListingPolling();
  }

  /// Fetch fresh restaurant list
  /// جلب قائمة المطاعم الجديدة
  Future<void> fetchRestaurants(String regionId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('🔄 RestaurantListProvider: fetching restaurants for region $regionId');
      
      // Get active address to pass to service
      final deliveryManager = DeliveryAddressManager.instance;
      final activeAddress = await deliveryManager.getActiveAddress();
      
      debugPrint('📍 RestaurantListProvider: activeAddress=$activeAddress');
      debugPrint('📍 RestaurantListProvider: activeAddress.regionId=${activeAddress?.regionId}');
      debugPrint('📍 RestaurantListProvider: requested regionId=$regionId');
      
      // ⚠️ إذا لم يكن هناك عنوان نشط، لا نستطيع الجلب
      if (activeAddress == null) {
        debugPrint('⚠️ RestaurantListProvider: No active address');
        _restaurants = [];
        _listingVersion = DateTime.now().millisecondsSinceEpoch;
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      // ✅ إذا كان regionId مختلف، نقوم بجلب المطاعم للمنطقة المطلوبة مباشرة
      // (هذا يحدث عندما يكتشف polling تحديث لمنطقة مختلفة)
      if (activeAddress.regionId != regionId) {
        debugPrint('⚠️ RestaurantListProvider: Region mismatch - fetching anyway');
        debugPrint('   activeAddress.regionId=${activeAddress.regionId} != requested=$regionId');
        debugPrint('   سيتم جلب المطاعم للمنطقة المطلوبة مباشرة');
        // لا نعود - نكمل لجلب المطاعم
      }
      
      debugPrint('✅ RestaurantListProvider: calling RestaurantFetchingService...');
      
      // Fetch from actual service using regionId directly
      // (polling may request a different region than the active address)
      final response = await RestaurantFetchingService.instance.fetchRestaurantsByRegion(
        regionId: regionId,
        page: 0,
        limit: 20,
      );
      
      debugPrint('📦 RestaurantListProvider: received ${response.businesses.length} raw businesses');
      // 🧪 DIAG: Extract raw IDs before any sanitization to detect backend vs UI divergence
      final List<String> rawIds = response.businesses.map((item) {
        if (item is Map<String, dynamic>) {
          return (item['businessId'] ?? item['business_id'] ?? item['id'] ?? '').toString();
        }
        return 'NON_MAP';
      }).cast<String>().toList();
      debugPrint('🧪 DIAG RAW IDS (${rawIds.length}): $rawIds');

      // Sanitize incoming list to ensure only Map<String,dynamic> entries are stored
      final List<dynamic> raw = response.businesses;
      final List<Map<String, dynamic>> sanitized = [];
      int invalidCount = 0;
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          sanitized.add(item);
        } else if (item is String) {
          invalidCount++;
          debugPrint('⚠️ RestaurantListProvider: ignoring unexpected String entry="$item"');
        } else {
          invalidCount++;
          debugPrint('⚠️ RestaurantListProvider: ignoring unexpected entry type=${item.runtimeType}');
        }
      }
      _restaurants = sanitized;
      if (invalidCount > 0) {
        debugPrint('🧹 RestaurantListProvider: removed $invalidCount invalid entries; kept ${_restaurants!.length} valid maps');
      }

      // 🧪 DIAG: Stored (sanitized) IDs list
      final List<String> storedIds = _restaurants!.map((m) => (m['businessId'] ?? m['business_id'] ?? m['id'] ?? '').toString()).toList();
      debugPrint('🧪 DIAG STORED IDS (${storedIds.length}): $storedIds');

      debugPrint('🏪 RestaurantListProvider: stored ${_restaurants!.length} items (sanitized maps)');
      
      // Update data and version
      _listingVersion = DateTime.now().millisecondsSinceEpoch;
      
      debugPrint('✅ Restaurant list refreshed: ${_restaurants!.length} items');
      _isLoading = false;
      
      debugPrint('🔔🔔🔔 Provider calling notifyListeners() - hashCode: ${this.hashCode}');
      debugPrint('   Region: $regionId');
      debugPrint('   Restaurants count: ${_restaurants!.length}');
      debugPrint('   Timestamp: ${DateTime.now().millisecondsSinceEpoch}');
      
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      debugPrint('❌ Error fetching restaurants: $e');
      notifyListeners();
    }
  }

  /// Show update notification
  /// عرض إشعار بالتحديث
  void _showUpdateNotification(ListingVersionCheckResult result) {
    final newCount = result.totalBusinesses;
    final available = result.availableBusinesses;
    
    debugPrint('🔔 تحديث القائمة: $newCount مطعم ($available متاح)');
    // TODO: Show snackbar or notification to user
  }

  @override
  void dispose() {
    stopPolling();
    disposePolling();
    super.dispose();
  }
}

/// Provider for batch checking multiple items
/// Provider للفحص الدفعي لعدة عناصر
class BatchVersionProviderWithVersioning with ChangeNotifier, PollingMixin {
  final VersionCheckService _service = VersionCheckService();
  
  Map<String, int?> _businessMenuVersions = {};
  Map<String, int?> _businessInventoryVersions = {};
  Map<String, int?> _regionListingVersions = {};
  
  bool _isChecking = false;
  String? _error;

  bool get isChecking => _isChecking;
  String? get error => _error;

  /// Start batch polling for multiple items
  /// بدء polling دفعي لعدة عناصر
  void startBatchPolling({
    required List<String> businessIds,
    required List<String> regionIds,
  }) {
    final businesses = businessIds.map((id) => BusinessVersionInfo(
      businessId: id,
      menuVersion: _businessMenuVersions[id],
      inventoryVersion: _businessInventoryVersions[id],
    )).toList();
    
    final regions = regionIds.map((id) => RegionVersionInfo(
      regionId: id,
      listingVersion: _regionListingVersions[id],
    )).toList();
    
    pollingManager.startBatchPolling(
      businesses: businesses,
      regions: regions,
      onUpdate: (result) {
        debugPrint('📱 Batch update: ${result.summary.needsUpdate}/${result.summary.totalChecked} items need refresh');
        
        // Update versions
        for (var business in result.businesses) {
          if (business.needsUpdate) {
            _businessMenuVersions[business.businessId] = business.menuVersion;
            _businessInventoryVersions[business.businessId] = business.inventoryVersion;
            debugPrint('   📍 ${business.businessName ?? business.businessId} updated');
          }
        }
        
        for (var region in result.regions) {
          if (region.needsUpdate) {
            _regionListingVersions[region.regionId] = region.listingVersion;
            debugPrint('   📍 ${region.regionNameAr ?? region.regionId} updated');
          }
        }
        
        notifyListeners();
      },
      customInterval: 45, // Poll every 45 seconds
    );
  }

  /// Stop batch polling
  /// إيقاف polling الدفعي
  void stopBatchPolling() {
    pollingManager.stopBatchPolling();
  }

  /// Check once without polling
  /// فحص مرة واحدة بدون polling
  Future<void> checkOnce({
    required List<String> businessIds,
    required List<String> regionIds,
  }) async {
    _isChecking = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.batchCheckVersions(
        businesses: businessIds.map((id) => BusinessVersionInfo(
          businessId: id,
          menuVersion: _businessMenuVersions[id],
          inventoryVersion: _businessInventoryVersions[id],
        )).toList(),
        regions: regionIds.map((id) => RegionVersionInfo(
          regionId: id,
          listingVersion: _regionListingVersions[id],
        )).toList(),
      );
      
      debugPrint('✅ Batch check complete: ${result.summary.needsUpdate} items need updates');
      _isChecking = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isChecking = false;
      debugPrint('❌ Error in batch check: $e');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopBatchPolling();
    disposePolling();
    super.dispose();
  }
}
