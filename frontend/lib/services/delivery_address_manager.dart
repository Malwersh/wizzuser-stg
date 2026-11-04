import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'address_book_api_319.dart';
import 'session_service.dart';
import '../models/address_model.dart';

import '../models/delivery_address.dart';
import '../models/location_mismatch_info.dart';
import 'region_resolver_service.dart';

/// Service to manage the active delivery address - the single source of truth
/// خدمة إدارة عنوان التوصيل الفعّال - المصدر الوحيد للحقيقة
class DeliveryAddressManager {
  // Singleton pattern
  DeliveryAddressManager._();
  static final DeliveryAddressManager instance = DeliveryAddressManager._();

  // Constants
  String get _scope => SessionService.instance.currentUserId ?? 'guest';
  String get _cacheKey => 'delivery_address_319_$_scope';
  String get _lastUsedKey => 'last_used_address_319_$_scope';
  String? _activeOwner;
  static const double _mismatchThresholdKm = 5.0;

  // State
  DeliveryAddress? _activeAddress;
  final _addressController = StreamController<DeliveryAddress?>.broadcast();
  Timer? _mismatchCheckTimer;
  bool _isInitialized = false;

  /// Stream of active delivery address changes
  /// استماع للتغييرات على عنوان التوصيل الفعّال
  Stream<DeliveryAddress?> get addressStream => _addressController.stream;

  /// Get current active delivery address
  /// الحصول على عنوان التوصيل الفعّال الحالي
  DeliveryAddress? get activeAddress =>
      _activeOwner == _scope ? _activeAddress : null;

  /// Check if manager is initialized
  /// التحقق من تهيئة المدير
  bool get isInitialized => _isInitialized;

  /// Initialize delivery address based on user type
  /// تهيئة عنوان التوصيل بناءً على نوع المستخدم
  ///
  /// 🆕 الأولوية الجديدة:
  /// 1️⃣ GPS (الطبقة الأولى - للجميع)
  /// 2️⃣ العناوين المحفوظة (للمسجلين فقط)
  /// 3️⃣ Fallback (جلب الكل)
  Future<DeliveryAddress?> initializeDeliveryAddress({
    String? userId,
    bool isRegisteredUser = false,
  }) async {
    final scope = _scope;
    if (_activeOwner != scope) {
      _activeAddress = null;
      _activeOwner = scope;
    }
    try {
      var address = _activeAddress;
      if (address == null && isRegisteredUser && userId == scope) {
        address = await _initializeForRegisteredUser(userId!);
      } else if (address == null && !isRegisteredUser) {
        address = await _loadFromCache();
      }
      if (address == null || address.isExpired) return null;
      address = await _validatedAddress(address);
      if (_scope != scope) return null;
      _activeAddress = address;
      _isInitialized = true;
      _addressController.add(address);
      _startLocationMismatchDetection();
      return address;
    } catch (_) {
      return null;
    }
  }

  /// Initialize for registered user (Saved addresses only - no GPS here)
  /// تهيئة لمستخدم مسجل (العناوين المحفوظة فقط - GPS تم في الطبقة 1)
  Future<DeliveryAddress?> _initializeForRegisteredUser(String userId) async {
    final scope = _scope;
    final prefs = await SharedPreferences.getInstance();
    if (_scope != scope || userId != scope) return null;
    final last = prefs.getString(_lastUsedKey);
    final rows = await _savedBook(userId);
    if (_scope != scope) return null;
    for (final row in rows) {
      if (row.id == last) return DeliveryAddress.fromSavedAddress(row);
    }
    for (final row in rows) {
      if (row.isDefault) return DeliveryAddress.fromSavedAddress(row);
    }
    return null;
  }

  // 🗑️ تم حذف _initializeForGuestUser - GPS الآن في الطبقة 1 للجميع

