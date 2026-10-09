import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/region_resolver_service.dart';
import '../services/google_places_service.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final String? initialAddress;
  
  const LocationPickerScreen({
    Key? key,
    this.initialPosition,
    this.initialAddress,
  }) : super(key: key);
  
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedPosition;
  String? _selectedAddress;
  bool _isLoadingRegion = false;
  RegionResolveResult? _resolvedRegion;
  final TextEditingController _searchController = TextEditingController();
  
  // 🔥 Custom Google Places Service
  late final GooglePlacesService _placesService;
  List<PlacePrediction> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition;
    _selectedAddress = widget.initialAddress;
    
    // 🔥 تهيئة Places Service
    _placesService = GooglePlacesService();
    
    // الاستماع لتغييرات البحث
    _searchController.addListener(_onSearchChanged);
    
    // If no initial position, get current location
    if (_selectedPosition == null) {
      _getCurrentLocation();
    }
  }
  
  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounceTimer?.cancel();
    _placesService.dispose();
    super.dispose();
  }
  
  /// � معالج تغيير نص البحث (مع Debouncing)
  void _onSearchChanged() {
    // إلغاء Timer السابق
    _debounceTimer?.cancel();
    
    final query = _searchController.text.trim();
    
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    
    // Debounce: الانتظار 800ms قبل البحث
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _performSearch(query);
    });
  }
  
  /// 🔍 تنفيذ البحث
  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final results = await _placesService.searchPlaces(
        query: query,
        language: 'ar',
        countries: ['iq'], // العراق فقط
      );
      
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      print('❌ خطأ في البحث: $e');
      setState(() {
        _isSearching = false;
      });
      
      if (mounted) {
        _showError('فشل البحث: ${e.toString()}');
      }
    }
  }
  
  /// � معالج اختيار نتيجة بحث
  Future<void> _onPlaceSelected(PlacePrediction prediction) async {
    // إغلاق لوحة المفاتيح
    FocusScope.of(context).unfocus();
    
    setState(() {
      _isSearching = true;
      _searchResults = [];
    });
    
    try {
      // الحصول على تفاصيل المكان
      final details = await _placesService.getPlaceDetails(
        placeId: prediction.placeId,
        language: 'ar',
      );
      
      // 🎯 منطق ذكي: استخدم formattedAddress إذا كان جيداً (بدون Plus Code)
      // وإلا استخدم Reverse Geocoding للحصول على عنوان أفضل
      String finalAddress = details.formattedAddress;
      
      // التحقق من وجود Plus Code في العنوان
      final plusCodeRegex = RegExp(r'[A-Z0-9]{4}\+[A-Z0-9]{2,}');
      final hasPlusCode = plusCodeRegex.hasMatch(details.formattedAddress);
      
      if (hasPlusCode) {
        // العنوان يحتوي على Plus Code - استخدم Reverse Geocoding
        print('⚠️ العنوان يحتوي على Plus Code - نستخدم Reverse Geocoding');
        try {
          final reversedAddress = await _placesService.getAddressFromCoordinates(
            latitude: details.latitude,
            longitude: details.longitude,
            language: 'ar',
          );
          finalAddress = reversedAddress;
          print('✅ عنوان من Reverse Geocoding: $finalAddress');
        } catch (e) {
          print('⚠️ فشل Reverse Geocoding، نستخدم العنوان الأصلي: $e');
        }
      } else {
        print('✅ العنوان جيد (بدون Plus Code) - نستخدمه مباشرة');
      }
      
      // 🔍 طباعة التفاصيل للفحص
      print('📍 تفاصيل المكان المختار من البحث:');
      print('   - formattedAddress: ${details.formattedAddress}');
      print('   - finalAddress: $finalAddress');
      print('   - description: ${prediction.description}');
      
      // تحديث الموقع على الخريطة
      final newPosition = LatLng(details.latitude, details.longitude);
      
      setState(() {
        _selectedPosition = newPosition;
        _selectedAddress = finalAddress; // العنوان من اختيار المستخدم
        _searchController.text = prediction.description;
        _isSearching = false;
      });
      
      // تحريك الكاميرا
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(newPosition, 16),
      );
      
      // التحقق من المنطقة
      _resolveRegion(newPosition);
      
    } catch (e) {
      print('❌ خطأ في الحصول على التفاصيل: $e');
      setState(() {
        _isSearching = false;
      });
      
      if (mounted) {
        _showError('فشل تحديد الموقع: ${e.toString()}');
      }
    }
  }
  
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('خدمة الموقع غير مفعلة');
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('تم رفض صلاحية الموقع');
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        _showError('صلاحية الموقع مرفوضة بشكل دائم');
        return;
      }
      
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _selectedPosition = LatLng(position.latitude, position.longitude);
      });
      
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_selectedPosition!),
      );
      
      // Resolve region for current location
      _resolveRegion(_selectedPosition!);
    } catch (e) {
      _showError('فشل الحصول على الموقع الحالي');
    }
  }
  
  Future<void> _resolveRegion(LatLng position) async {
    setState(() {
      _isLoadingRegion = true;
      _resolvedRegion = null;
    });
    
    try {
      final service = RegionResolverService();
      final result = await service.resolvePoint(
        lat: position.latitude,
        lng: position.longitude,
      );
      
      setState(() {
        _resolvedRegion = result;
        _isLoadingRegion = false;
      });
      
      if (result == null) {
        print('⚠️ 404 من Region API - الموقع غير موجود في جدول H3 Cells');
        print('💡 هذا لا يعني أن المنطقة غير مخدومة - قد تكون مشكلة في تغطية Backend');
      } else if (!result.effective.isActive) {
        print('⚠️ المنطقة غير نشطة: ${result.region.nameAr}');
      } else if (!result.effective.hasDelivery) {
        print('⚠️ خدمة التوصيل غير متوفرة في: ${result.region.nameAr}');
      } else {
        print('✅ المنطقة محددة: ${result.region.nameAr} (${result.region.name})');
        print('✅ خدمة التوصيل متوفرة');
      }
    } catch (e) {
      setState(() {
        _isLoadingRegion = false;
      });
      print('❌ خطأ في تحديد المنطقة: $e');
    }
  }
  
  void _onMapTap(LatLng position) async {
    setState(() {
      _selectedPosition = position;
      _selectedAddress = null; // مسح العنوان القديم
    });
    
    // 🌍 الحصول على العنوان من الإحداثيات
    try {
      final address = await _placesService.getAddressFromCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
        language: 'ar',
      );
      
      setState(() {
        _selectedAddress = address;
      });
      
      print('📍 عنوان من الضغط على الخريطة: $address');
    } catch (e) {
      print('⚠️ فشل الحصول على العنوان من الإحداثيات: $e');
    }
    
    _resolveRegion(position);
  }
  
  /* معطّل مؤقتاً بسبب bug في google_places_flutter
  /// معالج الضغط على نتيجة البحث من القائمة
  void _onPlaceSelected(Prediction prediction) {
    FocusScope.of(context).unfocus();
    print('📍 تم اختيار من القائمة: ${prediction.description}');
    _searchController.text = prediction.description ?? '';
    setState(() {
      _selectedAddress = prediction.description;
    });
  }
  */
  
  void _confirmLocation() {
    if (_selectedPosition == null) {
      _showError('الرجاء اختيار موقع على الخريطة');
      return;
    }
    
    // ❌ منع الحفظ في المناطق غير المخدومة
    if (_resolvedRegion == null) {
      // لا توجد بيانات منطقة - الموقع خارج العراق أو خارج نطاق الخدمة
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('منطقة غير مخدومة'),
            ],
          ),
          content: const Text(
            'العنوان المختار في منطقة غير مخدومة حالياً.\n\n'
            'الرجاء اختيار عنوان مناسب ضمن مناطق الخدمة المتاحة.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('اختيار عنوان آخر'),
            ),
          ],
        ),
      );
      return;
    }
    
    if (!_resolvedRegion!.effective.isActive) {
      // المنطقة موجودة في النظام لكن غير مفعّلة
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('الخدمة غير متوفرة'),
            ],
          ),
          content: Text(
            'الخدمة غير متوفرة حالياً في: ${_resolvedRegion!.region.nameAr}\n\n'
            'الرجاء اختيار عنوان مناسب في منطقة مخدومة.',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('اختيار عنوان آخر'),
            ),
          ],
        ),
      );
      return;
    }
    
    // التحقق من توفر خدمة التوصيل
    if (!_resolvedRegion!.effective.hasDelivery) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: Colors.blue, size: 28),
              SizedBox(width: 12),
              Text('خدمة التوصيل غير متوفرة'),
            ],
          ),
          content: Text(
            'خدمة التوصيل غير متوفرة حالياً في: ${_resolvedRegion!.region.nameAr}\n\n'
            'سيتم توفير الخدمة قريباً. الرجاء اختيار عنوان في منطقة أخرى.',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text('اختيار عنوان آخر'),
            ),
          ],
        ),
      );
      return;
    }
    
    // كل شيء على ما يرام - حفظ عادي
    Navigator.pop(context, {
      'position': _selectedPosition,
      'address': _selectedAddress ?? _searchController.text,
      'region': _resolvedRegion,
    });
  }
  
  void _showError(String message) {
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
        title: const Text('اختيار موقع التوصيل'),
        backgroundColor: const Color(0xFFFF6B35),
      ),
      body: Stack(
        children: [
          // Google Map
          if (_selectedPosition != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _selectedPosition!,
                zoom: 15,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              onTap: _onMapTap,
              markers: _selectedPosition != null
                  ? {
                      Marker(
                        markerId: const MarkerId('selected'),
                        position: _selectedPosition!,
                        draggable: true,
                        // ✅ تحسين سلاسة السحب
                        onDragStart: (position) {
                          // إلغاء أي عملية بحث جارية
                          setState(() {
                            _selectedAddress = null;
                          });
                        },
                        onDrag: (newPosition) {
                          // تحديث الموقع فوراً أثناء السحب (سلاسة أكثر)
                          setState(() {
                            _selectedPosition = newPosition;
                          });
                        },
                        onDragEnd: (newPosition) async {
                          setState(() {
                            _selectedPosition = newPosition;
                          });
                          
                          // الحصول على العنوان من الموقع الجديد
                          try {
                            final address = await _placesService.getAddressFromCoordinates(
                              latitude: newPosition.latitude,
                              longitude: newPosition.longitude,
                              language: 'ar',
                            );
                            setState(() {
                              _selectedAddress = address;
                            });
                            print('📍 عنوان جديد بعد السحب: $address');
                          } catch (e) {
                            print('⚠️ فشل الحصول على العنوان: $e');
                          }
                          
                          _resolveRegion(newPosition);
                        },
                      ),
                    }
                  : {},
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
            ),
          
          // 🔍 Search Bar
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search TextField
                  TextField(
                    controller: _searchController,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن مدينة أو منطقة...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  
                  // Search Results
                  if (_searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final prediction = _searchResults[index];
                          // 🔥 استخدام الوصف الكامل
                          final fullDescription = prediction.description;
                          
                          return ListTile(
                            leading: const Icon(Icons.location_on, color: Color(0xFFFF6B35)),
                            title: Text(
                              fullDescription,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              textDirection: TextDirection.rtl,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _onPlaceSelected(prediction),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Region Info Card
          if (_resolvedRegion != null)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // عنوان "تم اختيار الموقع"
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'تم اختيار الموقع من الخريطة',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // العنوان الكامل
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text(
                          _selectedAddress ?? 'عنوان غير محدد',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      // اسم المنطقة
                      Row(
                        children: [
                          const Text(
                            '📍',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _resolvedRegion!.region.nameAr,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Icon(
                            _resolvedRegion!.effective.isDeliveryAvailable
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: _resolvedRegion!.effective.isDeliveryAvailable
                                ? Colors.green
                                : Colors.red,
                            size: 22,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_resolvedRegion!.effective.isDeliveryAvailable &&
                          _resolvedRegion!.effective.service?.delivery != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: Wrap(
                            spacing: 20,
                            runSpacing: 6,
                            children: [
                              if (_resolvedRegion!.effective.service!.delivery!.baseFee != null)
                                Text(
                                  '💰 رسوم التوصيل: ${_resolvedRegion!.effective.service!.delivery!.baseFee!.toStringAsFixed(0)} د.ع',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              if (_resolvedRegion!.effective.service!.delivery!.minimumOrder != null)
                                Text(
                                  '🛒 الحد الأدنى للطلب: ${_resolvedRegion!.effective.service!.delivery!.minimumOrder!.toStringAsFixed(0)} د.ع',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                !_resolvedRegion!.effective.isActive
                                    ? Icons.block
                                    : Icons.local_shipping_outlined,
                                color: Colors.red,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  !_resolvedRegion!.effective.isActive
                                      ? 'الخدمة غير متوفرة في هذه المنطقة'
                                      : 'خدمة التوصيل غير متوفرة حالياً\nسيتم توفيرها قريباً',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Loading Indicator
          if (_isLoadingRegion)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text('جاري التحقق من المنطقة...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_selectedPosition != null && 
                    _resolvedRegion != null && 
                    _resolvedRegion!.effective.isDeliveryAvailable)
            ? _confirmLocation
            : null,
        backgroundColor: (_selectedPosition != null && 
                          _resolvedRegion != null && 
                          _resolvedRegion!.effective.isDeliveryAvailable)
            ? const Color(0xFFFF6B35)
            : Colors.grey,
        icon: const Icon(Icons.check),
        label: const Text('تأكيد الموقع'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
