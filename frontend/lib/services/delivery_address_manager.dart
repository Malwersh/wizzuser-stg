import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../models/delivery_address.dart';
import '../models/location_mismatch_info.dart';
import '../config.dart';

/// Service to manage the active delivery address - the single source of truth
/// خدمة إدارة عنوان التوصيل الفعّال - المصدر الوحيد للحقيقة
class DeliveryAddressManager {
  // Singleton pattern
  DeliveryAddressManager._();
  static final DeliveryAddressManager instance = DeliveryAddressManager._();

  // Constants
  static const String _cacheKey = 'delivery_address_cache';
  static const String _lastUsedKey = 'last_used_address_id';
  static const int _cacheExpiryDays = 7;
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
  DeliveryAddress? get activeAddress => _activeAddress;

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
    debugPrint('🚀 تهيئة عنوان التوصيل...');
    debugPrint('   نوع المستخدم: ${isRegisteredUser ? "مسجل" : "ضيف"}');

    try {
      // 🆕 الطبقة 0: إذا تم تعيين عنوان نشط مسبقاً (مثلاً العنوان الافتراضي من شاشة البداية)
      // لا نعيد التهيئة ولا نسمح لـ GPS بأن يطغى عليه
      if (_activeAddress != null) {
        debugPrint('✅ يوجد عنوان نشط بالفعل - تخطي إعادة التهيئة: ${_activeAddress!.displayName}');
        debugPrint('   regionId: ${_activeAddress!.regionId ?? "غير محددة"}');
        _isInitialized = true;
        // إعادة البث لضمان وصول العنوان للمستمعين الجدد (مثل الشاشة الرئيسية)
        _addressController.add(_activeAddress);
        return _activeAddress;
      }

      // 🆕 الطبقة 1: محاولة GPS أولاً (للجميع)
      debugPrint('📍 الطبقة 1: محاولة الحصول على موقع GPS...');
      _activeAddress = await _getGPSAddress();

      if (_activeAddress != null) {
        debugPrint('✅ تم الحصول على الموقع من GPS');
        debugPrint(
          '   الإحداثيات: ${_activeAddress!.latitude}, ${_activeAddress!.longitude}',
        );
        debugPrint('   المنطقة: ${_activeAddress!.regionId ?? "غير محددة"}');

        // حفظ في Cache للضيوف
        if (!isRegisteredUser) {
          await _saveToCache(_activeAddress!);
        }

        _addressController.add(_activeAddress);
        _isInitialized = true;
        _startLocationMismatchDetection();
        return _activeAddress;
      }

      debugPrint('⚠️ فشل الحصول على GPS - الانتقال للطبقة 2');

      // 🆕 الطبقة 2: استخدام العناوين المحفوظة (للمسجلين فقط)
      if (isRegisteredUser && userId != null) {
        debugPrint('📋 الطبقة 2: جلب العناوين المحفوظة...');
        _activeAddress = await _initializeForRegisteredUser(userId);

        if (_activeAddress != null) {
          debugPrint(
            '✅ تم استخدام عنوان محفوظ: ${_activeAddress!.displayName}',
          );
          _addressController.add(_activeAddress);
          _isInitialized = true;
          _startLocationMismatchDetection();
          return _activeAddress;
        }
      } else {
        // للضيوف: محاولة Cache
        debugPrint('💾 الطبقة 2: محاولة Cache للضيف...');
        _activeAddress = await _loadFromCache();

        if (_activeAddress != null && !_activeAddress!.isExpired) {
          debugPrint('✅ تم استخدام عنوان من Cache');
          _addressController.add(_activeAddress);
          _isInitialized = true;
          return _activeAddress;
        }
      }

      debugPrint('⚠️ لم يتم تحديد عنوان توصيل - سيتم جلب جميع المطاعم');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة عنوان التوصيل: $e');
      return null;
    }
  }

  /// Initialize for registered user (Saved addresses only - no GPS here)
  /// تهيئة لمستخدم مسجل (العناوين المحفوظة فقط - GPS تم في الطبقة 1)
  Future<DeliveryAddress?> _initializeForRegisteredUser(String userId) async {
    debugPrint('   📋 جلب العناوين المحفوظة للمستخدم...');

    try {
      // Try to load last used address
      final prefs = await SharedPreferences.getInstance();
      final lastUsedAddressId = prefs.getString(_lastUsedKey);

      if (lastUsedAddressId != null) {
        debugPrint('   📍 محاولة جلب آخر عنوان مستخدم: $lastUsedAddressId');
        final address = await _fetchAddressFromAPI(lastUsedAddressId);
        if (address != null) {
          return address;
        }
      }

      // Load default address
      debugPrint('   🏠 جلب العنوان الافتراضي...');
      final defaultAddress = await _fetchDefaultAddress(userId);
      if (defaultAddress != null) {
        return defaultAddress;
      }

      debugPrint('   ⚠️ لا توجد عناوين محفوظة');
      return null;
    } catch (e) {
      debugPrint('   ❌ خطأ في جلب العناوين: $e');
      return null;
    }
  }

  // 🗑️ تم حذف _initializeForGuestUser - GPS الآن في الطبقة 1 للجميع

  /// Get GPS address
  /// الحصول على عنوان من GPS
  Future<DeliveryAddress?> _getGPSAddress() async {
    try {
      // Check GPS permission
      final permission = await _checkGPSPermission();
      if (!permission) {
        debugPrint('   ❌ لا يوجد إذن GPS');
        return null;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      debugPrint(
        '   📍 الإحداثيات: ${position.latitude}, ${position.longitude}',
      );

      // Get region info from backend API
      final regionInfo = await _findRegionByCoordinates(
        position.latitude,
        position.longitude,
      );

      // Create address
      final address = DeliveryAddress(
        formattedAddress: regionInfo['formattedAddress'] ?? 'الموقع الحالي',
        latitude: position.latitude,
        longitude: position.longitude,
        regionId: regionInfo['region_id'],
        regionNameAr: regionInfo['region_name_ar'],
        regionNameEn: regionInfo['region_name_en'],
        neighborhood: regionInfo['neighborhood'],
        city: regionInfo['city'] ?? 'غير محدد',
        source: AddressSource.gps,
        timestamp: DateTime.now(),
        expiryTimestamp: DateTime.now().add(Duration(days: _cacheExpiryDays)),
      );

      return address;
    } catch (e) {
      debugPrint('   ❌ خطأ في الحصول على GPS: $e');
      return null;
    }
  }

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
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/regions/find-by-coordinates'
        '?latitude=$latitude&longitude=$longitude',
      );

      final response = await http.get(url).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'] as Map<String, dynamic>;
        }
      }

      // Fallback if API fails
      return {'city': 'غير محدد', 'formattedAddress': 'الموقع الحالي'};
    } catch (e) {
      debugPrint('   ⚠️ خطأ في API إيجاد المنطقة: $e');
      return {'city': 'غير محدد', 'formattedAddress': 'الموقع الحالي'};
    }
  }

  /// Fetch address from API by ID
  /// جلب عنوان من API بواسطة المعرّف
  Future<DeliveryAddress?> _fetchAddressFromAPI(String addressId) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/addresses/$addressId');
      final response = await http.get(url).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return DeliveryAddress.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('   ⚠️ خطأ في جلب العنوان: $e');
      return null;
    }
  }

  /// Fetch default address for user
  /// جلب العنوان الافتراضي للمستخدم
  Future<DeliveryAddress?> _fetchDefaultAddress(String userId) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/addresses?userId=$userId&default=true',
      );
      final response = await http.get(url).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['addresses'] != null) {
          final addresses = data['addresses'] as List;
          if (addresses.isNotEmpty) {
            return DeliveryAddress.fromJson(addresses[0]);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('   ⚠️ خطأ في جلب العنوان الافتراضي: $e');
      return null;
    }
  }

  /// Set delivery address
  /// تعيين عنوان التوصيل
  Future<void> setDeliveryAddress(DeliveryAddress address) async {
    debugPrint('🔄 تغيير عنوان التوصيل...');
    debugPrint('   الجديد: ${address.displayName}');
    debugPrint('   القديم: ${_activeAddress?.displayName ?? "لا يوجد"}');
    debugPrint('   🗺️ Region ID الجديد: ${address.regionId}');
    debugPrint('   🗺️ Region ID القديم: ${_activeAddress?.regionId}');

    final oldAddress = _activeAddress;
    _activeAddress = address;

    // Save to cache if guest address
    if (address.isGuestAddress) {
      await _saveToCache(address);
      debugPrint('   💾 تم حفظ عنوان الضيف في Cache');
    }

    // Save last used address ID if registered
    if (address.isRegisteredAddress && address.addressId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastUsedKey, address.addressId!);
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
    return _activeAddress;
  }

  /// Check if has active address
  /// فحص وجود عنوان نشط
  ///
  /// يُستخدم في splash_screen و login_screen لتحديد المسار المناسب
  Future<bool> hasActiveAddress() async {
    return _activeAddress != null;
  }

  /// Load from cache
  /// التحميل من الذاكرة المؤقتة
  Future<DeliveryAddress?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);

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
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(address.toJson());
      await prefs.setString(_cacheKey, json);
      debugPrint('   💾 تم حفظ العنوان في الذاكرة المؤقتة');
    } catch (e) {
      debugPrint('   ⚠️ خطأ في حفظ الذاكرة المؤقتة: $e');
    }
  }

  /// Clear cache
  /// مسح الذاكرة المؤقتة
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_lastUsedKey);
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
    if (_activeAddress == null) return null;

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
