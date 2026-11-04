import '../utils/readable_colors.dart';
import '../services/device_location_hint.dart';
import '../widgets/location_picker_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/browsing_location.dart';
import '../services/browsing_location_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

import '../constants/app_colors.dart';
import '../models/delivery_address.dart';
import '../services/delivery_address_manager.dart';
import '../services/guest_cache_service.dart';
import '../services/address_service.dart';
import '../services/region_resolver_service.dart';
import '../config/google_places_config.dart';
import 'home_screen.dart';
import '../widgets/active_region_tree.dart';
import '../services/active_region_catalog.dart';

/// شاشة بوابة العنوان - Address Gate Screen
///
/// الغرض: منع الوصول إلى HomeScreen بدون عنوان توصيل نشط
/// مشابهة لشاشة DoorDash لاختيار العنوان
class AddressGateScreen extends StatefulWidget {
  final bool isGuest;
  final bool showBackButton;
  final ActiveRegionCatalog? regionCatalog;
  final BrowsingLocationService? browsingService;
  final Future<Map<String, dynamic>?> Function(
    BuildContext,
    LatLng?,
    String?,
    String?,
  )?
  pickPoint;

  const AddressGateScreen({
    Key? key,
    required this.isGuest,
    this.showBackButton = false,
    this.regionCatalog,
    this.browsingService,
    this.pickPoint,
  }) : super(key: key);

  @override
  State<AddressGateScreen> createState() => _AddressGateScreenState();
}

class _AddressGateScreenState extends State<AddressGateScreen> {
  bool _isLoading = false;
  bool _savingSelection = false;
  bool _choosingPoint = false;
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
    unawaited(DeviceLocationHint.instance.acquire());
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