  /// Get GPS address
  /// الحصول على عنوان من GPS
  /// Check GPS permission
  /// التحقق من إذن GPS
  Future<bool> _checkGPSPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('   ❌ تم رفض إذن GPS');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('   ❌ إذن GPS مرفوض نهائياً');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('   ❌ خطأ في التحقق من إذن GPS: $e');
      return false;
    }
  }

  /// Find region by coordinates using backend API
  /// إيجاد المنطقة من الإحداثيات باستخدام API الخلفية
  Future<Map<String, dynamic>> _findRegionByCoordinates(
    double latitude,
    double longitude,
  ) async {
    final result = await RegionResolverService().resolvePoint(
      lat: latitude,
      lng: longitude,
      throwOnFailure: true,
    );
    if (result == null || !result.effective.isDeliveryAvailable)
      throw Exception('الخدمة غير متاحة في هذا الموقع.');
    return {
      'region_id': result.region.id,
      'region_name_ar': result.region.nameAr,
      'region_name_en': result.region.name,
      'city': result.region.nameAr,
    };
  }

  Future<DeliveryAddress> _validatedAddress(DeliveryAddress address) async {
    final r = await _findRegionByCoordinates(
      address.latitude,
      address.longitude,
    );
    return address.copyWith(
      regionId: r['region_id'],
      regionNameAr: r['region_name_ar'],
      regionNameEn: r['region_name_en'],
    );
  }

  /// Fetch address from API by ID
  /// جلب عنوان من API بواسطة المعرّف
  Future<List<DetailedAddress>> _savedBook(String userId) async {
    final session = SessionService.instance;
    if (session.currentUserId != userId || !session.isLoggedIn) return [];
    final token = await session.getToken();
    if (token == null || session.currentUserId != userId) return [];
    final response = await AddressBookApi319.instance.request(
      method: 'GET',
      owner: userId,
      token: token,
    );
    if (session.currentUserId != userId || response['success'] != true)
      return [];
    dynamic data = response['data'];
    if (data is Map && data['data'] is Map) data = data['data'];
    if (data is! Map || data['addresses'] is! List) return [];
    return (data['addresses'] as List)
        .map((a) => DetailedAddress.fromJson(Map<String, dynamic>.from(a)))
        .where((a) => a.userId == userId)
        .toList();
  }

  /// Set delivery address
  /// تعيين عنوان التوصيل
  Future<void> setDeliveryAddress(DeliveryAddress address) async {
    debugPrint('🔄 تغيير عنوان التوصيل...');
    debugPrint('   الجديد: ${address.displayName}');
    debugPrint('   القديم: ${_activeAddress?.displayName ?? "لا يوجد"}');
    debugPrint('   🗺️ Region ID الجديد: ${address.regionId}');
    debugPrint('   🗺️ Region ID القديم: ${_activeAddress?.regionId}');

    final scope = _scope;
    address = await _validatedAddress(address);
    if (_scope != scope) throw StateError('Session changed');
    _activeOwner = scope;
    final oldAddress = _activeAddress;
    _activeAddress = address;

    // Save to cache if guest address
    if (address.isGuestAddress) {
      await _saveToCache(address);
      debugPrint('   💾 تم حفظ عنوان الضيف في Cache');
    }

    // Save last used address ID if registered
    if (address.isRegisteredAddress && address.addressId != null) {
      final key = _lastUsedKey;
      final prefs = await SharedPreferences.getInstance();
      if (_scope != scope) return;
      await prefs.setString(key, address.addressId!);
      debugPrint('   💾 تم حفظ addressId للمستخدم المسجل');
    }

    // Emit change - Always emit even if same region to trigger reload
    debugPrint('   📡 إرسال event عبر addressStream...');
    debugPrint('   📡 hasListener: ${_addressController.hasListener}');
    debugPrint('   📡 isClosed: ${_addressController.isClosed}');

    // Force emit by creating a microtask to ensure listeners receive the event
    // This is important when changing address within the same region
    _addressController.add(_activeAddress);

    // Force a second emit with a slight delay to ensure listeners catch it
    // This handles the case where the stream might deduplicate same-object emissions
    Future.microtask(() {
      if (!_addressController.isClosed) {
        debugPrint('   📡 Force re-emit to ensure delivery');
        _addressController.add(_activeAddress);
      }
    });

    debugPrint('   ✅ تم إرسال event بنجاح');

    // Check if region changed
    if (oldAddress != null && oldAddress.regionId != address.regionId) {
      debugPrint(
        '   ⚠️ تغيرت المنطقة: ${oldAddress.regionId} → ${address.regionId}',
      );
      // This event can be used to trigger cart validation
    } else if (oldAddress == null) {
      debugPrint('   🆕 أول عنوان يتم تعيينه (لا يوجد عنوان سابق)');
    } else {
      debugPrint('   🔁 نفس المنطقة: ${address.regionId}');
    }

    debugPrint('✅ تم تحديث عنوان التوصيل');
  }

  /// Set active address (alias for setDeliveryAddress)
  /// تعيين العنوان النشط
  Future<void> setActiveAddress(DeliveryAddress address) async {
    await setDeliveryAddress(address);
  }

  /// Get active address
  /// الحصول على العنوان النشط
  Future<DeliveryAddress?> getActiveAddress() async {
    return activeAddress;
  }

  /// Check if has active address
  /// فحص وجود عنوان نشط
  ///
  /// يُستخدم في splash_screen و login_screen لتحديد المسار المناسب
  Future<bool> hasActiveAddress() async {
    return activeAddress != null;
  }

  /// Load from cache
  /// التحميل من الذاكرة المؤقتة
  Future<DeliveryAddress?> _loadFromCache() async {
    try {
      final scope = _scope, key = _cacheKey;
      final prefs = await SharedPreferences.getInstance();
      if (_scope != scope) return null;
      final cachedJson = prefs.getString(key);

      if (cachedJson != null) {
        final data = jsonDecode(cachedJson) as Map<String, dynamic>;
        return DeliveryAddress.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('   ⚠️ خطأ في قراءة الذاكرة المؤقتة: $e');
      return null;
    }
  }

  /// Save to cache
  /// الحفظ في الذاكرة المؤقتة
  Future<void> _saveToCache(DeliveryAddress address) async {
    try {
      final scope = _scope, key = _cacheKey;
      final prefs = await SharedPreferences.getInstance();
      if (_scope != scope) return;
      final json = jsonEncode(address.toJson());
      await prefs.setString(key, json);
      debugPrint('   💾 تم حفظ العنوان في الذاكرة المؤقتة');
    } catch (e) {
      debugPrint('   ⚠️ خطأ في حفظ الذاكرة المؤقتة: $e');
    }
  }

  /// Clear cache
  /// مسح الذاكرة المؤقتة
  void clearActiveSelection() {
    _activeAddress = null;
    _mismatchCheckTimer?.cancel();
    _isInitialized = true;
    if (!_addressController.isClosed) _addressController.add(null);
  }

  Future<void> clearCache() async {
    try {
      final cache = _cacheKey, last = _lastUsedKey;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cache);
      await prefs.remove(last);
      debugPrint('   🗑️ تم مسح الذاكرة المؤقتة');
    } catch (e) {
      debugPrint('   ⚠️ خطأ في مسح الذاكرة المؤقتة: $e');
    }
  }

  /// Start location mismatch detection (periodic GPS check)
  /// بدء كشف عدم تطابق الموقع (فحص دوري لـ GPS)
  void _startLocationMismatchDetection() {
    // Cancel existing timer
    _mismatchCheckTimer?.cancel();

    // Check every 5 minutes
    _mismatchCheckTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _checkLocationMismatch(),
    );
  }

  /// Check for location mismatch
  /// التحقق من عدم تطابق الموقع
  Future<LocationMismatchInfo?> _checkLocationMismatch() async {
    if (activeAddress == null) return null;

    try {
      // Get current GPS location
      final permission = await _checkGPSPermission();
      if (!permission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      // Calculate distance
      final distance = LocationMismatchInfo.calculateDistance(
        lat1: position.latitude,
        lon1: position.longitude,
        lat2: _activeAddress!.latitude,
        lon2: _activeAddress!.longitude,
      );

      // Check if mismatch
      if (distance > _mismatchThresholdKm) {
        debugPrint(
          '⚠️ اكتشاف عدم تطابق الموقع: ${distance.toStringAsFixed(1)} km',
        );

        // Get current city from API
        final regionInfo = await _findRegionByCoordinates(
          position.latitude,
          position.longitude,
        );

        final mismatchInfo = LocationMismatchInfo(
          currentLatitude: position.latitude,
          currentLongitude: position.longitude,
          currentCity: regionInfo['city'] ?? 'غير محدد',
          currentRegionId: regionInfo['region_id'],
          selectedAddressCity: _activeAddress!.city,
          selectedRegionId: _activeAddress!.regionId,
          distance: distance,
        );

        // You can emit this to a stream or show a dialog
        debugPrint('   ${mismatchInfo.getMessage()}');
        return mismatchInfo;
      }

      return null;
    } catch (e) {
      debugPrint('   ⚠️ خطأ في فحص الموقع: $e');
      return null;
    }
  }

  /// Stop location mismatch detection
  /// إيقاف كشف عدم تطابق الموقع
  void stopLocationMismatchDetection() {
    _mismatchCheckTimer?.cancel();
    _mismatchCheckTimer = null;
    debugPrint('   🛑 تم إيقاف كشف عدم تطابق الموقع');
  }

  /// Dispose resources
  /// تحرير الموارد
  void dispose() {
    _addressController.close();
    _mismatchCheckTimer?.cancel();
    debugPrint('   🗑️ تم تحرير موارد DeliveryAddressManager');
  }
}
