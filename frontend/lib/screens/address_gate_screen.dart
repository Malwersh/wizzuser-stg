import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

import '../constants/app_colors.dart';
import '../models/delivery_address.dart';
import '../models/address_model.dart';
import '../services/delivery_address_manager.dart';
import '../services/guest_cache_service.dart';
import '../services/address_service.dart';
import '../services/region_resolver_service.dart';
import '../config/google_places_config.dart';
import 'home_screen.dart';

/// شاشة بوابة العنوان - Address Gate Screen
/// 
/// الغرض: منع الوصول إلى HomeScreen بدون عنوان توصيل نشط
/// مشابهة لشاشة DoorDash لاختيار العنوان
class AddressGateScreen extends StatefulWidget {
  final bool isGuest;
  final bool showBackButton;
  
  const AddressGateScreen({
    Key? key,
    required this.isGuest,
    this.showBackButton = false,
  }) : super(key: key);

  @override
  State<AddressGateScreen> createState() => _AddressGateScreenState();
}

class _AddressGateScreenState extends State<AddressGateScreen> {
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  Timer? _debounce;
  List<DeliveryAddress> _savedAddresses = [];
  String? _searchError; // حالة خطأ البحث
  String? _currentLocationName; // اسم المنطقة الحالية

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }
  
  @override
  void didUpdateWidget(covariant AddressGateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // إعادة تحميل العناوين عند تحديث الـ widget
    _loadSavedAddresses();
  }
  
  /// تحميل العناوين المحفوظة (من Cache للضيف أو من Database للمستخدم)
  Future<void> _loadSavedAddresses() async {
    print('🔄 بدء تحميل العناوين المحفوظة...');
    print('   نوع المستخدم: ${widget.isGuest ? "ضيف" : "مسجل"}');
    
    try {
      if (widget.isGuest) {
        // جلب كل العناوين السابقة للضيف من Cache
        final guestAddresses = await GuestCacheService.getAllGuestAddresses();
        print('📍 تم جلب ${guestAddresses.length} عنوان للضيف من Cache');
        
        // طباعة تفاصيل كل عنوان
        for (var i = 0; i < guestAddresses.length; i++) {
          print('   ${i + 1}. ${guestAddresses[i].formattedAddress}');
        }
        
        setState(() {
          _savedAddresses = guestAddresses;
        });
      } else {
        // جلب عناوين المستخدم المسجل من Database
        final addressService = EnhancedAddressService();
        await addressService.loadAddressesFromAPI();
        
        // تحويل DetailedAddress إلى DeliveryAddress
        final userAddresses = addressService.detailedAddresses.map((detailedAddr) {
          return DeliveryAddress(
            label: detailedAddr.name, // استخدم 'name' من DetailedAddress
            formattedAddress: detailedAddr.fullAddress,
            latitude: detailedAddr.latitude ?? 0,
            longitude: detailedAddr.longitude ?? 0,
            regionId: detailedAddr.regionId, // استخدم region_id الموجود
            city: detailedAddr.province, // province = المحافظة
            source: AddressSource.saved,
            isDefault: detailedAddr.isDefault,
            timestamp: DateTime.now(),
          );
        }).toList();
        
        print('📍 تم جلب ${userAddresses.length} عنوان للمستخدم من Database');
        setState(() {
          _savedAddresses = userAddresses;
        });
      }
    } catch (e) {
      print('❌ خطأ في تحميل العناوين المحفوظة: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// البحث عن عنوان باستخدام Google Places API
  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
      });
      return;
    }

    try {
      final apiKey = GooglePlacesConfig.httpKey; // المفتاح الصحيح للـ HTTP API
      print('🔍 بدء البحث عن: $query');

      
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&components=country:iq'
        '&language=ar'
        '&key=$apiKey',
      );


      final response = await http.get(url);
      print('📥 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Data: ${data['status']}');
        print('📋 عدد النتائج: ${data['predictions']?.length ?? 0}');
        
        setState(() {
          if (data['status'] == 'REQUEST_DENIED') {
            _searchError = 'خدمة البحث غير متاحة حالياً. الرجاء استخدام زر الموقع الحالي.';
            _searchResults = [];
            print('❌ REQUEST_DENIED: ${data['error_message'] ?? "لا توجد رسالة"}');
          } else if (data['status'] == 'ZERO_RESULTS') {
            _searchError = null;
            _searchResults = [];
            print('⚠️ لا توجد نتائج لـ: $query');
          } else if (data['status'] == 'OK') {
            _searchError = null;
            _searchResults = data['predictions'] ?? [];
          } else {
            _searchError = 'خطأ غير متوقع في البحث';
            _searchResults = [];
            print('⚠️ حالة غير معروفة: ${data['status']}');
          }
        });
      } else {
        print('❌ خطأ HTTP: ${response.statusCode} - ${response.body}');
        setState(() {
          _searchError = 'خطأ في الاتصال بخدمة البحث';
          _searchResults = [];
        });
      }
    } catch (e) {
      print('❌ خطأ في البحث: $e');
      setState(() {
        _searchError = 'حدث خطأ أثناء البحث';
        _searchResults = [];
      });
    }
  }

  /// الحصول على تفاصيل المكان من place_id
  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    try {
      final apiKey = GooglePlacesConfig.httpKey; // المفتاح الصحيح للـ HTTP API
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=formatted_address,geometry,name,address_components'
        '&language=ar'
        '&key=$apiKey',
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'];
        
        if (result != null) {
          return {
            'formattedAddress': result['formatted_address'] ?? '',
            'latitude': result['geometry']['location']['lat'],
            'longitude': result['geometry']['location']['lng'],
            'name': result['name'] ?? '',
          };
        }
      }
    } catch (e) {
      print('خطأ في جلب تفاصيل المكان: $e');
    }
    return null;
  }

  /// الحصول على اسم المنطقة من الإحداثيات (Reverse Geocoding)
  Future<String> _getLocationName(double latitude, double longitude) async {
    try {
      final apiKey = GooglePlacesConfig.httpKey;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$latitude,$longitude'
        '&key=$apiKey'
        '&language=ar',
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'OK' && data['results'] != null && data['results'].isNotEmpty) {
          // محاولة الحصول على المدينة أو المنطقة
          final result = data['results'][0];
          
          // البحث عن locality (المدينة)
          for (var component in result['address_components']) {
            final types = component['types'] as List;
            if (types.contains('locality')) {
              return component['long_name'] as String;
            }
          }
          
          // إذا لم نجد المدينة، نستخدم formatted_address
          return result['formatted_address'] as String;
        }
      }
    } catch (e) {
      print('خطأ في الحصول على اسم المنطقة: $e');
    }
    
    // في حالة الفشل، نرجع الإحداثيات
    return 'موقعك الحالي';
  }

  /// البحث عن region_id باستخدام RegionResolverService (نفس الخدمة في add_address_screen)
  Future<String?> _findRegionId(double latitude, double longitude) async {
    try {
      print('🗺️ البحث عن المنطقة للإحداثيات: $latitude, $longitude');
      
      final regionService = RegionResolverService();
      final result = await regionService.resolvePoint(
        lat: latitude,
        lng: longitude,
        throwOnFailure: true,
      );
      
      if (result != null && result.success) {
        print('✅ تم العثور على المنطقة: ${result.region.nameAr} (${result.region.id})');
        print('🟢 المنطقة نشطة: ${result.effective.isActive}');
        print('📦 خدمة التوصيل متوفرة: ${result.effective.hasDelivery}');
        
        // ⚠️ نفس المنطق في location_picker_screen.dart
        if (!result.effective.isActive) {
          print('⚠️ المنطقة غير نشطة');
          return null;
        }
        
        if (!result.effective.hasDelivery) {
          print('⚠️ خدمة التوصيل غير متوفرة في: ${result.region.nameAr}');
          return null;
        }
        
        // ✅ المنطقة نشطة AND لديها خدمة توصيل
        print('✅ التوصيل متاح في: ${result.region.nameAr}');
        return result.region.id;
      } else {
        print('❌ لم يتم العثور على المنطقة');
        return null;
      }
    } catch (e) {
      if (e is RegionResolutionException) rethrow;
      return null;
    }
  }

  /// معالجة اختيار عنوان من نتائج البحث
  Future<void> _handleSearchResultTap(dynamic result) async {
    setState(() => _isLoading = true);
    
    try {
      final placeDetails = await _getPlaceDetails(result['place_id']);
      
      if (placeDetails != null) {
        // الحصول على region_id
        final regionId = await _findRegionId(
          placeDetails['latitude'],
          placeDetails['longitude'],
        );
        
        // إنشاء العنوان
        await _createAddressFromDetails(placeDetails, regionId);
      } else {
        _showErrorSnackBar('فشل تحميل تفاصيل المكان');
      }
    } catch (e) {
      print('خطأ في معالجة اختيار العنوان: $e');
      _showErrorSnackBar(e is RegionResolutionException ? e.toString() : 'حدث خطأ');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// إنشاء عنوان من التفاصيل
  Future<void> _createAddressFromDetails(
    Map<String, dynamic> addressData,
    String? regionId,
  ) async {
    // استخراج اسم المدينة
    String city = 'النجف';
    final formattedAddress = addressData['formattedAddress'] as String;
    if (formattedAddress.contains('Baghdad') || formattedAddress.contains('بغداد')) {
      city = 'بغداد';
    } else if (formattedAddress.contains('Najaf') || formattedAddress.contains('النجف')) {
      city = 'النجف';
    }

    final deliveryAddress = DeliveryAddress(
      label: addressData['name'] ?? 'العنوان المحدد',
      formattedAddress: formattedAddress,
      latitude: addressData['latitude'],
      longitude: addressData['longitude'],
      regionId: regionId,
      city: city,
      source: AddressSource.manual,
      isDefault: true,
      timestamp: DateTime.now(),
    );

    await _saveAndProceed(deliveryAddress);
  }

  /// استخدام الموقع الحالي (GPS)
  Future<void> _useCurrentLocation() async {
    setState(() => _isLoading = true);

    try {
      // 1. التحقق من صلاحيات GPS
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showPermissionDeniedDialog();
        setState(() => _isLoading = false);
        return;
      }

      // 2. الحصول على الموقع الحالي
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      print('📍 الموقع: ${position.latitude}, ${position.longitude}');

      // 3. الحصول على اسم المنطقة
      _currentLocationName = await _getLocationName(
        position.latitude,
        position.longitude,
      );
      print('🌍 اسم المنطقة: $_currentLocationName');

      // 4. البحث عن region_id
      final regionId = await _findRegionId(
        position.latitude,
        position.longitude,
      );
      
      print('🏘️ Region ID: $regionId');

      // 5. إنشاء عنوان من الإحداثيات
      final deliveryAddress = DeliveryAddress(
        label: 'موقعي الحالي',
        formattedAddress: 'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}',
        latitude: position.latitude,
        longitude: position.longitude,
        regionId: regionId,
        city: 'النجف', // افتراضياً
        source: AddressSource.gps,
        isDefault: true,
        timestamp: DateTime.now(),
      );

      // 6. حفظ العنوان
      await _saveAndProceed(deliveryAddress);

    } catch (e) {
      print('خطأ في الحصول على الموقع: $e');
      _showErrorSnackBar(e is RegionResolutionException ? e.toString() : 'فشل تحديد موقعك الحالي');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// حفظ العنوان والانتقال إلى HomeScreen
  Future<void> _saveAndProceed(DeliveryAddress address) async {
    try {
      // ✅ التحقق من region_id قبل المتابعة
      if (address.regionId == null || address.regionId!.isEmpty) {
        print('❌ لا يوجد region_id - المنطقة غير مخدومة');
        _showRegionNotSupportedDialog();
        return;
      }
      
      final addressManager = DeliveryAddressManager.instance;

      if (widget.isGuest) {
        // حفظ في Cache للضيف (كعنوان نشط)
        await GuestCacheService.saveGuestAddress(address);
        print('✅ تم حفظ العنوان كعنوان نشط: ${address.formattedAddress}');
        
        // ✅ إضافة للقائمة للعرض في المرات القادمة
        await GuestCacheService.addGuestAddressToList(address);
        print('✅ تم إضافة العنوان للقائمة المحفوظة');
        
        // التحقق من الحفظ
        final savedList = await GuestCacheService.getAllGuestAddresses();
        print('📊 إجمالي العناوين المحفوظة الآن: ${savedList.length}');
      } else {
        // 🆕 حفظ عنوان المستخدم المسجّل في قاعدة البيانات مع region_id
        // نحفظ فقط العناوين الجديدة (من البحث أو GPS)، أما العناوين المحفوظة
        // مسبقاً (source == saved) فلا نكررها في قاعدة البيانات.
        if (address.source != AddressSource.saved) {
          try {
            final addressService = context.read<EnhancedAddressService>();
            final request = AddressCreateRequest(
              name: (address.label != null && address.label!.trim().isNotEmpty)
                  ? address.label!.trim()
                  : 'عنوان التوصيل',
              province: address.city.isNotEmpty ? address.city : 'غير محدد',
              district: '-',
              neighborhood:
                  (address.neighborhood != null && address.neighborhood!.trim().isNotEmpty)
                      ? address.neighborhood!.trim()
                      : '-',
              landmark: 'موقع محدد من الخريطة',
              detailedAddress: address.formattedAddress,
              latitude: address.latitude,
              longitude: address.longitude,
              addressType: AddressType.other,
              isDefault: address.isDefault,
              // ✅ تخزين region_id مع العنوان حتى لا يُعاد حسابه عند كل إقلاع
              regionId: address.regionId,
              regionNameAr: address.regionNameAr,
            );
            final created = await addressService.createAddress(request);
            if (created != null) {
              print('✅ تم حفظ عنوان المستخدم المسجّل في قاعدة البيانات: ${created.id}');
              // استخدم addressId الحقيقي من قاعدة البيانات واجعل المصدر saved
              // حتى يُحفظ كـ "آخر عنوان مستخدم" ولا يُعاد إنشاؤه لاحقاً.
              address = DeliveryAddress(
                addressId: created.id,
                userId: created.userId,
                label: address.label,
                formattedAddress: address.formattedAddress,
                latitude: address.latitude,
                longitude: address.longitude,
                regionId: address.regionId,
                regionNameAr: address.regionNameAr,
                neighborhood: address.neighborhood,
                city: address.city,
                source: AddressSource.saved,
                isDefault: address.isDefault,
                timestamp: DateTime.now(),
              );
            }
          } catch (e) {
            print('⚠️ تعذّر حفظ العنوان في قاعدة البيانات: $e');
            // نكمل حتى لو فشل الحفظ (يبقى العنوان نشطاً للجلسة الحالية)
          }
        } else {
          print('ℹ️ عنوان محفوظ مسبقاً - لا حاجة لإعادة الحفظ في قاعدة البيانات');
        }
      }

      // تعيين كعنوان نشط
      await addressManager.setActiveAddress(address);

      // فحص المسافة (سنضيفها لاحقاً)
      // await _checkDistanceWarning(address);

      // الانتقال إلى HomeScreen
      if (!mounted) return;
      
      if (widget.showBackButton) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      print('خطأ في حفظ العنوان: $e');
      _showErrorSnackBar('فشل حفظ العنوان');
    }
  }

  /// Dialog صلاحيات GPS
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 8),
            Text('صلاحيات الموقع'),
          ],
        ),
        content: Text(
          'يحتاج التطبيق إلى صلاحية الوصول لموقعك لتحديد عنوان التوصيل.\n\n'
          'يرجى تفعيل صلاحية الموقع من إعدادات التطبيق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('حسناً'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: Text('فتح الإعدادات'),
          ),
        ],
      ),
    );
  }
  
  /// عرض رسالة أن المنطقة غير مخدومة
  void _showRegionNotSupportedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.orange, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'منطقة غير مخدومة',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عرض اسم المنطقة الحالية
            if (_currentLocationName != null) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.orange[700], size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 15, color: Colors.black87),
                          children: [
                            TextSpan(
                              text: 'أنت في: ',
                              style: TextStyle(fontWeight: FontWeight.normal),
                            ),
                            TextSpan(
                              text: _currentLocationName!,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],
            Text(
              'عذراً، هذه المنطقة غير مخدومة حالياً.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'قد تكون المنطقة ضمن نطاق خدمتنا، لكن لا يوجد مطاعم تخدمها في الوقت الحالي.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📍 المناطق المخدومة بشكل مؤكد:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('• بغداد (مناطق مختارة)\n• النجف (مناطق محددة)\n• كربلاء (مناطق مختارة)'),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'يرجى اختيار عنوان من المناطق المخدومة باستخدام شريط البحث أو تجربة عنوان آخر.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text(
              'حسناً، سأختار عنواناً آخر',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// عرض رسالة خطأ
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('اختيار عنوان التوصيل'),
        backgroundColor: AppColors.primary,
        automaticallyImplyLeading: widget.showBackButton,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // شريط البحث
              Container(
                padding: EdgeInsets.all(16),
                color: Colors.white,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن عنوان',
                    prefixIcon: Icon(Icons.search, color: AppColors.primary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _searchError = null; // مسح رسالة الخطأ
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (value) {
                    // Debounce للبحث
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      if (value.length > 2) {
                        _searchAddress(value);
                      } else {
                        setState(() => _searchResults = []);
                      }
                    });
                  },
                ),
              ),

              Divider(height: 1),

              // المحتوى الرئيسي
              Expanded(
                child: _searchError != null
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 64, color: Colors.orange),
                              SizedBox(height: 16),
                              Text(
                                _searchError!,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange[700],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 24),
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.blue),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'يمكنك استخدام زر "موقعي الحالي" للمتابعة',
                                        style: TextStyle(color: Colors.blue[900]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _searchController.text.length > 2 && _searchResults.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد نتائج',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'جرب البحث باستخدام اسم مكان آخر',
                                style: TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _searchResults.isNotEmpty
                    ? _buildSearchResults()
                    : _buildDefaultContent(),
              ),
            ],
          ),

          // مؤشر التحميل
          if (_isLoading)
            Container(
              color: Colors.black45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'جارٍ التحميل...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// بناء نتائج البحث
  Widget _buildSearchResults() {
    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => Divider(height: 1),
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return ListTile(
          leading: Icon(Icons.location_on, color: Colors.grey),
          title: Text(
            result['structured_formatting']['main_text'] ?? '',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            result['structured_formatting']['secondary_text'] ?? '',
            style: TextStyle(fontSize: 12),
          ),
          onTap: () => _handleSearchResultTap(result),
        );
      },
    );
  }

  /// بناء المحتوى الافتراضي
  Widget _buildDefaultContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قسم "Explore Nearby"
            SizedBox(height: 16),
            Text(
              'استكشف القريب منك',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16),
            
            // زر استخدام الموقع الحالي
            InkWell(
              onTap: _isLoading ? null : _useCurrentLocation,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.my_location,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'استخدام موقعي الحالي',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'أضف عنوانك لاحقاً',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                  ],
                ),
              ),
            ),
            
            // قسم "العناوين المحفوظة"
            if (_savedAddresses.isNotEmpty) ...[
              SizedBox(height: 32),
              Text(
                'العناوين المحفوظة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 16),
              
              // قائمة العناوين المحفوظة
              ..._savedAddresses.map((address) => _buildSavedAddressItem(address)).toList(),
            ],
            
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  
  /// بناء عنصر عنوان محفوظ
  Widget _buildSavedAddressItem(DeliveryAddress address) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _selectSavedAddress(address),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address.label ?? 'عنوان محفوظ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      address.formattedAddress,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
  
  /// اختيار عنوان محفوظ
  Future<void> _selectSavedAddress(DeliveryAddress address) async {
    setState(() => _isLoading = true);
    
    try {
      // التحقق من region_id
      if (address.regionId == null || address.regionId!.isEmpty) {
        // محاولة الحصول على region_id
        final regionId = await _findRegionId(
          address.latitude,
          address.longitude,
        );
        
        if (regionId != null) {
          address = DeliveryAddress(
            label: address.label,
            formattedAddress: address.formattedAddress,
            latitude: address.latitude,
            longitude: address.longitude,
            regionId: regionId,
            city: address.city,
            source: address.source,
            isDefault: address.isDefault,
            timestamp: DateTime.now(),
          );
        }
      }
      
      await _saveAndProceed(address);
    } catch (e) {
      print('خطأ في اختيار العنوان المحفوظ: $e');
      _showErrorSnackBar(e is RegionResolutionException ? e.toString() : 'فشل تحديد العنوان');
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
