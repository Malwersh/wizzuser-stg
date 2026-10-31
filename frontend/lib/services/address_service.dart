import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'address_book_api_319.dart';
import 'address_save_attempt_319.dart';
import 'browsing_location_service.dart';
import 'saved_address_selection_319.dart';
import 'delivery_address_manager.dart';
import 'address_write_result.dart';
// lib/services/address_service.dart - Dynamic Version

import 'package:flutter/material.dart';
import '../models/address_model.dart';
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

  final AddressBookApi319 api;
  final String? Function() owner;
  final bool Function() loggedIn;
  final Future<String?> Function() freshToken;
  final Future<void> Function(DetailedAddress) activate;
  final BrowsingLocationService browsing;
  String? _scope;
  int _epoch = 0;
  bool _cacheLoaded = false;
  StreamSubscription? _session;
  Future<void> _cacheWrites = Future.value();
  final _creates = <String, Future<DetailedAddress?>>{};
  EnhancedAddressService({
    AddressBookApi319? api,
    String? Function()? owner,
    bool Function()? loggedIn,
    Future<String?> Function()? freshToken,
    Future<void> Function(DetailedAddress)? activate,
    BrowsingLocationService? browsing,
  }) : api = api ?? AddressBookApi319.instance,
       owner = owner ?? (() => SessionService.instance.currentUserId),
       loggedIn = loggedIn ?? (() => SessionService.instance.isLoggedIn),
       freshToken = freshToken ?? (() => SessionService.instance.getToken()),
       activate = activate ?? SavedAddressSelection319.activate,
       browsing = browsing ?? BrowsingLocationService.instance {
    _scope = this.owner();
    if (owner == null)
      _session = SessionService.instance.sessionStateStream.listen((_) {
        _syncScope();
      });
  }
  void _syncScope() {
    if (_scope != owner()) {
      ++_epoch;
      _scope = owner();
      _cacheLoaded = false;
      _detailedAddresses = [];
      _addresses = [];
      _currentAddress = null;
      _selectedAddress = null;
      _currentLocationAddress = null;
      _error = null;
      _isLoading = false;
      _notifyIfNotDisposed();
    }
  }

  bool get _sameOwner => _scope == owner();
  List<AddressModel> get addresses =>
      _sameOwner ? List.unmodifiable(_addresses) : [];
  List<DetailedAddress> get detailedAddresses =>
      _sameOwner ? List.unmodifiable(_detailedAddresses) : [];
  AddressModel? get currentAddress => _sameOwner ? _currentAddress : null;
  AddressModel? get selectedAddress =>
      _sameOwner ? (_selectedAddress ?? _currentAddress) : null;
  DetailedAddress? get currentLocationAddress => _currentLocationAddress;
  bool get isLoadingLocation => _isLoadingLocation;
  bool get isLoading => _isLoading;
  String? get locationError => _locationError;
  String? get error => _error;
  DetailedAddress? get defaultAddress {
    for (final a in detailedAddresses) {
      if (a.isDefault) return a;
    }
    return null;
  }

  bool get hasAddresses => detailedAddresses.isNotEmpty;
  int get addressCount => detailedAddresses.length;

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _session?.cancel();
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

  Map<String, dynamic> _data(Map<String, dynamic> result) {
    dynamic value = result;
    for (var i = 0; i < 4; i++) {
      if (value is! Map) break;
      if (value.containsKey('addresses'))
        return Map<String, dynamic>.from(value);
      value = value['data'];
    }
    throw const FormatException('Invalid address book');
  }

  Future<void> _loadCachedBook(String id, int generation) async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance(),
          raw = prefs.getString('address_book_319_$id');
      if (raw == null || owner() != id || generation != _epoch) return;
      final data = jsonDecode(raw) as List;
      final rows =
          data
              .map(
                (r) => DetailedAddress.fromJson(Map<String, dynamic>.from(r)),
              )
              .toList();
      if (rows.any((a) => a.userId != id || a.id.isEmpty)) return;
      _detailedAddresses = rows;
      _addresses = rows.map(_convertDetailedToAddressModel).toList();
      await _setDefaultAddressLocally();
    } catch (_) {}
  }

  bool _lastFetchConfirmed = false;
  Future<void> fetchAddresses() async {
    _syncScope();
    final id = owner(), generation = ++_epoch;
    _lastFetchConfirmed = false;
    if (id == null || !loggedIn()) {
      _detailedAddresses = [];
      _addresses = [];
      _currentAddress = null;
      _selectedAddress = null;
      _error = null;
      _isLoading = false;
      _notifyIfNotDisposed();
      return;
    }
    _isLoading = true;
    _notifyIfNotDisposed();
    try {
      await _loadCachedBook(id, generation);
      final token = await freshToken();
      if (owner() != id || generation != _epoch || _disposed) return;
      if (token == null) throw StateError('Session unavailable');
      final result = await api.request(method: 'GET', owner: id, token: token);
      if (owner() != id || generation != _epoch || _disposed) return;
      if (result['success'] != true) {
        _error = result['message'];
        return;
      }
      final data = _data(result), raw = data['addresses'];
      if (raw is! List) throw const FormatException('Missing book');
      final rows =
          raw
              .map(
                (r) => DetailedAddress.fromJson(Map<String, dynamic>.from(r)),
              )
              .toList();
      if (rows.any((a) => a.id.isEmpty || a.userId != id) ||
          rows.map((a) => a.id).toSet().length != rows.length)
        throw const FormatException('Wrong owner');
      final defaultId = data['default_address_id'];
      if (defaultId != null && !rows.any((a) => a.id == defaultId))
        throw const FormatException('Missing default');
      _detailedAddresses =
          rows.map((a) => a.copyWith(isDefault: a.id == defaultId)).toList();
      _addresses =
          _detailedAddresses.map(_convertDetailedToAddressModel).toList();
      await _setDefaultAddressLocally();
      await _saveAddressesLocally();
      if (owner() != id || generation != _epoch || _disposed) return;
      _lastFetchConfirmed = true;
      _error = null;
      final selected = browsing.selection;
      if (selected?.source == 'saved') {
        final found = _detailedAddresses.where(
          (a) => a.id == selected!.savedAddressId,
        );
        if (found.isEmpty) {
          final fallback = defaultAddress;
          await browsing.clear();
          DeliveryAddressManager.instance.clearActiveSelection();
          await DeliveryAddressManager.instance.clearCache();
          if (fallback != null) await activate(fallback);
        } else {
          final a = found.first;
          if (a.latitude != selected!.latitude ||
              a.longitude != selected.longitude ||
              a.regionId != selected.regionId ||
              a.fullAddress != selected.addressText) {
            await activate(a);
          }
        }
      }
    } catch (_) {
      if (owner() == id && generation == _epoch)
        _error = 'تعذر تحديث عناوينك. تحقق من الاتصال وأعد المحاولة.';
    } finally {
      if (owner() == id && generation == _epoch && !_disposed) {
        _isLoading = false;
        _notifyIfNotDisposed();
      }
    }
  }

  Future<DetailedAddress?> createAddress(AddressCreateRequest address) {
    _syncScope();
    final id = owner();
    if (id == null || !loggedIn()) {
      _error = 'سجل الدخول لحفظ عنوانك.';
      _notifyIfNotDisposed();
      return Future.value(null);
    }
    final body = address.toJson();
    if (address.detailedAddress?.trim().isNotEmpty == true)
      body['fullAddress'] = address.detailedAddress!.trim();
    final signature = AddressSaveAttempt319.signature(id, body);
    if (_creates[signature] != null) return _creates[signature]!;
    Future<DetailedAddress?> run() async {
      ++_epoch;
      try {
        final key = await AddressSaveAttempt319.key(
          id,
          body,
          suggested: address.idempotencyKey,
        );
        body['idempotency_key'] = key;
        final token = await freshToken();
        if (token == null || owner() != id || _disposed) return null;
        var result = await api.request(
          method: 'POST',
          owner: id,
          token: token,
          body: body,
        );
        if (result['code'] == 'ADDRESS_BOOK_CHANGED')
          result = await api.request(
            method: 'POST',
            owner: id,
            token: token,
            body: body,
          );
        if (owner() != id || _disposed) return null;
        if (result['success'] != true) {
          _error = result['message'];
          return null;
        }
        final created = AddressWriteResult.parse(result, ownerId: id);
        await AddressSaveAttempt319.confirmed(id, body, key);
        if (address.saveToAddressBook) await fetchAddresses();
        if (owner() != id || _disposed) return null;
        _error = null;
        return created;
      } catch (_) {
        if (owner() == id)
          _error = 'تعذر تأكيد حفظ العنوان. أعد المحاولة للتحقق من النتيجة.';
        return null;
      } finally {
        _creates.remove(signature);
        _notifyIfNotDisposed();
      }
    }

    final task = run();
    _creates[signature] = task;
    return task;
  }

  Future<bool> setDefaultAddress(String addressId) async {
    _syncScope();
    final id = owner();
    if (id == null || !loggedIn()) return false;
    ++_epoch;
    try {
      final token = await freshToken();
      if (token == null || owner() != id) return false;
      final result = await api.request(
        method: 'PUT',
        owner: id,
        token: token,
        addressId: addressId,
        setDefault: true,
      );
      if (owner() != id || _disposed) return false;
      if (result['success'] != true && result['uncertain'] != true) {
        _error = result['message'];
        return false;
      }
      await fetchAddresses();
      if (owner() != id || !_lastFetchConfirmed) return false;
      final target = defaultAddress;
      if (target?.id != addressId) {
        _error = 'لم يتم تأكيد تغيير الافتراضي. حدّث القائمة وأعد المحاولة.';
        return false;
      }
      await activate(target!);
      if (owner() != id) return false;
      await _setDefaultAddressLocally();
      _error = null;
      return true;
    } catch (_) {
      _error = 'تعذر تأكيد تغيير الافتراضي. حدّث القائمة وأعد المحاولة.';
      return false;
    } finally {
      _notifyIfNotDisposed();
    }
  }

  Future<bool> deleteAddress(String addressId) async {
    _syncScope();
    final id = owner();
    if (id == null || !loggedIn()) return false;
    ++_epoch;
    try {
      final token = await freshToken();
      if (token == null || owner() != id) return false;
      final result = await api.request(
        method: 'DELETE',
        owner: id,
        token: token,
        addressId: addressId,
      );
      if (owner() != id || _disposed) return false;
      if (result['success'] != true && result['uncertain'] != true) {
        _error = result['message'];
        return false;
      }
      await fetchAddresses();
      if (owner() != id || !_lastFetchConfirmed) return false;
      if (_detailedAddresses.any((a) => a.id == addressId)) {
        _error = 'لم يتم تأكيد الحذف. أعد المحاولة.';
        return false;
      }
      _error = null;
      return true;
    } catch (_) {
      _error = 'تعذر تأكيد الحذف. حدّث القائمة وأعد المحاولة.';
      return false;
    } finally {
      _notifyIfNotDisposed();
    }
  }

  Future<DetailedAddress?> updateAddress(
    String addressId,
    AddressUpdateRequest request,
  ) async {
    _syncScope();
    final id = owner();
    if (id == null || !loggedIn()) return null;
    ++_epoch;
    try {
      final body = request.toJson()..removeWhere((k, v) => v == null);
      if (request.detailedAddress?.trim().isNotEmpty == true)
        body['fullAddress'] = request.detailedAddress!.trim();
      final token = await freshToken();
      if (token == null || owner() != id) return null;
      final result = await api.request(
        method: 'PUT',
        owner: id,
        token: token,
        addressId: addressId,
        body: body,
      );
      if (owner() != id || _disposed) return null;
      if (result['success'] != true) {
        final message = result['message'] as String?;
        if (result['uncertain'] == true) await fetchAddresses();
        if (owner() == id)
          _error = message ?? 'تعذر تأكيد التحديث. حدّث القائمة وأعد المحاولة.';
        return null;
      }
      final updated = AddressWriteResult.parse(result, ownerId: id);
      await fetchAddresses();
      if (owner() != id) return null;
      if (request.isDefault == true &&
          _lastFetchConfirmed &&
          defaultAddress?.id == addressId)
        await activate(updated);
      _error = null;
      return updated;
    } catch (_) {
      _error = 'تعذر تأكيد تحديث العنوان. حدّث القائمة ثم أعد المحاولة.';
      return null;
    } finally {
      _notifyIfNotDisposed();
    }
  }

  // Clear all data
  void clearData() {
    ++_epoch;
    _cacheLoaded = false;
    _lastFetchConfirmed = false;
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

  Future<void> _setDefaultAddressLocally() async {
    _currentAddress = null;
    _selectedAddress = null;
    final activeId = browsing.selection?.savedAddressId;
    DetailedAddress? selected;
    for (final a in _detailedAddresses) {
      if (a.id == activeId) selected = a;
    }
    selected ??= defaultAddress;
    if (selected != null) {
      _currentAddress = _convertDetailedToAddressModel(selected);
      _selectedAddress = _currentAddress;
    }
  }

  Future<void> _saveAddressesLocally() async {
    final id = owner(), generation = _epoch;
    if (id == null || id != _scope) return;
    final rows = _detailedAddresses.map((a) => a.toJson()).toList();
    final task = _cacheWrites.catchError((_) {}).then((_) async {
      if (owner() != id || generation != _epoch) return;
      final prefs = await SharedPreferences.getInstance();
      if (owner() == id && generation == _epoch)
        await prefs.setString('address_book_319_$id', jsonEncode(rows));
    });
    _cacheWrites = task;
    try {
      await task;
    } catch (_) {}
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
        throw Exception(
          'تم رفض إذن الموقع بشكل دائم. يرجى تفعيله من الإعدادات',
        );
      }

      // 2. الحصول على الموقع الحالي
      print('🌐 جلب إحداثيات GPS...');
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      print(
        '✅ تم الحصول على الموقع: ${position.latitude}, ${position.longitude}',
      );

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

      if (place.administrativeArea != null &&
          place.administrativeArea!.isNotEmpty) {
        addressParts.add(place.administrativeArea!);
      }

      if (place.subAdministrativeArea != null &&
          place.subAdministrativeArea!.isNotEmpty) {
        addressParts.add(place.subAdministrativeArea!);
      }

      if (place.locality != null && place.locality!.isNotEmpty) {
        addressParts.add(place.locality!);
      }

      if (place.subLocality != null && place.subLocality!.isNotEmpty) {
        addressParts.add(place.subLocality!);
      }

      String fullAddress =
          addressParts.isNotEmpty ? addressParts.join('، ') : 'الموقع الحالي';

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