        if (!mounted) return;
        setState(() {
          _savedAddresses = guestAddresses;
        });
      } else {
        // جلب عناوين المستخدم المسجل من Database
        final addressService = context.read<EnhancedAddressService>();
        await addressService.loadAddressesFromAPI();

        // تحويل DetailedAddress إلى DeliveryAddress
        final userAddresses =
            addressService.detailedAddresses.map((detailedAddr) {
              return DeliveryAddress.fromSavedAddress(detailedAddr);
            }).toList();

        print('📍 تم جلب ${userAddresses.length} عنوان للمستخدم من Database');
        if (!mounted) return;
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
            _searchError =
                'خدمة البحث غير متاحة حالياً. الرجاء استخدام زر الموقع الحالي.';
            _searchResults = [];
            print(
              '❌ REQUEST_DENIED: ${data['error_message'] ?? "لا توجد رسالة"}',
            );
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
  Future<void> _handleSearchResultTap(dynamic result) async {
    setState(() => _isLoading = true);

    try {
      final placeDetails = await _getPlaceDetails(result['place_id']);

      if (placeDetails != null) {
        await _createAddressFromDetails(placeDetails, null);
      } else {
        _showErrorSnackBar('فشل تحميل تفاصيل المكان');
      }
    } catch (e) {
      print('خطأ في معالجة اختيار العنوان: $e');
      _showErrorSnackBar(
        e is RegionResolutionException ? e.toString() : 'حدث خطأ',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// إنشاء عنوان من التفاصيل
  Future<void> _createAddressFromDetails(
    Map<String, dynamic> addressData,
    String? regionId,
  ) async {
    const city = '';
    final formattedAddress = addressData['formattedAddress'] as String;

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

    await _choosePoint(deliveryAddress, source: 'search');
  }

  /// استخدام الموقع الحالي (GPS)
  Future<void> _useCurrentLocation() async {
    setState(() => _isLoading = true);

    try {
      final hint = await DeviceLocationHint.instance.acquire(
        requestPermission: true,
      );
      if (!mounted) return;
      if (hint == null) {
        _showErrorSnackBar(
          'تعذر تحديد موقع دقيق. ابحث عن العنوان أو اختر منطقتك وحدد النقطة على الخريطة.',
        );
        return;
      }
      print('📍 الموقع: ${hint.latitude}, ${hint.longitude}');

      final deliveryAddress = DeliveryAddress(
        label: 'موقعي الحالي',
        formattedAddress: 'الموقع الحالي',
        latitude: hint.latitude,
        longitude: hint.longitude,
        city: '',
        source: AddressSource.gps,
      );

      // 6. حفظ العنوان
      await _saveAndProceed(deliveryAddress);
    } catch (e) {
      print('خطأ في الحصول على الموقع: $e');
      _showErrorSnackBar(
        e is RegionResolutionException
            ? e.toString()
            : 'فشل تحديد موقعك الحالي',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// حفظ العنوان والانتقال إلى HomeScreen
  Future<void> _saveAndProceed(DeliveryAddress address) async {
    if (_savingSelection) return;
    _savingSelection = true;
    try {
      final result = await RegionResolverService().resolvePoint(
        lat: address.latitude,
        lng: address.longitude,
        throwOnFailure: true,
      );
      if (result == null || !result.effective.isDeliveryAvailable) {
        _showRegionNotSupportedDialog();
        return;
      }
      _currentLocationName = result.region.nameAr;
      await (widget.browsingService ?? BrowsingLocationService.instance).select(
        BrowsingLocation(
          regionId: result.region.id,
          regionName: result.region.nameAr,
          source:
              address.source == AddressSource.saved
                  ? 'saved'
                  : address.source == AddressSource.gps
                  ? 'gps'
                  : 'search',
          latitude: address.latitude,
          longitude: address.longitude,
          addressText: address.formattedAddress,
          savedAddressId:
              address.source == AddressSource.saved ? address.addressId : null,
        ),
      );
      if (address.source == AddressSource.saved) {
        await DeliveryAddressManager.instance.setActiveAddress(address);
      } else {
        DeliveryAddressManager.instance.clearActiveSelection();
      }
      _finishSelection();
    } catch (_) {
      _showErrorSnackBar('تعذر التحقق من المنطقة. أعد المحاولة.');
    } finally {
      _savingSelection = false;
    }
  }

  /// عرض رسالة أن المنطقة غير مخدومة
  void _showRegionNotSupportedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
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
                      border: Border.all(
                        color: Colors.orange[300]!,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Colors.orange[700],
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                              children: [
                                TextSpan(
                                  text: 'أنت في: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.normal,
                                  ),
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
                      Text(
                        'يمكنك تصفح المناطق المفتوحة من قائمة اختيار العنوان.',
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'يرجى اختيار عنوان من المناطق المخدومة باستخدام شريط البحث أو تجربة عنوان آخر.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  foregroundColor: readableForeground(AppColors.primary),
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
      SnackBar(content: Text(message), backgroundColor: Colors.red),
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
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.secondaryDark,
                    ),
                    suffixIcon:
                        _searchController.text.isNotEmpty
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
                child:
                    _searchError != null
                        ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Colors.orange,
                                ),
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
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.blue,
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'يمكنك استخدام زر "موقعي الحالي" للمتابعة',
                                          style: TextStyle(
                                            color: Colors.blue[900],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        : _searchController.text.length > 2 &&
                            _searchResults.isEmpty
                        ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'لا توجد نتائج',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
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
                      style: TextStyle(color: Colors.white, fontSize: 16),
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
              'اختر طريقة تحديد العنوان',
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
                        color: AppColors.secondaryDark,
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
                            'نحدد المنطقة حسب موقع جهازك',
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

            const SizedBox(height: 20),
            const Text(
              'اختيار منطقة',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D2D60),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'اختر منطقتك لعرض المطاعم المتاحة فيها.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE1E6EE)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ActiveRegionTree(
                onSelected: _selectRegion,
                catalog: widget.regionCatalog,
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
              ..._savedAddresses
                  .map((address) => _buildSavedAddressItem(address))
                  .toList(),
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
                child: Icon(Icons.location_on, color: Colors.red, size: 24),
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
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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

  Future<void> _selectRegion(ActiveRegion region) async {
    if (_savingSelection) return;
    LatLng? initial;
    final hint = DeviceLocationHint.instance.recent;
    if (hint != null) {
      try {
        final r = await RegionResolverService().resolvePoint(
          lat: hint.latitude,
          lng: hint.longitude,
          throwOnFailure: true,
        );
        if (r?.region.id == region.id) initial = hint;
      } catch (_) {}
    }
    final selected =
        (widget.browsingService ?? BrowsingLocationService.instance).selection;
    if (initial == null &&
        selected?.regionId == region.id &&
        selected?.hasPoint == true)
      initial = LatLng(selected!.latitude!, selected.longitude!);
    if (initial == null) {
      for (final address in _savedAddresses) {
        if (address.regionId == region.id) {
          initial = LatLng(address.latitude, address.longitude);
          break;
        }
      }
    }
    if (!mounted) return;
    await _choosePoint(
      null,
      source: 'region',
      region: region,
      initial: initial,
    );
  }

  Future<void> _choosePoint(
    DeliveryAddress? address, {
    required String source,
    ActiveRegion? region,
    LatLng? initial,
  }) async {
    if (_savingSelection || _choosingPoint || !mounted) return;
    _choosingPoint = true;
    try {
      final position =
          initial ??
          (address == null
              ? null
              : LatLng(address.latitude, address.longitude));
      LatLngBounds? viewport;
      final bounds = region?.bounds;
      if (position == null && bounds != null) {
        final south = bounds['south'],
            north = bounds['north'],
            west = bounds['west'],
            east = bounds['east'];
        if (south is num && north is num && west is num && east is num)
          viewport = LatLngBounds(
            southwest: LatLng(south.toDouble(), west.toDouble()),
            northeast: LatLng(north.toDouble(), east.toDouble()),
          );
      }
      final result =
          widget.pickPoint != null
              ? await widget.pickPoint!(
                context,
                position,
                region?.name,
                region?.id,
              )
              : await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => LocationPickerScreen(
                        initialPosition: position,
                        initialViewport: viewport,
                        initialAddress: region?.name ?? 'حدد نقطة التوصيل',
                        requiredRegionId: region?.id,
                        requirePinSelection: true,
                      ),
                ),
              );
      if (!mounted || result == null) return;
      final point = result['position'] as LatLng;
      final resolved = result['region'] as RegionResolveResult;
      if (!resolved.effective.isDeliveryAvailable ||
          (region != null && resolved.region.id != region.id))
        return;
      await (widget.browsingService ?? BrowsingLocationService.instance).select(
        BrowsingLocation(
          regionId: resolved.region.id,
          regionName: resolved.region.nameAr,
          source: source,
          latitude: point.latitude,
          longitude: point.longitude,
          addressText:
              source == 'search'
                  ? address?.formattedAddress
                  : resolved.region.nameAr,
        ),
      );
      DeliveryAddressManager.instance.clearActiveSelection();
      _finishSelection();
    } finally {
      _choosingPoint = false;
    }
  }

  void _finishSelection() {
    if (!mounted) return;
    if (widget.showBackButton) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  /// اختيار عنوان محفوظ
  Future<void> _selectSavedAddress(DeliveryAddress address) async {
    setState(() => _isLoading = true);

    try {
      await _saveAndProceed(address);
    } catch (e) {
      print('خطأ في اختيار العنوان المحفوظ: $e');
      _showErrorSnackBar(
        e is RegionResolutionException ? e.toString() : 'فشل تحديد العنوان',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
