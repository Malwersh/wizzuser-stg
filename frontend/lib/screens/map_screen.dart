import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:developer' as developer;
import 'dart:async';

import '../constants/app_colors.dart';
import '../models/business_model.dart';
import '../services/business_service.dart';
import '../config/secure_google_maps_config.dart';
import './store_detail_screen.dart';
import '../models/store.dart';

class MapScreen extends StatefulWidget {
  final List<BusinessModel>? businesses; // قائمة المطاعم المصفاة من الشاشة الرئيسية
  
  const MapScreen({
    super.key,
    this.businesses,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  String _selectedFilter = 'all'; // all, open, highRating
  String _searchQuery = '';
  List<BusinessModel> _allBusinesses = [];
  List<BusinessModel> _filteredBusinesses = [];
  Set<Marker> _markers = {};
  final TextEditingController _searchController = TextEditingController();
  bool _showList = false; // للتبديل بين عرض الخريطة والقائمة
  
  // إحداثيات بغداد الافتراضية
  static const LatLng _defaultLocation = LatLng(33.3128, 44.3615);
  
  // مفاتيح للخريطة
  BitmapDescriptor? _restaurantIcon;
  BitmapDescriptor? _userLocationIcon;

  @override
  void initState() {
    super.initState();
    // استخدام المطاعم الممررة من الشاشة الرئيسية
    if (widget.businesses != null && widget.businesses!.isNotEmpty) {
      _allBusinesses = widget.businesses!;
      _filteredBusinesses = _allBusinesses;
    }
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    try {
      developer.log('🗺️ بدء تهيئة شاشة الخريطة...');
      
      // طباعة حالة إعداد Google Maps
      SecureGoogleMapsConfig.logConfigurationStatus();
      
      // التحقق من صحة مفتاح API
      if (!SecureGoogleMapsConfig.isValidApiKey(SecureGoogleMapsConfig.apiKey)) {
        developer.log('⚠️ تحذير: مفتاح Google Maps API غير صحيح أو مفقود');
        // يمكن عرض رسالة خطأ للمستخدم هنا
      }
      
      // تحميل الأيقونات المخصصة
      await _loadCustomIcons();
      
      // الحصول على الموقع الحالي
      await _getCurrentLocation();
      
      // تحميل المطاعم
      await _loadRestaurants();
      
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
    try {
      // محاولة تحميل الأيقونة المخصصة
      _restaurantIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/icons/cat_rest.png',
      );
      developer.log('✅ تم تحميل أيقونة المطعم المخصصة');
    } catch (e) {
      developer.log('⚠️ لم يتم العثور على الأيقونة المخصصة، استخدام الافتراضية: $e');
      // إذا لم تكن الأيقونة موجودة، استخدم الافتراضية
      _restaurantIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }

    try {
      // استخدم الأيقونة الافتراضية للمستخدم
      _userLocationIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      developer.log('✅ تم تحميل أيقونة المستخدم');
    } catch (e) {
      developer.log('❌ خطأ في تحميل أيقونة المستخدم: $e');
      _userLocationIcon = BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log('⚠️ خدمات الموقع معطلة');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          developer.log('⚠️ تم رفض إذن الموقع');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        developer.log('⚠️ إذن الموقع مرفوض نهائياً');
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition();
      developer.log('📍 تم الحصول على الموقع الحالي: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}');
    } catch (e) {
      developer.log('❌ خطأ في الحصول على الموقع: $e');
    }
  }

  Future<void> _loadRestaurants() async {
    try {
      developer.log('🔄 تحميل المطاعم للخريطة...');
      
      final businessesResponse = await BusinessService.getAllBusinessesWithPagination(
        page: 0,
        limit: 50, // تحميل عدد أكبر للخريطة
      );
      
      setState(() {
        _allBusinesses = businessesResponse.businesses;
        _filteredBusinesses = _allBusinesses;
      });
      
      await _updateMarkers();
      
      developer.log('✅ تم تحميل ${_allBusinesses.length} مطعم على الخريطة');
    } catch (e) {
      developer.log('❌ خطأ في تحميل المطاعم: $e');
    }
  }

  Future<void> _updateMarkers() async {
    final Set<Marker> markers = {};

    // إضافة مطعم الموقع الحالي للمستخدم
    if (_currentPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        icon: _userLocationIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(
          title: 'موقعك الحالي',
          snippet: 'أنت هنا',
        ),
      ));
    }

    // إضافة علامات المطاعم المفلترة
    for (int i = 0; i < _filteredBusinesses.length; i++) {
      final business = _filteredBusinesses[i];
      
      if (business.latitude != null && business.longitude != null) {
        markers.add(Marker(
          markerId: MarkerId(business.id),
          position: LatLng(business.latitude!, business.longitude!),
          icon: _restaurantIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: business.businessName,
            snippet: '${business.deliveryTime} • ${business.businessType}',
          ),
          onTap: () => _showRestaurantBottomSheet(business),
        ));
      }
    }

