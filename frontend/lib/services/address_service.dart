// lib/services/address_service.dart - Dynamic Version

import 'package:flutter/material.dart';
import '../models/address_model.dart';
import 'package:foodapp_user/services/api_service.dart';
import "session_service.dart";
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class EnhancedAddressService extends ChangeNotifier {
  // Local models for compatibility
  List<AddressModel> _addresses = [];
  AddressModel? _currentAddress;
  AddressModel? _selectedAddress;
  
  // API-based models
  List<DetailedAddress> _detailedAddresses = [];
  DetailedAddress? _currentLocationAddress;
  
  bool _isLoadingLocation = false;
  bool _isLoading = false;
  String? _locationError;
  String? _error;
  bool _disposed = false;

  // Getters for compatibility
  List<AddressModel> get addresses => _addresses;  
  List<DetailedAddress> get detailedAddresses => _detailedAddresses;
  AddressModel? get currentAddress => _currentAddress;
  AddressModel? get selectedAddress => _selectedAddress ?? _currentAddress;
  DetailedAddress? get currentLocationAddress => _currentLocationAddress;
  bool get isLoadingLocation => _isLoadingLocation;
  bool get isLoading => _isLoading;
  String? get locationError => _locationError;
  String? get error => _error;
  
  // Additional getters for UI compatibility
  DetailedAddress? get defaultAddress {
    try {
      // البحث عن عنوان افتراضي محدد
      final defaultAddr = _detailedAddresses.where((addr) => addr.isDefault).isNotEmpty 
          ? _detailedAddresses.where((addr) => addr.isDefault).first 
          : null;
      
      // إذا لم يوجد عنوان افتراضي، استخدم أول عنوان متاح
      if (defaultAddr == null && _detailedAddresses.isNotEmpty) {
        print('⚠️ لا يوجد عنوان افتراضي - استخدام أول عنوان');
        return _detailedAddresses.first;
      }
      
      return defaultAddr;
    } catch (e) {
      // في حالة الخطأ، حاول إرجاع أول عنوان
      return _detailedAddresses.isNotEmpty ? _detailedAddresses.first : null;
    }
  }
  
  bool get hasAddresses => _detailedAddresses.isNotEmpty;
  
  int get addressCount => _detailedAddresses.length;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyIfNotDisposed() {
    if (!_disposed) {
      // Defer notification to avoid calling during build phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          notifyListeners();
        }
      });
    }
  }

  // Initialize service
  Future<void> initialize() async {
    print('🔧 تهيئة خدمة العناوين...');
    await loadAddressesFromAPI();
  }

  // Load addresses from API - Dynamic only
  Future<void> loadAddressesFromAPI() async {
    await fetchAddresses();
  }

  /// Fetch addresses from API
  Future<void> fetchAddresses() async {
    if (_disposed) return;
    
    _isLoading = true;
    _error = null;
    _notifyIfNotDisposed();
    
    try {
      print('🏠 بدء جلب العناوين المحفوظة من API...');
      
      // 🔧 تشخيص شامل لحالة الجلسة
      final sessionService = SessionService.instance;
      print('🔍 تشخيص حالة الجلسة:');
      print('   - isLoggedIn: ${sessionService.isLoggedIn}');
      print('   - isGuest: ${sessionService.isGuest}');
      print('   - currentUserId: ${sessionService.currentUserId}');
      print('   - accessToken متوفر: ${sessionService.accessToken != null ? "نعم" : "لا"}');
      print('   - idToken متوفر: ${sessionService.idToken != null ? "نعم" : "لا"}');
      
      // التحقق من حالة تسجيل الدخول أولاً
      final isLoggedIn = sessionService.isLoggedIn;
      final isGuest = sessionService.isGuest;
      
      // إذا كان المستخدم ضيف، لا نحتاج لتحميل العناوين
      if (isGuest || !isLoggedIn) {
        print('👤 المستخدم ضيف أو غير مسجل - لا توجد عناوين');
        _detailedAddresses.clear();
        _addresses.clear();
        _error = null;
        _isLoading = false;
        _notifyIfNotDisposed();
        return;
      }
      
      // التحقق من وجود المصادقة
      String? token = SessionService.instance.accessToken;
      String? userId = SessionService.instance.currentUserId;

      if (token == null || token.isEmpty) {
        _error = 'لم يتم العثور على token المصادقة. يرجى إعادة تسجيل الدخول';
        print('❌ Token is empty');
        _isLoading = false;
        _notifyIfNotDisposed();
        return;
      }

      if (userId == null || userId.isEmpty) {
        _error = 'لم يتم العثور على معرف المستخدم. يرجى إعادة تسجيل الدخول';
        print('❌ User ID is empty');
        _isLoading = false;
        _notifyIfNotDisposed();
        return;
      }
      
      print('🔑 Access Token: ${token.substring(0, 20)}...');
      print('👤 User ID: $userId');

      
      // استدعاء API
      final result = await ApiService.getUserAddresses(token);
      
      print('📊 تفاصيل استجابة API: $result');
      
      if (result['success'] == true) {
        // فحص هيكل البيانات المُرجعة
        var addressesData = <dynamic>[];
        
        print('🔍 فحص هيكل البيانات المُستلمة...');
        print('📊 البيانات الأساسية: ${result['data']}');
        
        // التعامل مع هياكل البيانات المختلفة
        if (result['data'] != null) {
          var currentData = result['data'];
          
          // فحص ما إذا كانت البيانات ملفوفة مرتين (nested data structure)
          if (currentData is Map<String, dynamic> && currentData.containsKey('data')) {
            currentData = currentData['data'];
          }
          
          if (currentData is Map<String, dynamic>) {
            // هيكل بيانات من النوع: {addresses: [...], total: X}
            if (currentData['addresses'] != null && currentData['addresses'] is List) {
              addressesData = currentData['addresses'];
            } else {
              print('⚠️ لم يتم العثور على addresses في currentData');
              addressesData = [];
            }
          } else if (currentData is List) {
            // هيكل بيانات من النوع: [...]
            addressesData = currentData;
          }
        }
        
        
        if (addressesData.isNotEmpty) {
          try {
            _detailedAddresses = addressesData
                .map((data) => DetailedAddress.fromJson(data as Map<String, dynamic>))
                .toList();
            
            // تحديث العناوين المحلية للتوافق
            _addresses = _detailedAddresses
                .map((addr) => _convertDetailedToAddressModel(addr))
                .toList();
            
            print('📍 العناوين المحملة:');
            for (int i = 0; i < _detailedAddresses.length; i++) {
              final addr = _detailedAddresses[i];
              print('   ${i + 1}. ${addr.name} - ${addr.fullAddress}');
            }
            
            // تعيين العنوان الافتراضي
            await _setDefaultAddressLocally();
            
            // حفظ العناوين محلياً
            await _saveAddressesLocally();
            
            _error = null;
            
          } catch (e) {
            print('❌ خطأ في تحويل بيانات العناوين: $e');
            print('🔍 البيانات المُستلمة: $addressesData');
            _error = 'خطأ في معالجة بيانات العناوين: $e';
            _detailedAddresses.clear();
            _addresses.clear();
          }
        } else {
          print('⚠️ لا توجد عناوين مسجلة للمستخدم');
          _detailedAddresses.clear();
          _addresses.clear();
          _error = null; // ليس خطأ، فقط لا توجد عناوين
        }
      } else {
        final errorMessage = result['message'] ?? 'فشل في تحميل العناوين';
        _error = errorMessage;
        print('❌ فشل في تحميل العناوين: $errorMessage');
        print('📊 تفاصيل الاستجابة: $result');
        _detailedAddresses.clear();
        _addresses.clear();
      }
      
    } catch (e) {
      _error = 'خطأ في الاتصال بالخادم: $e';
      print('💥 خطأ في تحميل العناوين: $e');
      _detailedAddresses.clear();
      _addresses.clear();
    } finally {
      _isLoading = false;
      
      // إجبار تحديث الـ UI مع تأخير قصير لضمان انتشار التحديث
      _notifyIfNotDisposed();
      
      // تأخير إضافي لضمان وصول التحديث للـ UI
      await Future.delayed(const Duration(milliseconds: 100));
      _notifyIfNotDisposed();
      
    }
  }

  // Create new address - Dynamic
  Future<DetailedAddress?> createAddress(AddressCreateRequest address) async {
    try {
      print('📍 إنشاء عنوان جديد: ${address.name}');
      
      // التحقق من حالة تسجيل الدخول
      final isLoggedIn = SessionService.instance.isLoggedIn;
      if (!isLoggedIn) {
        _error = 'المستخدم غير مسجل دخول. يرجى تسجيل الدخول أولاً';
        print('❌ المستخدم غير مسجل دخول');
        _notifyIfNotDisposed();
        return null;
      }

      // الحصول على token وuser_id من الجلسة النشطة
      String? token = await SessionService.instance.getToken();
      String? userId = SessionService.instance.currentUserId;
      
      // التحقق من وجود البيانات المطلوبة
      if (token == null || userId == null) {
        _error = 'المستخدم غير مسجل دخول. يرجى تسجيل الدخول أولاً';
        print('❌ لا يوجد token أو user ID - المستخدم بحاجة لتسجيل الدخول');
        _notifyIfNotDisposed();
        return null;
      }
      
      print('🆔 User ID: $userId');
      
      if (token.isEmpty) {
        _error = 'لم يتم العثور على token المصادقة';
        print('❌ Token is empty');
        return null;
      }

      if (userId.isEmpty) {
        _error = 'لم يتم العثور على معرف المستخدم';
        print('❌ User ID is empty');
        return null;
      }

      print('📋 بيانات العنوان المرسلة: ${address.toJson()}');

      // 🔥 استدعاء API مع Region System Fields
      final result = await ApiService.addUserAddress(
        token: token,
        name: address.name,
        province: address.province,
        district: address.district,
        neighborhood: address.neighborhood,
        landmark: address.landmark,
        isDefault: address.isDefault,
        detailedAddress: address.detailedAddress,
        buildingNumber: address.buildingNumber,
        floorNumber: address.floorNumber,
        apartmentNumber: address.apartmentNumber,
        phoneNumber: address.phoneNumber,
        latitude: address.latitude,
        longitude: address.longitude,
        addressType: address.addressType,
        // 🆕 Region System Fields
        regionId: address.regionId,
        regionName: address.regionName,
        regionNameAr: address.regionNameAr,
        regionLevel: address.regionLevel,
        regionIsActive: address.regionIsActive,
        deliveryFee: address.deliveryFee,
        minimumOrder: address.minimumOrder,
        maxDistanceKm: address.maxDistanceKm,
        pricePerKm: address.pricePerKm,
      );

      // في الوقت الحالي، الـ Backend سيحفظ GPS ويمكننا إضافة Region fields لاحقاً
      if (address.regionId != null) {
        print('📍 Region Data متوفرة لكن لم يتم إرسالها بعد:');
        print('   - regionId: ${address.regionId}');
        print('   - regionName: ${address.regionNameAr}');
        print('   - deliveryFee: ${address.deliveryFee}');
      }
      
      if (result['success'] == true && result['data'] != null) {
        
        // إنشاء DetailedAddress من الاستجابة
        final newAddress = DetailedAddress.fromJson(result['data']);
        
        // إضافة العنوان للقائمة
        _detailedAddresses.add(newAddress);
        _addresses.add(_convertDetailedToAddressModel(newAddress));
        
        // إذا كان هذا العنوان الأول أو محدد كافتراضي، اجعله افتراضي
        if (_detailedAddresses.length == 1 || newAddress.isDefault) {
          await _setDefaultAddressLocally();
        }
        
        // حفظ محلياً
        await _saveAddressesLocally();
        
        _error = null;
        
        // ضمان التحديث الفوري للـ UI
        _notifyIfNotDisposed();
        
        // إضافة تأخير قصير لضمان انتشار التحديث
        await Future.delayed(const Duration(milliseconds: 100));
        _notifyIfNotDisposed();
        
        return newAddress;
        
      } else {
        final errorMessage = result['message'] ?? 'فشل في إنشاء العنوان';
        _error = errorMessage;
        print('❌ فشل في إنشاء العنوان: $errorMessage');
        _notifyIfNotDisposed();
        return null;
      }
      
    } catch (e) {
      _error = 'خطأ في إنشاء العنوان: $e';
      print('💥 خطأ في إنشاء العنوان: $e');
      _notifyIfNotDisposed();
      return null;
    }
  }

  // Set default address
  Future<bool> setDefaultAddress(String addressId) async {
    try {
      print('📍 تعيين العنوان الافتراضي: $addressId');
      
      // التحقق من حالة تسجيل الدخول
      final isLoggedIn = SessionService.instance.isLoggedIn;
      if (!isLoggedIn) {
        _error = 'المستخدم غير مسجل دخول. يرجى تسجيل الدخول أولاً';
        print('❌ المستخدم غير مسجل دخول');
        _notifyIfNotDisposed();
        return false;
      }

      // الحصول على token وuser_id من الجلسة النشطة
      String? token = SessionService.instance.accessToken;
      
      if (token == null) {
        _error = 'لم يتم العثور على token المصادقة';
        print('❌ Token is empty');
        return false;
      }

      // استدعاء API
      final result = await ApiService.setDefaultAddress(
        token: token,
        addressId: addressId,
      );
      
      if (result['success'] == true) {
        
        // تحديث العناوين محلياً
        for (int i = 0; i < _detailedAddresses.length; i++) {
          _detailedAddresses[i] = _detailedAddresses[i].copyWith(
            isDefault: _detailedAddresses[i].id == addressId,
          );
        }
        
        // تحديث العناوين المحلية للتوافق
        _addresses = _detailedAddresses
            .map((addr) => _convertDetailedToAddressModel(addr))
            .toList();
        
        // تعيين العنوان الافتراضي
        await _setDefaultAddressLocally();
        
        // حفظ محلياً
        await _saveAddressesLocally();
        
        _error = null;
        _notifyIfNotDisposed();
        
        return true;
        
      } else {
        final errorMessage = result['message'] ?? 'فشل في تعيين العنوان الافتراضي';
        _error = errorMessage;
        print('❌ فشل في تعيين العنوان الافتراضي: $errorMessage');
        _notifyIfNotDisposed();
        return false;
      }
      
    } catch (e) {
      _error = 'خطأ في تعيين العنوان الافتراضي: $e';
      print('💥 خطأ في تعيين العنوان الافتراضي: $e');
      _notifyIfNotDisposed();
      return false;
    }
  }

  // Delete address
  Future<bool> deleteAddress(String addressId) async {
    try {
      print('🗑️ حذف العنوان: $addressId');
      
      // التحقق من حالة تسجيل الدخول
      final isLoggedIn = SessionService.instance.isLoggedIn;
      if (!isLoggedIn) {
        _error = 'المستخدم غير مسجل دخول. يرجى تسجيل الدخول أولاً';
        print('❌ المستخدم غير مسجل دخول');
        _notifyIfNotDisposed();
        return false;
      }

      // الحصول على token وuser_id من الجلسة النشطة
      String? token = SessionService.instance.accessToken;
      
      if (token == null) {
        _error = 'لم يتم العثور على token المصادقة';
        print('❌ Token is empty');
        return false;
      }

      // استدعاء API
      final result = await ApiService.deleteUserAddress(
        token: token,
        addressId: addressId,
      );
      
      if (result['success'] == true) {
        
        // إزالة العنوان من القائمة
        _detailedAddresses.removeWhere((addr) => addr.id == addressId);
        _addresses.removeWhere((addr) => addr.id == addressId);
        
        // إذا كان العنوان المحذوف هو الافتراضي، عين الأول كافتراضي
        await _setDefaultAddressLocally();
        
        // حفظ محلياً
        await _saveAddressesLocally();
        
        _error = null;
        _notifyIfNotDisposed();
        
        return true;
        
      } else {
        final errorMessage = result['message'] ?? 'فشل في حذف العنوان';
        _error = errorMessage;
        print('❌ فشل في حذف العنوان: $errorMessage');
        _notifyIfNotDisposed();
        return false;
      }
      
    } catch (e) {
      _error = 'خطأ في حذف العنوان: $e';
      print('💥 خطأ في حذف العنوان: $e');
      _notifyIfNotDisposed();
      return false;
    }
  }

  // Update address
  Future<DetailedAddress?> updateAddress(String addressId, AddressUpdateRequest request) async {
    try {
      print('📝 تحديث العنوان: $addressId');
      
      // التحقق من حالة تسجيل الدخول
      final isLoggedIn = SessionService.instance.isLoggedIn;
      if (!isLoggedIn) {
        _error = 'المستخدم غير مسجل دخول. يرجى تسجيل الدخول أولاً';
        print('❌ المستخدم غير مسجل دخول');
        _notifyIfNotDisposed();
        return null;
      }

      // الحصول على token وuser_id من الجلسة النشطة
      String? token = SessionService.instance.accessToken;
      
      if (token == null) {
        _error = 'لم يتم العثور على token المصادقة';
        print('❌ Token is empty');
        return null;
      }

      // تحضير بيانات العنوان للتحديث
      final addressData = <String, dynamic>{};
      if (request.name != null) addressData['name'] = request.name;
      if (request.province != null) addressData['province'] = request.province;
      if (request.district != null) addressData['district'] = request.district;
      if (request.neighborhood != null) addressData['neighborhood'] = request.neighborhood;
      if (request.landmark != null) addressData['landmark'] = request.landmark;
      if (request.detailedAddress != null) addressData['detailed_address'] = request.detailedAddress;
      if (request.latitude != null) addressData['latitude'] = request.latitude;
      if (request.longitude != null) addressData['longitude'] = request.longitude;
      if (request.addressType != null) addressData['address_type'] = request.addressType;
      if (request.isDefault != null) addressData['is_default'] = request.isDefault;
      if (request.buildingNumber != null) addressData['building_number'] = request.buildingNumber;
      if (request.floorNumber != null) addressData['floor_number'] = request.floorNumber;
      if (request.apartmentNumber != null) addressData['apartment_number'] = request.apartmentNumber;
      if (request.phoneNumber != null) addressData['phone_number'] = request.phoneNumber;

      print('📋 بيانات العنوان المحدثة: $addressData');

      // استدعاء API
      final result = await ApiService.updateUserAddress(
        token: token,
        addressId: addressId,
        name: request.name ?? '',
        province: request.province ?? '',
        district: request.district ?? '',
        neighborhood: request.neighborhood ?? '',
        landmark: request.landmark ?? '',
        isDefault: request.isDefault ?? false,
        detailedAddress: request.detailedAddress,
        buildingNumber: request.buildingNumber,
        floorNumber: request.floorNumber,
        apartmentNumber: request.apartmentNumber,
        phoneNumber: request.phoneNumber,
        latitude: request.latitude,
        longitude: request.longitude,
        addressType: request.addressType,
      );
      
      if (result['success'] == true && result['data'] != null) {
        
        // إنشاء DetailedAddress من الاستجابة
        final updatedAddress = DetailedAddress.fromJson(result['data']);
        
        // تحديث العنوان في القائمة
        final index = _detailedAddresses.indexWhere((addr) => addr.id == addressId);
        if (index != -1) {
          _detailedAddresses[index] = updatedAddress;
          _addresses[index] = _convertDetailedToAddressModel(updatedAddress);
        }
        
        // إذا كان العنوان محدد كافتراضي، تعيينه
        if (updatedAddress.isDefault) {
          await _setDefaultAddressLocally();
        }
        
        // حفظ محلياً
        await _saveAddressesLocally();
        
        _error = null;
        _notifyIfNotDisposed();
        
        return updatedAddress;
        
      } else {
        final errorMessage = result['message'] ?? 'فشل في تحديث العنوان';
        _error = errorMessage;
        print('❌ فشل في تحديث العنوان: $errorMessage');
        _notifyIfNotDisposed();
        return null;
      }
      
    } catch (e) {
      _error = 'خطأ في تحديث العنوان: $e';
      print('💥 خطأ في تحديث العنوان: $e');
      _notifyIfNotDisposed();
      return null;
    }
  }

  // Clear all data
  void clearData() {
    _addresses.clear();
    _detailedAddresses.clear();
    _currentAddress = null;
    _selectedAddress = null;
    _currentLocationAddress = null;
    _error = null;
    _locationError = null;
    _notifyIfNotDisposed();
  }

  // Refresh addresses
  Future<void> refreshAddresses() async {
    clearData();
    await loadAddressesFromAPI();
  }

  // Helper method to convert DetailedAddress to AddressModel for compatibility
  AddressModel _convertDetailedToAddressModel(DetailedAddress detailed) {
    return AddressModel(
      id: detailed.id,
      name: detailed.name,
      fullAddress: detailed.fullAddress,
      latitude: detailed.latitude ?? 0.0,
      longitude: detailed.longitude ?? 0.0,
      isDefault: detailed.isDefault,
      isCurrent: false,
      type: detailed.addressType,
    );
  }

  // Helper method to set default address locally
  Future<void> _setDefaultAddressLocally() async {
    // Find the default address and set others to non-default
    for (int i = 0; i < _detailedAddresses.length; i++) {
      if (_detailedAddresses[i].isDefault) {
        _currentAddress = _convertDetailedToAddressModel(_detailedAddresses[i]);
        _selectedAddress = _currentAddress;
        break;
      }
    }
    
    // If no default address found, set the first one as default
    if (_currentAddress == null && _detailedAddresses.isNotEmpty) {
      _currentAddress = _convertDetailedToAddressModel(_detailedAddresses.first);
      _selectedAddress = _currentAddress;
    }
  }

  // Helper method to save addresses locally (placeholder for future local storage)
  Future<void> _saveAddressesLocally() async {
    // TODO: Implement local storage using SharedPreferences or Hive
    // For now, this is just a placeholder
    print('💾 حفظ العناوين محلياً (placeholder)');
  }

  // Add missing getCurrentLocationAddress method
  Future<void> getCurrentLocationAddress() async {
    print('📍 بدء الحصول على الموقع الحالي...');
    
    _isLoadingLocation = true;
    _locationError = null;
    _notifyIfNotDisposed();

    try {
      // 1. التحقق من إذن الموقع
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        print('⚠️ طلب إذن الموقع...');
        permission = await Geolocator.requestPermission();
        
        if (permission == LocationPermission.denied) {
          throw Exception('تم رفض إذن الوصول إلى الموقع');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('تم رفض إذن الموقع بشكل دائم. يرجى تفعيله من الإعدادات');
      }

      // 2. الحصول على الموقع الحالي
      print('🌐 جلب إحداثيات GPS...');
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      
      print('✅ تم الحصول على الموقع: ${position.latitude}, ${position.longitude}');

      // 3. تحويل GPS إلى عنوان
      print('🗺️ تحويل الإحداثيات إلى عنوان...');
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        throw Exception('لم يتم العثور على عنوان لهذا الموقع');
      }

      // 4. بناء العنوان من Placemark
      Placemark place = placemarks.first;
      print('📍 تفاصيل العنوان:');
      print('   - Country: ${place.country}');
      print('   - AdministrativeArea: ${place.administrativeArea}');
      print('   - SubAdministrativeArea: ${place.subAdministrativeArea}');
      print('   - Locality: ${place.locality}');
      print('   - SubLocality: ${place.subLocality}');
      print('   - Thoroughfare: ${place.thoroughfare}');
      print('   - SubThoroughfare: ${place.subThoroughfare}');

      // بناء العنوان الكامل
      List<String> addressParts = [];
      
      if (place.country != null && place.country!.isNotEmpty) {
        addressParts.add(place.country!);
      }
      
      if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
        addressParts.add(place.administrativeArea!);
      }
      
      if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty) {
        addressParts.add(place.subAdministrativeArea!);
      }
      
      if (place.locality != null && place.locality!.isNotEmpty) {
        addressParts.add(place.locality!);
      }
      
      if (place.subLocality != null && place.subLocality!.isNotEmpty) {
        addressParts.add(place.subLocality!);
      }

      String fullAddress = addressParts.isNotEmpty 
          ? addressParts.join('، ') 
          : 'الموقع الحالي';

      // إنشاء DetailedAddress
      _currentLocationAddress = DetailedAddress(
        id: 'current_location_${DateTime.now().millisecondsSinceEpoch}',
        userId: SessionService.instance.currentUserId ?? '',
        name: 'الموقع الحالي',
        province: place.administrativeArea ?? '',
        district: place.locality ?? '',
        neighborhood: place.subLocality ?? '',
        landmark: place.thoroughfare ?? '',
        detailedAddress: place.street,
        fullAddress: fullAddress,
        latitude: position.latitude,
        longitude: position.longitude,
        addressType: 'current',
        isDefault: false,
        buildingNumber: place.subThoroughfare,
        floorNumber: null,
        apartmentNumber: null,
        phoneNumber: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      print('✅ تم الحصول على العنوان: $fullAddress');
      _locationError = null;
      
    } on PermissionDeniedException catch (e) {
      _locationError = 'تم رفض إذن الوصول إلى الموقع. يرجى تفعيله من الإعدادات';
      print('❌ خطأ إذن: $e');
      _currentLocationAddress = null;
    } on LocationServiceDisabledException catch (e) {
      _locationError = 'خدمة الموقع غير مفعلة. يرجى تفعيل GPS';
      print('❌ GPS غير مفعل: $e');
      _currentLocationAddress = null;
    } catch (e) {
      _locationError = 'خطأ في الحصول على الموقع الحالي: $e';
      print('💥 خطأ في الحصول على الموقع: $e');
      _currentLocationAddress = null;
    } finally {
      _isLoadingLocation = false;
      _notifyIfNotDisposed();
    }
  }
}

// Extension for AddressModel compatibility
extension AddressModelExtension on AddressModel {
  static AddressModel fromDetailedAddress(DetailedAddress detailed) {
    return AddressModel(
      id: detailed.id,
      name: detailed.name,
      fullAddress: detailed.fullAddress,
      latitude: detailed.latitude ?? 0.0,
      longitude: detailed.longitude ?? 0.0,
      isDefault: detailed.isDefault,
      isCurrent: false,
      type: detailed.addressType,
    );
  }
}