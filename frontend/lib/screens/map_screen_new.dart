import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:ui' as ui;

import '../constants/app_colors.dart';
import '../models/business_model.dart';
import '../config/secure_google_maps_config.dart';
import './store_detail_screen.dart';
import './dish_detail_screen.dart';
import '../models/store.dart';
import '../models/dish.dart';
import '../models/product_model.dart';
import '../services/status_polling_service.dart';
import '../services/business_service.dart';
import '../utils/distance_calculator.dart';
import '../services/delivery_address_manager.dart';

/// شاشة الخريطة المحسّنة - تصميم يشبه DoorDash
/// 
/// تعرض المطاعم المصفاة حسب regionId (المنطقة) من العنوان المختار
/// كل مطعم يظهر على الخريطة في موقعه الفعلي حسب latitude و longitude
class MapScreenNew extends StatefulWidget {
  /// المطاعم المصفاة من الشاشة الرئيسية (مصفاة حسب regionId من العنوان المختار)
  /// يجب أن تحتوي كل BusinessModel على latitude و longitude للعرض على الخريطة
  final List<BusinessModel>? businesses;
  
  const MapScreenNew({
    super.key,
    this.businesses,
  });

  @override
  State<MapScreenNew> createState() => _MapScreenNewState();
}

class _MapScreenNewState extends State<MapScreenNew> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  
  // الفلاتر
  String _selectedFilter = 'all'; // all, open, highRating
  String _searchQuery = '';
  double _minRating = 0.0; // 🔥 فلتر التقييم (القيمة الدنيا للتقييم)
  double _tempMinRating = 0.0; // 🔥 قيمة مؤقتة للشريط قبل تطبيق الفلتر
  
  // البيانات
  List<BusinessModel> _allBusinesses = [];
  List<BusinessModel> _filteredBusinesses = [];
  BusinessModel? _selectedBusiness; // المطعم المحدد
  
  // الخريطة
  Set<Marker> _markers = {};
  TextEditingController _searchController = TextEditingController();
  
  // القائمة السفلية القابلة للسحب
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _minSheetSize = 0.15; // 15% من الشاشة (أصغر لإظهار الخريطة)
  double _initialSheetSize = 0.2; // 20% بدايةً (لإظهار الخريطة أكثر)
  double _maxSheetSize = 0.9; // 90% أقصى ارتفاع
  
  // إحداثيات بغداد الافتراضية
  static const LatLng _defaultLocation = LatLng(33.3128, 44.3615);
  
  // الأيقونات
  BitmapDescriptor? _userLocationIcon;
  
  // 🔥 خدمة polling ومستمع لتحديثاتها
  final StatusPollingService _statusPolling = StatusPollingService.instance;
  StreamSubscription<Map<String, dynamic>>? _pollingUpdatesSubscription;
  
  // 🔥 تخزين المنتجات المحملة لكل مطعم لتجنب إعادة التحميل غير الضرورية
  final Map<String, List<dynamic>> _cachedProducts = {};
  final Map<String, bool> _productsLoading = {};
  
  // 🔥 Timer لإعادة فحص المنتجات دورياً (كل 30 ثانية)
  Timer? _productsRefreshTimer;

  @override
  void initState() {
    super.initState();
    // استخدام المطاعم الممررة من الشاشة الرئيسية (مصفاة حسب regionId)
    if (widget.businesses != null && widget.businesses!.isNotEmpty) {
      _allBusinesses = widget.businesses!;
      _filteredBusinesses = _allBusinesses;
      
      // حساب عدد المطاعم التي لديها إحداثيات
      final withCoords = _allBusinesses.where((b) => b.latitude != null && b.longitude != null).length;
      
      developer.log('═══════════════════════════════════════════════════');
      developer.log('🗺️ تم استلام مطاعم من الشاشة الرئيسية (مصفاة حسب المنطقة)');
      developer.log('   إجمالي المطاعم: ${_allBusinesses.length}');
      developer.log('   مطاعم بإحداثيات: $withCoords');
      developer.log('   سيتم عرضها على الخريطة حسب احداثياتها (lat, lng)');
      developer.log('═══════════════════════════════════════════════════');
    } else {
      developer.log('⚠️ لم يتم تمرير مطاعم - الخريطة ستكون فارغة');
    }
    _initializeMap();
    _setupPollingListener();
    _startStatusPolling();
    _startProductsRefreshTimer();
  }

  @override
  void dispose() {
    _pollingUpdatesSubscription?.cancel();
    _productsRefreshTimer?.cancel();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    try {
      developer.log('🗺️ بدء تهيئة شاشة الخريطة...');
      
      SecureGoogleMapsConfig.logConfigurationStatus();
      
      if (!SecureGoogleMapsConfig.isValidApiKey(SecureGoogleMapsConfig.apiKey)) {
        developer.log('⚠️ تحذير: مفتاح Google Maps API غير صحيح');
      }
      
      await _loadCustomIcons();
      await _getCurrentLocation();
      
      // إذا لم يتم تمرير مطاعم، حملها من API
      if (_allBusinesses.isEmpty) {
        developer.log('⚠️ لا توجد مطاعم ممررة - سيتم تحميلها من API');
        // await _loadRestaurants(); // يمكن تفعيله لاحقاً
      }
      
      await _updateMarkers();
      
      setState(() {
        _isLoading = false;
      });
      
      developer.log('✅ تم تهيئة شاشة الخريطة بنجاح');
    } catch (e) {
      developer.log('❌ خطأ في تهيئة شاشة الخريطة: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCustomIcons() async {
    // سيتم إنشاء الأيقونات ديناميكياً حسب نوع المتجر
    // لا حاجة لتحميل أيقونات ثابتة
    try {
      _userLocationIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    } catch (e) {
      _userLocationIcon = BitmapDescriptor.defaultMarker;
    }
  }
  
  /// إنشاء أيقونة مخصصة حسب نوع المتجر (أسلوب DoorDash)
  Future<BitmapDescriptor> _createBusinessTypeIcon(String? businessType, {bool isSelected = false}) async {
    try {
      // اختيار الأيقونة والألوان حسب نوع المتجر
      IconData iconData;
      Color backgroundColor;
      
      switch (businessType?.toLowerCase()) {
        case 'restaurant':
        case 'مطعم':
          iconData = Icons.restaurant;
          backgroundColor = const Color(0xFF000000); // أسود
          break;
        case 'store':
        case 'supermarket':
        case 'grocery':
        case 'متجر':
        case 'سوبر ماركت':
          iconData = Icons.shopping_basket;
          backgroundColor = const Color(0xFF000000); // أسود
          break;
        case 'pharmacy':
        case 'صيدلية':
          iconData = Icons.local_pharmacy;
          backgroundColor = const Color(0xFF000000); // أسود
          break;
        case 'cafe':
        case 'coffee':
        case 'مقهى':
          iconData = Icons.local_cafe;
          backgroundColor = const Color(0xFF000000); // أسود
          break;
        case 'bakery':
        case 'مخبز':
          iconData = Icons.bakery_dining;
          backgroundColor = const Color(0xFF000000); // أسود
          break;
        case 'dessert':
        case 'حلويات':
          iconData = Icons.cake;
          backgroundColor = const Color(0xFF000000); // أسود
          break;
        default:
          iconData = Icons.store;
          backgroundColor = const Color(0xFF000000); // أسود
      }
      
      // حجم أصغر ومناسب
      final double size = isSelected ? 52.0 : 44.0;
      final double iconSize = isSelected ? 24.0 : 20.0;
      
      // رسم الأيقونة
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // رسم الدائرة الخارجية (الخلفية)
      final circlePaint = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        size / 2,
        circlePaint,
      );
      
      // رسم الحدود البيضاء
      if (isSelected) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0;
        
        canvas.drawCircle(
          Offset(size / 2, size / 2),
          size / 2,
          borderPaint,
        );
      }
      
      // رسم الأيقونة الداخلية بلون التطبيق الأساسي
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );
      
      textPainter.text = TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: iconData.fontFamily,
          color: AppColors.primary, // لون التطبيق الأساسي بدلاً من الأبيض
          fontWeight: FontWeight.bold,
        ),
      );
      
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size - textPainter.width) / 2,
          (size - textPainter.height) / 2,
        ),
      );
      
      // تحويل إلى صورة
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      
      return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    } catch (e) {
      developer.log('❌ خطأ في إنشاء أيقونة مخصصة: $e');
      // العودة إلى أيقونة افتراضية
      return isSelected
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition();
    } catch (e) {
      developer.log('❌ خطأ في الحصول على الموقع: $e');
    }
  }

  Future<void> _updateMarkers() async {
    final Set<Marker> markers = {};

    // موقع المستخدم
    if (_currentPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        icon: _userLocationIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ));
    }

    // المطاعم - إنشاء أيقونة مخصصة لكل متجر حسب نوعه
    for (final business in _filteredBusinesses) {
      if (business.latitude != null && business.longitude != null) {
        final isSelected = _selectedBusiness?.id == business.id;
        
        // إنشاء أيقونة مخصصة حسب نوع المتجر (أسلوب DoorDash)
        final icon = await _createBusinessTypeIcon(
          business.businessType.isNotEmpty ? business.businessType : 'restaurant',
          isSelected: isSelected,
        );
        
        markers.add(Marker(
          markerId: MarkerId(business.id),
          position: LatLng(business.latitude!, business.longitude!),
          icon: icon,
          onTap: () => _onRestaurantTapped(business),
        ));
      }
    }

    setState(() {
      _markers = markers;
    });
  }

  void _onRestaurantTapped(BusinessModel business) {
    setState(() {
      _selectedBusiness = business;
      // تصفية القائمة السفلية لإظهار المطعم المحدد فقط
      _filteredBusinesses = [business];
    });
    
    _updateMarkers();
    
    // تحريك الكاميرا للمطعم
    if (business.latitude != null && business.longitude != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(business.latitude!, business.longitude!),
          15.0,
        ),
      );
    }
    
    // توسيع القائمة السفلية قليلاً
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.45,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _resetSelection() {
    setState(() {
      _selectedBusiness = null;
      _filteredBusinesses = _allBusinesses;
      _applyFilters();
    });
    _updateMarkers();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredBusinesses = _allBusinesses.where((business) {
        // البحث
        final matchesSearch = _searchQuery.isEmpty ||
            business.businessName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            business.businessType.toLowerCase().contains(_searchQuery.toLowerCase());

        // الفلاتر
        bool matchesFilter = true;
        switch (_selectedFilter) {
          case 'all':
            // عرض جميع المطاعم
            matchesFilter = true;
            break;
          case 'open':
            // فلتر "مفتوح الآن" - يعرض فقط المطاعم المفتوحة والمستعدة لقبول الطلبات
            matchesFilter = business.isActive && 
                           business.isOnline && 
                           business.acceptingOrders && 
                           !business.isBusy;
            break;
          case 'highRating':
            // 🔥 فلتر التقييم - يستخدم القيمة الدنيا المحددة من الشريط
            matchesFilter = business.rating >= _minRating;
            break;
          default:
            matchesFilter = true;
        }

        return matchesSearch && matchesFilter;
      }).toList();
    });
    
    _updateMarkers();
  }
  
  /// 🔥 إعداد الاستماع لتحديثات polling
  void _setupPollingListener() {
    _pollingUpdatesSubscription = _statusPolling.statusUpdates.listen(
      (update) {
        final businessId = update['businessId'] as String?;
        final isAvailable = update['isAvailable'] as bool?;
        final acceptingOrders = update['acceptingOrders'] as bool?;
        final isWithinWorkingHours = update['isWithinWorkingHours'] as bool?;
        
        if (businessId != null && mounted) {
          developer.log('🔔 Map: استلام تحديث polling للمطعم $businessId');
          developer.log('   - isAvailable: $isAvailable');
          developer.log('   - acceptingOrders: $acceptingOrders');
          developer.log('   - isWithinWorkingHours: $isWithinWorkingHours');
          
          setState(() {
            bool updated = false;
            
            // تحديث في _allBusinesses
            for (int i = 0; i < _allBusinesses.length; i++) {
              if (_allBusinesses[i].id == businessId) {
                // 🔥 تحديث isBusy بشكل صحيح:
                // - إذا isAvailable=false و acceptingOrders=true → مشغول (busy)
                // - إذا isAvailable=true → غير مشغول (not busy)
                // - خلاف ذلك، إبقاء القيمة الحالية
                bool newIsBusy = _allBusinesses[i].isBusy;
                if (isAvailable != null && acceptingOrders != null) {
                  newIsBusy = (isAvailable == false && acceptingOrders == true);
                }
                
                _allBusinesses[i] = _allBusinesses[i].copyWithBusinessStatus(
                  isOnline: isWithinWorkingHours ?? _allBusinesses[i].isOnline,
                  acceptingOrders: acceptingOrders ?? _allBusinesses[i].acceptingOrders,
                  isBusy: newIsBusy,
                );
                updated = true;
                developer.log('✅ Map: تم تحديث بيانات المطعم في _allBusinesses - isBusy: $newIsBusy');
                break;
              }
            }
            
            if (updated) {
              // إعادة تطبيق الفلاتر لتحديث _filteredBusinesses
              _applyFilters();
              
              // 🔥 تحديث الماركرز على الخريطة ليعكس الحالة الجديدة
              // فقط إذا كان فلتر "مفتوح الآن" نشطاً
              if (_selectedFilter == 'open') {
                developer.log('🗺️ Map: تحديث الماركرز بعد تغيير حالة المطعم');
                _updateMarkers();
              }
            }
          });
        }
      },
      onError: (error) {
        developer.log('❌ Map: خطأ في استلام تحديثات polling: $error');
      },
    );
    
    developer.log('✅ Map: تم إعداد مستمع تحديثات polling');
  }
  
  /// 🔥 بدء status polling لجميع المطاعم في الخريطة
  void _startStatusPolling() {
    if (_allBusinesses.isNotEmpty) {
      final businessIds = _allBusinesses.map((b) => b.id).toList();
      developer.log('🚀 Map: بدء status polling لـ ${businessIds.length} مطعم');
      
      _statusPolling.updateWatchedIds(businessIds);
      _statusPolling.start();
      
      developer.log('✅ Map: تم بدء status polling بنجاح');
    } else {
      developer.log('⚠️ Map: لا توجد مطاعم لبدء polling');
    }
  }
  
  /// 🔥 بدء Timer لإعادة فحص المنتجات دورياً
  void _startProductsRefreshTimer() {
    _productsRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      developer.log('🔄 Map: فحص دوري للمنتجات...');
      
      // إعادة فحص المنتجات للمطاعم المعروضة حالياً
      for (final business in _filteredBusinesses) {
        _refreshProductsForBusiness(business.id);
      }
    });
    
    developer.log('✅ Map: تم بدء Timer لفحص المنتجات دورياً (كل 30 ثانية)');
  }
  
  /// 🔥 إعادة تحميل المنتجات لمطعم معين للكشف عن التحديثات
  Future<void> _refreshProductsForBusiness(String businessId) async {
    // تجنب التحميل إذا كان هناك تحميل جاري
    if (_productsLoading[businessId] == true) {
      return;
    }
    
    // إذا لم تكن المنتجات محملة أصلاً، لا نحتاج للفحص
    if (!_cachedProducts.containsKey(businessId)) {
      return;
    }
    
    try {
      developer.log('🔍 Map: فحص تحديثات المنتجات للمطعم $businessId');
      
      // جلب المنتجات الجديدة
      final categoryProducts = await BusinessService.getBusinessCategoriesAndProducts(businessId);
      
      if (!mounted) return;
      
      // جمع جميع المنتجات
      final newProducts = <dynamic>[];
      for (final products in categoryProducts.values) {
        newProducts.addAll(products);
      }
      
      // مقارنة مع المنتجات المخزنة
      final oldProducts = _cachedProducts[businessId] ?? [];
      final hasChanges = _detectProductChanges(oldProducts, newProducts);
      
      if (hasChanges) {
        developer.log('🆕 Map: تم اكتشاف تحديثات في منتجات المطعم $businessId - عرض loading');
        
        // إظهار loading indicator
        setState(() {
          _productsLoading[businessId] = true;
        });
        
        // انتظار قليلاً لإظهار loading indicator
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (!mounted) return;
        
        // تحديث المنتجات
        setState(() {
          _cachedProducts[businessId] = newProducts;
          _productsLoading[businessId] = false;
        });
        
        developer.log('✅ Map: تم تحديث المنتجات للمطعم $businessId');
      } else {
        developer.log('ℹ️ Map: لا توجد تحديثات في المنتجات للمطعم $businessId');
      }
    } catch (e) {
      developer.log('❌ Map: خطأ في فحص تحديثات المنتجات للمطعم $businessId: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              const Text('جاري تحميل الخريطة...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // الخريطة
          _buildMap(),
          
          // شريط البحث والفلاتر
          _buildTopBar(),
          
          // القائمة السفلية القابلة للسحب
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _getInitialMapCenter(),
        zoom: 12.0,
      ),
      markers: _markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      // تفعيل جميع الحركات على الخريطة
      zoomGesturesEnabled: true, // التكبير/التصغير بالأصابع
      scrollGesturesEnabled: true, // السحب
      tiltGesturesEnabled: true, // الميلان
      rotateGesturesEnabled: true, // التدوير
      // إضافة gestureRecognizers لتجنب تعارض مع DraggableScrollableSheet
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(
          () => EagerGestureRecognizer(),
        ),
      },
      onMapCreated: (controller) {
        _mapController = controller;
        // تحريك الكاميرا لتشمل جميع المطاعم
        _fitMapToRestaurants();
      },
      onTap: (_) {
        // عند النقر على الخريطة، إلغاء التحديد
        if (_selectedBusiness != null) {
          _resetSelection();
        }
      },
    );
  }
  
  /// حساب مركز الخريطة الابتدائي بناءً على المطاعم المتاحة
  LatLng _getInitialMapCenter() {
    // إذا كانت هناك مطاعم، احسب المركز من متوسط إحداثياتها
    if (_filteredBusinesses.isNotEmpty) {
      double totalLat = 0;
      double totalLng = 0;
      int validCount = 0;
      
      for (final business in _filteredBusinesses) {
        if (business.latitude != null && business.longitude != null) {
          totalLat += business.latitude!;
          totalLng += business.longitude!;
          validCount++;
        }
      }
      
      if (validCount > 0) {
        final centerLat = totalLat / validCount;
        final centerLng = totalLng / validCount;
        developer.log('🗺️ مركز الخريطة محسوب من $validCount مطعم: ($centerLat, $centerLng)');
        return LatLng(centerLat, centerLng);
      }
    }
    
    // افتراضياً: موقع المستخدم أو بغداد
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    
    return _defaultLocation;
  }
  
  /// تعديل الكاميرا لتشمل جميع المطاعم المصفاة
  Future<void> _fitMapToRestaurants() async {
    if (_mapController == null || _filteredBusinesses.isEmpty) return;
    
    // جمع إحداثيات جميع المطاعم
    final List<LatLng> positions = [];
    
    for (final business in _filteredBusinesses) {
      if (business.latitude != null && business.longitude != null) {
        positions.add(LatLng(business.latitude!, business.longitude!));
      }
    }
    
    if (positions.isEmpty) return;
    
    // حساب الحدود
    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLng = positions.first.longitude;
    double maxLng = positions.first.longitude;
    
    for (final pos in positions) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }
    
    // إضافة padding للحدود
    final southwest = LatLng(minLat, minLng);
    final northeast = LatLng(maxLat, maxLng);
    final bounds = LatLngBounds(southwest: southwest, northeast: northeast);
    
    // تحريك الكاميرا
    await Future.delayed(const Duration(milliseconds: 500)); // انتظار تهيئة الخريطة
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80), // padding 80px
    );
    
    developer.log('✅ تم تعديل الكاميرا لتشمل ${positions.length} مطعم');
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // شريط البحث (حجم أصغر)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            height: 44, // ارتفاع ثابت أصغر
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // زر الرجوع (أصغر)
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                // حقل البحث
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 14),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: const InputDecoration(
                      hintText: 'استكشف',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                const Icon(Icons.search, color: Colors.grey, size: 20),
              ],
            ),
          ),
          
          // الفلاتر (حجم أصغر)
          Container(
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterChipWithCount('مفتوح الآن', Icons.access_time, 'open'),
                const SizedBox(width: 6),
                _buildFilterChip('التقييم', Icons.star, 'highRating'),
                const SizedBox(width: 6),
                _buildFilterChip('الكل', Icons.restaurant, 'all'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon, String filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        // 🔥 إذا كان فلتر التقييم، نفتح Bottom Sheet
        if (filter == 'highRating') {
          _showRatingFilterBottomSheet();
        } else {
          setState(() {
            _selectedFilter = filter;
            _selectedBusiness = null;
            _applyFilters();
            _updateMarkers();
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white, // لون التطبيق الأساسي عند التفعيل
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.black87),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            // 🔥 عرض التقييم المحدد على زر التقييم
            if (filter == 'highRating' && _minRating > 0) ...[
              const SizedBox(width: 4),
              Text(
                '${_minRating.toStringAsFixed(1)}+',
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// 🔥 فلتر مع عداد للمطاعم المفتوحة
  Widget _buildFilterChipWithCount(String label, IconData icon, String filter) {
    final isSelected = _selectedFilter == filter;
    
    // حساب عدد المطاعم المفتوحة الآن
    int openCount = 0;
    if (filter == 'open') {
      openCount = _allBusinesses.where((b) => 
        b.isActive && b.isOnline && b.acceptingOrders && !b.isBusy
      ).length;
    }
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
          _selectedBusiness = null;
          _applyFilters();
          _updateMarkers();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.black87),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (openCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.3) : AppColors.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$openCount',
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.secondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _initialSheetSize,
      minChildSize: _minSheetSize,
      maxChildSize: _maxSheetSize,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // مؤشر السحب
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // القائمة
              Expanded(
                child: _filteredBusinesses.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filteredBusinesses.length,
                        separatorBuilder: (context, index) => const Divider(height: 24),
                        itemBuilder: (context, index) {
                          return _buildRestaurantCard(_filteredBusinesses[index]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    // رسائل مخصصة حسب الفلتر النشط
    String mainMessage;
    String subMessage;
    IconData iconData;
    
    if (_allBusinesses.isEmpty) {
      mainMessage = 'لا توجد مطاعم في هذه المنطقة';
      subMessage = 'جرب تغيير العنوان لمنطقة أخرى';
      iconData = Icons.restaurant;
    } else if (_selectedFilter == 'open' && _filteredBusinesses.isEmpty) {
      // حالة خاصة: لا توجد مطاعم مفتوحة الآن
      mainMessage = 'لا توجد مطاعم مفتوحة الآن';
      subMessage = 'جميع المطاعم مغلقة أو مشغولة حالياً';
      iconData = Icons.access_time_outlined;
    } else {
      mainMessage = 'لا توجد نتائج مطابقة';
      subMessage = 'جرب تغيير الفلاتر أو البحث';
      iconData = Icons.search_off;
    }
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconData, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            mainMessage,
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            subMessage,
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(BusinessModel business) {
    // 🔥 استخدام المنتجات المخزنة بدلاً من FutureBuilder لتجنب إعادة التحميل المستمرة
    final allProducts = _cachedProducts[business.id] ?? [];
    final hasProducts = allProducts.isNotEmpty;
    final isLoading = _productsLoading[business.id] ?? false;
    
    // 🔥 تحميل المنتجات فقط إذا لم تكن محملة مسبقاً ولا يوجد تحميل جاري
    if (!_cachedProducts.containsKey(business.id) && !isLoading) {
      // استخدام SchedulerBinding لتجنب استدعاء setState أثناء build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRestaurantProductsOnce(business.id);
        }
      });
    }
    
    return _buildRestaurantCardContent(business, allProducts, hasProducts, isLoading);
  }
  
  /// 🔥 جلب منتجات المطعم مرة واحدة فقط ومقارنتها مع المخزنة
  Future<void> _loadRestaurantProductsOnce(String businessId) async {
    // تجنب التحميل المتكرر
    if (_productsLoading[businessId] == true) {
      developer.log('⏭️ Map: تحميل جاري بالفعل للمطعم $businessId - تخطي');
      return;
    }
    
    // تجنب إعادة التحميل إذا كانت المنتجات محملة مسبقاً
    if (_cachedProducts.containsKey(businessId)) {
      developer.log('✅ Map: المنتجات محملة مسبقاً للمطعم $businessId - تخطي');
      return;
    }
    
    if (!mounted) return;
    
    setState(() {
      _productsLoading[businessId] = true;
    });
    
    try {
      developer.log('🔄 Map: بدء جلب منتجات المطعم $businessId');
      
      // استخدام نفس الخدمة المستخدمة في store_detail_screen
      final categoryProducts = await BusinessService.getBusinessCategoriesAndProducts(businessId);
      
      if (!mounted) {
        developer.log('⚠️ Map: Widget تم dispose - إلغاء التحميل');
        return;
      }
      
      // جمع جميع المنتجات من كل الفئات
      final allProducts = <dynamic>[];
      for (final products in categoryProducts.values) {
        allProducts.addAll(products);
      }
      
      developer.log('✅ Map: تم تحميل ${allProducts.length} منتج للمطعم $businessId');
      
      setState(() {
        _cachedProducts[businessId] = allProducts;
        _productsLoading[businessId] = false;
      });
    } catch (e) {
      developer.log('❌ خطأ في تحميل منتجات المطعم $businessId: $e');
      
      if (!mounted) return;
      
      setState(() {
        _cachedProducts[businessId] = []; // حفظ قائمة فارغة لتجنب إعادة المحاولة
        _productsLoading[businessId] = false;
      });
    }
  }
  
  /// 🔥 الكشف عن التغييرات في المنتجات (إضافة، حذف، تغيير السعر)
  bool _detectProductChanges(List<dynamic> oldProducts, List<dynamic> newProducts) {
    // إذا كانت المنتجات القديمة فارغة، فهذا أول تحميل
    if (oldProducts.isEmpty && newProducts.isEmpty) return false;
    if (oldProducts.isEmpty && newProducts.isNotEmpty) return true;
    
    // التحقق من تغيير عدد المنتجات
    if (oldProducts.length != newProducts.length) return true;
    
    // إنشاء خريطة للمنتجات القديمة للمقارنة السريعة
    final oldProductsMap = <String, dynamic>{};
    for (final product in oldProducts) {
      final id = product is Map ? (product['id'] ?? '') : (product.id ?? '');
      oldProductsMap[id] = product;
    }
    
    // التحقق من التغييرات في كل منتج
    for (final newProduct in newProducts) {
      final id = newProduct is Map ? (newProduct['id'] ?? '') : (newProduct.id ?? '');
      final oldProduct = oldProductsMap[id];
      
      // منتج جديد
      if (oldProduct == null) return true;
      
      // التحقق من تغيير السعر
      final oldPrice = oldProduct is Map 
          ? ((oldProduct['price'] ?? 0) is int ? (oldProduct['price'] as int).toDouble() : (oldProduct['price'] ?? 0.0))
          : (oldProduct.price ?? 0.0);
      final newPrice = newProduct is Map 
          ? ((newProduct['price'] ?? 0) is int ? (newProduct['price'] as int).toDouble() : (newProduct['price'] ?? 0.0))
          : (newProduct.price ?? 0.0);
      
      if (oldPrice != newPrice) {
        developer.log('🔄 تغيير السعر للمنتج $id: $oldPrice -> $newPrice');
        return true;
      }
      
      // التحقق من تغيير الاسم
      final oldName = oldProduct is Map ? (oldProduct['name'] ?? '') : (oldProduct.name ?? '');
      final newName = newProduct is Map ? (newProduct['name'] ?? '') : (newProduct.name ?? '');
      
      if (oldName != newName) {
        developer.log('🔄 تغيير الاسم للمنتج $id: $oldName -> $newName');
        return true;
      }
    }
    
    return false;
  }
  
  Widget _buildRestaurantCardContent(BusinessModel business, List<dynamic> allProducts, bool hasProducts, bool isLoading) {
    
    return GestureDetector(
      onTap: () {
        final store = _businessToStore(business);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoreDetailScreen(store: store),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedBusiness?.id == business.id 
                ? AppColors.primary 
                : Colors.grey[200]!,
            width: _selectedBusiness?.id == business.id ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // المعلومات الرئيسية
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // اسم المطعم
                  Text(
                    business.businessName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  
                  // التقييم والمسافة
                  Row(
                    children: [
                      Icon(Icons.star, size: 15, color: Colors.orange[700]),
                      const SizedBox(width: 4),
                      Text(
                        business.ratingString,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if ((business.reviewCount ?? 0) > 0) Text(
                        '(${business.reviewCount})',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      // 🔥 عرض المسافة الحقيقية المحسوبة
                      if (_currentPosition != null && 
                          business.latitude != null && 
                          business.longitude != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${_calculateRealDistance(business)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ] else if (business.distance.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${business.distance}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                  // رسوم التوصيل
                  if (business.deliveryFee.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'رسوم التوصيل: ',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        Text(
                          business.deliveryFee,
                          style: TextStyle(
                            fontSize: 14, 
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  
                  // الحالة
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getBusinessStatusColor(business),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getBusinessStatusText(business),
                        style: TextStyle(
                          fontSize: 13,
                          color: _getBusinessStatusColor(business),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // عرض المنتجات (مثل store_detail_screen)
            if (isLoading || hasProducts) ...[
              const Divider(height: 1, thickness: 1),
              const SizedBox(height: 8),
              
              // عنوان القسم
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'الأطباق المتوفرة',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              // كاروسل أفقي للمنتجات أو مؤشر التحميل
              if (isLoading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 3,
                    ),
                  ),
                )
              else
                Container(
                  height: 140,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: (allProducts.length > 5 ? 5 : allProducts.length) + 1, // +1 للسهم
                    itemBuilder: (context, index) {
                      // آخر عنصر هو السهم
                      if (index == (allProducts.length > 5 ? 5 : allProducts.length)) {
                        return _buildViewMoreCard(business);
                      }
                      return _buildCompactProductCard(allProducts[index] as dynamic, business);
                    },
                  ),
                ),
              
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
  
  /// بطاقة "عرض المزيد" مع سهم للانتقال إلى صفحة المطعم
  Widget _buildViewMoreCard(BusinessModel business) {
    return GestureDetector(
      onTap: () {
        final store = _businessToStore(business);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoreDetailScreen(store: store),
          ),
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(left: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'عرض المزيد',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  /// بطاقة منتج مضغوطة (compact) للعرض في الكاروسل الأفقي
  Widget _buildCompactProductCard(dynamic item, BusinessModel business) {
    // التعامل مع ProductModel من API
    final String itemName = item is Map ? (item['name'] ?? '') : (item.name ?? '');
    final String itemId = item is Map ? (item['id'] ?? '') : (item.id ?? '');
    final String itemImage = item is Map ? (item['imageUrl'] ?? '') : (item.image ?? item.imageUrl ?? '');
    final String itemDescription = item is Map ? (item['description'] ?? '') : (item.description ?? '');
    final double itemPrice = item is Map 
        ? ((item['price'] ?? 0) is int ? (item['price'] as int).toDouble() : (item['price'] ?? 0.0))
        : (item.price ?? 0.0);
    
    // 🔥 تحديد إذا كان المطعم متاح أم لا
    final bool isRestaurantAvailable = business.isActive && 
                                       business.isOnline && 
                                       business.acceptingOrders && 
                                       !business.isBusy;
    
    return GestureDetector(
      onTap: isRestaurantAvailable ? () {
        // 🔥 التنقل لشاشة تفاصيل الطبق
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DishDetailScreen(
              dish: Dish(
                id: itemId,
                name: itemName,
                description: itemDescription,
                basePrice: itemPrice,
                imageUrls: [itemImage],
                optionGroups: [], // لا توجد خيارات في الكاروسل
                likesPercent: 0,
                likesCount: 0,
              ),
              storeId: business.id,
              storeName: business.businessName,
              storeAddress: business.address,
              productData: item is ProductModel ? item : null,
            ),
          ),
        );
      } : null,
      child: Opacity(
        opacity: isRestaurantAvailable ? 1.0 : 0.5, // 🔥 تأثير الشفافية
        child: Stack(
          children: [
            Container(
              width: 120,
              margin: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // صورة المنتج
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 120,
                      height: 90,
                      color: Colors.grey[200],
                      child: itemImage.isNotEmpty
                          ? Image.network(
                              itemImage,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.primary.withOpacity(0.3),
                                        AppColors.primary.withOpacity(0.6),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.fastfood,
                                    size: 30,
                                    color: Colors.white,
                                  ),
                                );
                              },
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primary.withOpacity(0.3),
                                    AppColors.primary.withOpacity(0.6),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.fastfood,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 6),
                  
                  // اسم المنتج
                  Text(
                    itemName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const Spacer(),
                  
                  // السعر
                  Text(
                    '${itemPrice.toStringAsFixed(0)} د.ع',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            
            // 🔥 Overlay للمطاعم المغلقة/المشغولة
            if (!isRestaurantAvailable)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getBusinessStatusIcon(business),
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getBusinessStatusText(business),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// 🔥 تحديد أيقونة الحالة
  IconData _getBusinessStatusIcon(BusinessModel business) {
    if (!business.isActive) {
      return Icons.block;
    }
    if (!business.isOnline) {
      return Icons.access_time;
    }
    if (business.isBusy || !business.acceptingOrders) {
      return Icons.pause_circle;
    }
    return Icons.check_circle;
  }
  
  Store _businessToStore(BusinessModel business) {
    return Store(
      id: business.id,
      name: business.businessName,
      image: business.businessPhotoUrl,
      logoUrl: business.businessPhotoUrl,
      rating: business.rating.toStringAsFixed(1),
      fee: business.deliveryFee,
      reviews: business.reviewCount?.toString() ?? '',
      distance: business.distance,
      time: business.deliveryTime,
      averagePreparationMinutes: business.averagePreparationMinutes,
      address: business.address,
      isOpen: business.isActive,
      combos: const [],
      sandwiches: const [],
      drinks: const [],
      extras: const [],
      specialties: const [],
    );
  }
  
  /// 🔥 تحديد لون الحالة بناءً على حالة المطعم الفورية
  Color _getBusinessStatusColor(BusinessModel business) {
    // غير نشط
    if (!business.isActive) {
      return Colors.grey;
    }
    
    // مغلق (خارج ساعات العمل)
    if (!business.isOnline) {
      return Colors.orange[700]!;
    }
    
    // مشغول
    if (business.isBusy || !business.acceptingOrders) {
      return Colors.red[700]!;
    }
    
    // متاح
    return Colors.green[700]!;
  }
  
  /// 🔥 تحديد نص الحالة بناءً على حالة المطعم الفورية
  String _getBusinessStatusText(BusinessModel business) {
    // غير نشط
    if (!business.isActive) {
      return 'معطل';
    }
    
    // مغلق (خارج ساعات العمل)
    if (!business.isOnline) {
      return 'مغلق';
    }
    
    // مشغول
    if (business.isBusy) {
      return 'مشغول';
    }
    
    // لا يستقبل طلبات
    if (!business.acceptingOrders) {
      return 'لا يستقبل طلبات';
    }
    
    // متاح
    return 'مفتوح';
  }
  
  /// 🔥 عرض Bottom Sheet لفلتر التقييم (بتصميم DoorDash)
  void _showRatingFilterBottomSheet() {
    // نسخ القيمة الحالية إلى المؤقتة
    _tempMinRating = _minRating;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.45,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // مؤشر السحب
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  // العنوان
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'التقييم',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  
                  // محتوى الفلتر
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          
                          // عرض التقييم المحدد
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'الحد الأدنى للتقييم',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.star, size: 18, color: AppColors.secondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      _tempMinRating.toStringAsFixed(1),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                    Text(
                                      ' +',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // شريط التقييم (Slider)
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.primary,
                              inactiveTrackColor: Colors.grey[300],
                              thumbColor: AppColors.primary,
                              overlayColor: AppColors.primary.withOpacity(0.2),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: _tempMinRating,
                              min: 0.0,
                              max: 5.0,
                              divisions: 10,
                              onChanged: (double value) {
                                setModalState(() {
                                  _tempMinRating = value;
                                });
                              },
                            ),
                          ),
                          
                          // مؤشرات التقييم
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildRatingLabel('0.0'),
                                _buildRatingLabel('2.5'),
                                _buildRatingLabel('5.0'),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // عدد المطاعم المطابقة
                          Center(
                            child: Text(
                              '${_getMatchingRestaurantsCount(_tempMinRating)} مطعم متاح',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // أزرار الإجراءات
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // زر إعادة التعيين
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _minRating = 0.0;
                                _tempMinRating = 0.0;
                                _selectedFilter = 'all';
                                _applyFilters();
                                _updateMarkers();
                              });
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'إعادة التعيين',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // زر إظهار النتائج
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _minRating = _tempMinRating;
                                _selectedFilter = 'highRating';
                                _applyFilters();
                                _updateMarkers();
                              });
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'إظهار النتائج',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  /// بناء label للتقييم
  Widget _buildRatingLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey[600],
      ),
    );
  }
  
  /// حساب عدد المطاعم المطابقة للتقييم المحدد
  int _getMatchingRestaurantsCount(double minRating) {
    return _allBusinesses.where((b) => b.rating >= minRating).length;
  }
  
  /// 🔥 حساب المسافة الحقيقية بين عنوان المستخدم والمطعم
  String _calculateRealDistance(BusinessModel business) {
    if (business.latitude == null || business.longitude == null) {
      return business.distance.isNotEmpty ? business.distance : '';
    }
    
    // 🔥 الحصول على إحداثيات العنوان المُدخل (وليس الموقع الحالي للجهاز)
    try {
      final addressManager = DeliveryAddressManager.instance;
      final activeAddress = addressManager.activeAddress;
      
      // إذا كان هناك عنوان نشط بإحداثيات
      if (activeAddress != null) {
        final businessLat = business.latitude;
        final businessLng = business.longitude;

        if (businessLat == null || businessLng == null) {
          developer.log('❌ Map: لا توجد إحداثيات للمطعم');
          return business.distance.isNotEmpty ? business.distance : '';
        }

        developer.log('═══════════════════════════════════════════════════');
        developer.log('📍 Map: حساب المسافة للمطعم: ${business.businessName}');
        developer.log('   عنوان المستخدم: (${activeAddress.latitude}, ${activeAddress.longitude})');
        developer.log('   موقع المطعم: ($businessLat, $businessLng)');

        // حساب المسافة بالكيلومترات أولاً
        final distanceKm = DistanceCalculator.calculateDistance(
          lat1: activeAddress.latitude,
          lon1: activeAddress.longitude,
          lat2: businessLat,
          lon2: businessLng,
        );
        
        developer.log('   المسافة الخام: ${distanceKm.toStringAsFixed(3)} كم');
        
        // تنسيق المسافة
        final distance = DistanceCalculator.formatDistance(distanceKm);
        
        developer.log('   ✅ المسافة المنسقة: $distance');
        developer.log('═══════════════════════════════════════════════════');
        
        return distance;
      }
      
      // Fallback: استخدام الموقع الحالي للجهاز إذا لم يكن هناك عنوان
      if (_currentPosition != null) {
        final businessLat = business.latitude;
        final businessLng = business.longitude;

        if (businessLat == null || businessLng == null) {
          developer.log('❌ Map: لا توجد إحداثيات للمطعم للوصول إلى الموقع الحالي');
          return business.distance.isNotEmpty ? business.distance : '';
        }

        developer.log('⚠️ Map: لا يوجد عنوان نشط - استخدام الموقع الحالي للجهاز');

        return DistanceCalculator.calculateAndFormatDistance(
          lat1: _currentPosition!.latitude,
          lon1: _currentPosition!.longitude,
          lat2: businessLat,
          lon2: businessLng,
        );
      }
      
      // إذا لم يكن هناك أي معلومات موقع
      developer.log('❌ Map: لا يوجد موقع متاح لحساب المسافة');
      return business.distance.isNotEmpty ? business.distance : '';
      
    } catch (e) {
      developer.log('❌ Map: خطأ في حساب المسافة: $e');
      return business.distance.isNotEmpty ? business.distance : '';
    }
  }
}