    setState(() {
      _markers = markers;
    });
  }

  void _showRestaurantBottomSheet(BusinessModel business) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildRestaurantBottomSheet(business),
    );
  }

  Widget _buildRestaurantBottomSheet(BusinessModel business) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // المؤشر العلوي
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // محتوى المطعم
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // صورة واسم المطعم
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey[200],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: business.businessPhotoUrl.isNotEmpty
                              ? Image.network(
                                  business.businessPhotoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.restaurant, size: 40, color: Colors.grey);
                                  },
                                )
                              : const Icon(Icons.restaurant, size: 40, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              business.businessName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              business.businessType,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${business.rating}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  business.deliveryTime,
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // مؤشر حالة المطعم
                            _buildBusinessStatusBadge(business),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // معلومات الرسوم والتوصيل
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.delivery_dining,
                          title: 'رسوم التوصيل',
                          value: '${business.deliveryFee} د.ع',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.shopping_cart,
                          title: 'الحد الأدنى',
                          value: '20000 د.ع', // قيمة افتراضية
                        ),
                      ),
                    ],
                  ),
                  
                  const Spacer(),
                  
                  // زر عرض المطعم
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _navigateToRestaurant(business);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.secondary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'عرض المطعم',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _navigateToRestaurant(BusinessModel business) {
    // استخدام acceptingOrders و isOnline للحكم على حالة المطعم
    final isBusinessOpen = business.isActive && business.acceptingOrders && business.isOnline && !business.isBusy;
    
    final store = Store(
      id: business.id,
      name: business.businessName,
      image: business.businessPhotoUrl,
      logoUrl: business.businessPhotoUrl,
      isOpen: isBusinessOpen,
      fee: '${business.deliveryFee} د.ع',
      rating: '${business.rating}',
      reviews: business.reviewCount?.toString() ?? '',
      distance: _calculateDistance(business),
      time: business.deliveryTime,
      address: business.address,
      category: business.businessType,
      combos: const [],
      sandwiches: const [],
      drinks: const [],
      extras: const [],
      specialties: const [],
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoreDetailScreen(store: store),
      ),
    );
  }

  String _calculateDistance(BusinessModel business) {
    if (_currentPosition == null || business.latitude == null || business.longitude == null) {
      return '';
    }
    
    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      business.latitude!,
      business.longitude!,
    ) / 1000; // تحويل إلى كيلومتر
    
    return '${distance.toStringAsFixed(1)} كم';
  }

  void _applyFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      _filterBusinesses();
    });
    
    _updateMarkers();
  }

  void _filterBusinesses() {
    List<BusinessModel> filtered = _allBusinesses;

    // تطبيق فلتر البحث
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((business) =>
          business.businessName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          business.businessType.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    // تطبيق فلاتر أخرى
    switch (_selectedFilter) {
      case 'open':
        // استخدام جميع حقول الحالة للتأكد من أن المطعم متاح ويستقبل طلبات
        filtered = filtered.where((business) => 
            business.isActive && 
            business.acceptingOrders && 
            business.isOnline && 
            !business.isBusy
        ).toList();
        break;
      case 'rating':
        // ترتيب حسب التقييم (الأعلى أولاً)
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      default:
        // الكل - لا حاجة لفلترة إضافية
        break;
    }

    _filteredBusinesses = filtered;
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _filterBusinesses();
    });
    
    _updateMarkers();
  }

  Widget _buildFilterChips() {
    final filters = [
      {'key': 'all', 'label': 'الكل', 'icon': Icons.restaurant},
      {'key': 'open', 'label': 'مفتوح الآن', 'icon': Icons.schedule},
      {'key': 'rating', 'label': 'حسب التقييم', 'icon': Icons.star},
    ];

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['key'];
          
          return Container(
            margin: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    filter['icon'] as IconData,
                    size: 16,
                    color: isSelected ? Colors.white : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    filter['label'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) => _applyFilter(filter['key'] as String),
              selectedColor: AppColors.primary,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              side: BorderSide(color: AppColors.primary),
              elevation: isSelected ? 2 : 0,
            ),
          );
        },
      ),
    );
  }

  Widget _buildMapView() {
    try {
      return GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _currentPosition != null
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
              : _defaultLocation,
          zoom: SecureGoogleMapsConfig.defaultZoom,
        ),
        markers: _markers,
        myLocationEnabled: _currentPosition != null,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: true,
        buildingsEnabled: true,
        onMapCreated: (GoogleMapController controller) async {
          try {
            _mapController = controller;
            developer.log('✅ تم إنشاء كنترولر الخريطة بنجاح');
            
            // التحرك إلى الموقع الحالي أو الموقع الافتراضي
            final targetLocation = _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : _defaultLocation;
                
            await _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: targetLocation,
                  zoom: SecureGoogleMapsConfig.defaultZoom,
                ),
              ),
            );
          } catch (e) {
            developer.log('❌ خطأ في إعداد كنترولر الخريطة: $e');
          }
        },
      );
    } catch (e) {
      developer.log('❌ خطأ في إنشاء الخريطة: $e');
      // في حالة فشل تحميل الخريطة، اعرض رسالة خطأ
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.map_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'عذراً، لا يمكن تحميل الخريطة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'تحقق من اتصال الإنترنت أو جرب مرة أخرى',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showList = true; // التحويل إلى وضع القائمة
                  });
                },
                icon: const Icon(Icons.list),
                label: const Text('عرض كقائمة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildListView() {
    return Container(
      color: Colors.grey[100],
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 120, bottom: 120), // مساحة للفلاتر والشريط السفلي
        itemCount: _filteredBusinesses.length,
        itemBuilder: (context, index) {
          final business = _filteredBusinesses[index];
          return _buildRestaurantListItem(business);
        },
      ),
    );
  }

  Widget _buildRestaurantListItem(BusinessModel business) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[200],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: business.businessPhotoUrl.isNotEmpty
                ? Image.network(
                    business.businessPhotoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.restaurant, size: 30, color: Colors.grey);
                    },
                  )
                : const Icon(Icons.restaurant, size: 30, color: Colors.grey),
          ),
        ),
        title: Text(
          business.businessName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              business.businessType,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${business.rating}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                const SizedBox(width: 4),
                Text(
                  business.deliveryTime,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                if (_calculateDistance(business).isNotEmpty) ...[
                  Icon(Icons.location_on, color: Colors.grey[600], size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _calculateDistance(business),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: business.isActive ? AppColors.primary : Colors.grey,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            business.isActive ? 'مفتوح' : 'مغلق',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        onTap: () => _navigateToRestaurant(business),
      ),
    );
  }

  List<Widget> _buildMapOverlays() {
    return [
      // زر الموقع الحالي
      Positioned(
        bottom: 120, // رفع الزر أعلى قليلاً لتجنب تداخله مع الشريط السفلي
        left: 16,
        child: FloatingActionButton(
          mini: true,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          onPressed: () {
            if (_currentPosition != null && _mapController != null) {
              _mapController!.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    zoom: SecureGoogleMapsConfig.detailZoom,
                  ),
                ),
              );
            }
          },
          child: const Icon(Icons.my_location),
        ),
      ),
    ];
  }

  Widget _buildToggleBar() {
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.restaurant,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_filteredBusinesses.length} مطعم متاح',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    _getFilterDescription(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showList = !_showList;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _showList ? AppColors.primary : AppColors.secondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showList ? Icons.map : Icons.list,
                        size: 16,
                        color: _showList ? Colors.white : Colors.black,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showList ? 'خريطة' : 'قائمة',
                        style: TextStyle(
                          color: _showList ? Colors.white : Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              SizedBox(height: 16),
              Text(
                'جاري تحميل الخريطة...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // الخريطة أو القائمة
          _showList ? _buildListView() : _buildMapView(),
          
          // شريط البحث والفلاتر العلوي
          SafeArea(
            child: Column(
              children: [
                // شريط البحث
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن المطاعم والأطباق...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                
                // الفلاتر
                _buildFilterChips(),
              ],
            ),
          ),
          
          // تراكبات الخريطة فقط في وضع الخريطة (زر الموقع الحالي)
          if (!_showList) ..._buildMapOverlays(),
          
          // الشريط السفلي للتبديل - يظهر في الحالتين
          _buildToggleBar(),
        ],
      ),
    );
  }

  String _getFilterDescription() {
    switch (_selectedFilter) {
      case 'open':
        return 'المفتوحة الآن فقط';
      case 'rating':
        return 'مرتبة حسب التقييم';
      default:
        return 'جميع المطاعم المتاحة';
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// بناء مؤشر حالة المطعم
  Widget _buildBusinessStatusBadge(BusinessModel business) {
    Color badgeColor;
    String statusText;
    IconData statusIcon;
    
    if (!business.isActive) {
      badgeColor = Colors.grey;
      statusText = 'غير نشط';
      statusIcon = Icons.store_mall_directory_outlined;
    } else if (!business.isOnline) {
      badgeColor = Colors.red;
      statusText = 'غير متاح';
      statusIcon = Icons.wifi_off;
    } else if (!business.acceptingOrders) {
      badgeColor = Colors.orange;
      statusText = 'لا يستقبل طلبات';
      statusIcon = Icons.pause_circle_outline;
    } else if (business.isBusy) {
      badgeColor = Colors.amber;
      statusText = 'مشغول';
      statusIcon = Icons.hourglass_empty;
    } else {
      badgeColor = Colors.green;
      statusText = 'متاح';
      statusIcon = Icons.check_circle_outline;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: badgeColor, size: 14),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: badgeColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
