import 'package:shared_preferences/shared_preferences.dart';
import 'notifications_screen.dart';
import '../services/notification_inbox_service.dart';
import 'dart:developer' as developer;
// lib/screens/home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/constants/app_colors.dart';
import 'package:foodapp_user/models/store.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/services/business_service.dart';
import 'package:foodapp_user/providers/app_state_provider.dart';
import 'package:foodapp_user/models/address_model.dart';
import 'package:foodapp_user/services/address_service.dart';
import 'package:foodapp_user/providers/versioning_providers.dart';
import 'package:foodapp_user/screens/store_detail_screen.dart';
import 'package:foodapp_user/screens/cart_screen.dart';
import 'package:foodapp_user/screens/orders_screen.dart';
import 'package:foodapp_user/screens/order_tracking_screen.dart';
import 'package:foodapp_user/screens/improved_account_screen.dart';
import 'package:foodapp_user/widgets/animated_cart_bar.dart';
import 'package:foodapp_user/widgets/modern_cart_icon.dart';
import 'package:foodapp_user/screens/wallet_transfer_screen.dart';
import 'package:foodapp_user/widgets/enhanced_restaurant_card.dart';
import 'package:foodapp_user/services/websocket_service.dart';
import 'package:foodapp_user/services/session_service.dart';
import 'package:foodapp_user/services/push_notifications_service.dart';
import 'package:foodapp_user/services/status_polling_service.dart';
import '../models/favorites_model.dart';
import 'favorite_stores_screen.dart';
import 'map_screen_new.dart';
import '../widgets/custom_bottom_navigation.dart';
import '../models/platform_promo.dart';
import '../services/order_service.dart';
import '../widgets/promo_floating_card.dart';

// 🆕 Smart Delivery Address System imports
import 'package:foodapp_user/services/delivery_address_manager.dart';
import 'package:foodapp_user/services/restaurant_fetching_service.dart';
import 'package:foodapp_user/models/delivery_address.dart';
import 'package:geolocator/geolocator.dart';
import 'address_gate_screen.dart'; // ✅ لفتح شاشة تغيير العنوان
import '../utils/distance_calculator.dart'; // 🔥 لحساب المسافة الحقيقية

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // البيانات الحقيقية من قاعدة البيانات للقسمين المحددين فقط  
  List<BusinessModel> _newBusinesses = []; // للقسم "وصل حديثاً"
  List<BusinessModel> _allRealBusinesses = []; // للقسم "جميع المطاعم"
  List<BusinessModel> _nearbyBusinesses = []; // للقسم "الأقرب إليك" بناءً على GPS
  bool _isLoadingRealData = false;
  int _realDataPage = 0;
  bool _hasMoreRealData = true;

  // أكواد خصم المنصة (المنصة المركزية)
  PlatformPromo? _visiblePromo;

  // 🛠 تتبع آخر عملية bridge في build() لتجنب إعادة المحاولة بلا نهاية
  int _lastFallbackProviderCount = -1;
  int _lastFallbackAppliedCount = -1;
  
  // 🛡️ تتبع آخر تحديث للبيانات لتجنب استبدالها ببيانات قديمة
  DateTime _lastDataUpdateTime = DateTime.now();
  DateTime _lastAddressChangeTime = DateTime.now(); // تتبع آخر تغيير للعنوان

  // إعدادات البنر الأوتوماتيكي
  late final PageController _bannerController;
  Timer? _bannerTimer;
  int _bannerPage = 0;
  final List<String> _bannerImages = const [
    'assets/images/banner1.png',
    'assets/images/banner2.png',
    'assets/images/banner3.png',
  ];

  // التبويب المحدد في BottomNavigationBar
  int _selectedTabIndex = 0;

  bool _isHandlingPendingPush = false;
  String? _lastHandledPushOrderId;

  // متغيرات الفلاتر
  String _selectedSortOption = 'رتب حسب';
  bool _filterOpenNow = false;
  bool _filterFreeDelivery = false;
  bool _filterOffers = false;

  // العنوان المختار حالياً في الشريط العلوي
  DetailedAddress? _selectedAddress;

  final ScrollController _storesController = ScrollController();
  
  // 🆕 Smart Delivery Address System
  final DeliveryAddressManager _deliveryAddressManager = DeliveryAddressManager.instance;
  StreamSubscription<DeliveryAddress?>? _deliveryAddressSubscription;

  // خدمة WebSocket للحصول على التحديثات الفورية
  final WebSocketService _webSocketService = WebSocketService.instance;
  // خدمة polling صامتة لحالة المطاعم
  final StatusPollingService _statusPolling = StatusPollingService.instance;
  
  // مستمعات WebSocket للتحديثات الفورية
  StreamSubscription? _businessStatusSubscription;
  
  // 🔥 مستمع جديد لتحديثات polling
  StreamSubscription<Map<String, dynamic>>? _pollingUpdatesSubscription;
  
  // 🔥 قائمة الاشتراكات النشطة للمطاعم
  final Map<String, StreamSubscription<Map<String, dynamic>>> _activeBusinessSubscriptions = {};

  @override
  void initState() {
    super.initState();
    NotificationInboxService.instance.load().catchError((Object _) {});
    // مراقبة دورة حياة التطبيق لتفعيل جلب فوري عند العودة للمقدمة
    WidgetsBinding.instance.addObserver(this);
    _bannerController = PageController();
    _setupBannerTimer();
    
    // تهيئة نموذج المفضلة
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final favoritesModel = Provider.of<FavoritesModel>(context, listen: false);
      await favoritesModel.initialize();
    });
    
    // تهيئة WebSocket للحصول على التحديثات الفورية لحالة المطاعم
    _initializeWebSocket();
    
    _initializeSmartDeliveryAddressSystem(); // 🆕 تهيئة نظام العناوين الذكي
    _storesController.addListener(_scrollListener);
    _initializeAddressSystem();

    // بدء خدمة polling الصامتة (ستعمل عند تزويدها بالمعرفات)
    _statusPolling.start();

    // جلب أكواد الخصم الفعالة لعرضها في البطاقة العائمة
    _loadActivePromoCodes();
    
    // 🆕 إضافة listener مباشر على RestaurantListProvider لنقل البيانات فوراً
    // MUST be done IMMEDIATELY in initState (not in postFrameCallback) to catch all notifyListeners()
    try {
      final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('🎯🎯🎯 REGISTERING PROVIDER LISTENER IN HOME_SCREEN');
      debugPrint('📍 Provider instance hashCode: ${restaurantListProvider.hashCode}');
      debugPrint('📍 Current restaurants in Provider: ${restaurantListProvider.restaurants?.length ?? 0}');
      debugPrint('📍 Provider isLoading: ${restaurantListProvider.isLoading}');
      debugPrint('📍 About to call: restaurantListProvider.addListener(_onRestaurantListProviderChanged)');
      
      restaurantListProvider.addListener(_onRestaurantListProviderChanged);
      
      debugPrint('✅✅✅ تم تسجيل listener على RestaurantListProvider في initState SUCCESSFULLY!');
      debugPrint('   Listener function: _onRestaurantListProviderChanged');
      debugPrint('   This listener should be called whenever Provider calls notifyListeners()');
      debugPrint('═══════════════════════════════════════════════════');
      
      // ✅ إذا كان Provider يحتوي على بيانات بالفعل، استدعي Bridge فوراً
      if (restaurantListProvider.restaurants != null && restaurantListProvider.restaurants!.isNotEmpty) {
        debugPrint('⚡ Provider يحتوي على ${restaurantListProvider.restaurants!.length} مطعم بالفعل - تفعيل Bridge فوراً');
        Future.microtask(() => _bridgeProviderBusinessesIfAvailable());
      }
    } catch (e) {
      debugPrint('❌❌❌ ERROR registering RestaurantListProvider listener: $e');
    }

    // 🛠 بدء جدولة استرداد الجسر في حال لم يعمل الـ listener
    _scheduleBridgeRecovery();
    
    // 🔥 الاستماع لتحديثات polling وتحديث UI فوراً
    _listenToPollingUpdates();
    
    // 🆕 تسجيل listener لقائمة المطاعم من Provider
    _setupProviderListener();
    
    // 🆕 بدء polling قائمة المطاعم للتحديثات الفورية
    _startRestaurantListPolling();

    // 🔔 Handle pending navigation from push taps (cold start / resume)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingPushNavigation();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // فحص تغيير المستخدم وإعادة تحميل السلة عند الحاجة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      appState.checkForUserChange();
    });
  }

  /// تهيئة WebSocket للحصول على التحديثات الفورية
  Future<void> _initializeWebSocket() async {
    try {
      developer.log('Home: 🔌 تحضير WebSocket (بدون اتصال تلقائي)...');
      
      // 🚨 FIX: لا نتصل تلقائياً - فقط نفعّل إعادة الاتصال للسماح بالاتصال عند الحاجة
      // WebSocket سيتصل فقط عند تتبع طلب عبر connectForOrder()
      _webSocketService.enableReconnection();
      
      developer.log('Home: ✅ WebSocket جاهز للاتصال عند الحاجة (لن يتصل تلقائياً)');
      
      // الاستماع لتحديثات حالة المطاعم من جميع المطاعم
      _setupBusinessStatusListener();
    } catch (e) {
      developer.log('Home: ❌ خطأ في تحضير WebSocket: $e');
    }
  }

  /// إعداد مستمع لتحديثات حالة المطاعم
  void _setupBusinessStatusListener() {
    // إذا كان هناك اشتراك سابق، قم بإلغاؤه
    _businessStatusSubscription?.cancel();
    
    // تعيين callback للتحديثات العامة لحالة المطاعم
    _webSocketService.onBusinessStatusUpdate = (businessId, isBusy, status) {
      developer.log('Home: تحديث حالة المطعم $businessId: $status (مشغول: $isBusy)');
      _refreshBusinessStatus(businessId, isBusy, status);
    };
    
    // تعيين callback لتحديثات ساعات العمل الفورية
    _webSocketService.onWorkingHoursUpdate = (businessId, weekday, workingHours) {
      developer.log('Home: تحديث ساعات العمل للمطعم $businessId - يوم $weekday');
      _refreshBusinessWorkingHours(businessId, weekday, workingHours);
    };
    
    // تعيين callback لتحديثات عامة للمطعم (تشمل ساعات العمل والحالة)
    _webSocketService.onBusinessUpdate = (businessId, updateData) {
      developer.log('Home: تحديث عام للمطعم $businessId');
      _handleGeneralBusinessUpdate(businessId, updateData);
    };
  }

  /// تحديث حالة مطعم معين في UI
  void _refreshBusinessStatus(String businessId, bool isBusy, String status) {
    if (!mounted) return;
    
    bool uiUpdated = false;
    
    setState(() {
      // تحديث المطاعم الجديدة
      for (int i = 0; i < _newBusinesses.length; i++) {
        if (_newBusinesses[i].id == businessId) {
          _newBusinesses[i] = _newBusinesses[i].copyWithBusinessStatus(
            isBusy: isBusy,
            status: status,
          );
          uiUpdated = true;
          break;
        }
      }
      
      // تحديث جميع المطاعم
      for (int i = 0; i < _allRealBusinesses.length; i++) {
        if (_allRealBusinesses[i].id == businessId) {
          _allRealBusinesses[i] = _allRealBusinesses[i].copyWithBusinessStatus(
            isBusy: isBusy,
            status: status,
          );
          uiUpdated = true;
          break;
        }
      }
      
      // تحديث المطاعم القريبة
      for (int i = 0; i < _nearbyBusinesses.length; i++) {
        if (_nearbyBusinesses[i].id == businessId) {
          _nearbyBusinesses[i] = _nearbyBusinesses[i].copyWithBusinessStatus(
            isBusy: isBusy,
            status: status,
          );
          uiUpdated = true;
          break;
        }
      }
    });
    
    if (uiUpdated) {
      developer.log('Home: تم تحديث واجهة المستخدم للمطعم $businessId');
    }
  }

  /// تحديث ساعات العمل لمطعم معين في UI
  void _refreshBusinessWorkingHours(String businessId, String weekday, Map<String, dynamic> workingHours) async {
    if (!mounted) return;
    
    developer.log('Home: 🕐 تحديث ساعات العمل للمطعم $businessId - يوم $weekday: $workingHours');
    
    // 🔥 إعادة جلب بيانات المطعم الكاملة لإعادة فحص حالة التوفر
    try {
      developer.log('Home: 🔄 إعادة جلب بيانات المطعم $businessId لتحديث حالة التوفر...');
      
      final updatedBusiness = await BusinessService.getBusinessDetails(businessId);
      
      if (updatedBusiness != null && mounted) {
        developer.log('Home: ✅ تم جلب بيانات المطعم المحدثة: ${updatedBusiness.businessName}');
        developer.log('Home: 📊 حالة المطعم الجديدة: open=${updatedBusiness.isOpen}, busy=${updatedBusiness.isBusy}, status=${updatedBusiness.status}');
        
        setState(() {
          // تحديث المطعم في جميع القوائم
          for (int i = 0; i < _newBusinesses.length; i++) {
            if (_newBusinesses[i].id == businessId) {
              _newBusinesses[i] = updatedBusiness;
              developer.log('Home: ✅ تم تحديث المطعم في قائمة "وصل حديثاً"');
              break;
            }
          }
          
          for (int i = 0; i < _allRealBusinesses.length; i++) {
            if (_allRealBusinesses[i].id == businessId) {
              _allRealBusinesses[i] = updatedBusiness;
              developer.log('Home: ✅ تم تحديث المطعم في قائمة "جميع المطاعم"');
              break;
            }
          }
          
          for (int i = 0; i < _nearbyBusinesses.length; i++) {
            if (_nearbyBusinesses[i].id == businessId) {
              _nearbyBusinesses[i] = updatedBusiness;
              developer.log('Home: ✅ تم تحديث المطعم في قائمة "الأقرب إليك"');
              break;
            }
          }
        });
        
        developer.log('Home: 🎉 تم تحديث واجهة المستخدم بساعات العمل الجديدة للمطعم $businessId');
      } else {
        developer.log('Home: ⚠️ فشل جلب بيانات المطعم المحدثة $businessId');
      }
    } catch (e) {
      developer.log('Home: ❌ خطأ في إعادة جلب بيانات المطعم $businessId: $e');
    }
  }

  /// 🆕 تسجيل listener لـ Provider - يُستدعى مرة واحدة في initState
  void _setupProviderListener() {
    developer.log('🎧🎧🎧 Setting up Provider listener...');
    final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
    
    // إضافة listener للتحديثات - سيعمل عند كل تحديث من Provider
    restaurantListProvider.addListener(() {
      developer.log('🔔🔔🔔 Provider LISTENER triggered!');
      developer.log('   mounted: $mounted');
      developer.log('   isLoading: ${restaurantListProvider.isLoading}');
      
      if (mounted && !restaurantListProvider.isLoading) {
        developer.log('🔔 تحديث متاح لقائمة المطاعم - تحديث _allRealBusinesses...');
        
        // 🎯 تحديث _allRealBusinesses مباشرة من Provider
        final rawRestaurants = restaurantListProvider.restaurants;
        developer.log('📊 rawRestaurants count: ${rawRestaurants?.length ?? 0}');
        
        if (rawRestaurants != null && rawRestaurants.isNotEmpty) {
          // 🛡️ Guard: لا نستبدل قائمة حالية أكبر بقائمة أصغر إن كنا في وسط تحميل عنوان جديد أو تحميل مباشر
          if (_isLoadingRealData && _allRealBusinesses.isNotEmpty && rawRestaurants.length < _allRealBusinesses.length) {
            developer.log('🛡️ Provider LISTENER SKIP (loading + smaller list) provider=${rawRestaurants.length} current=${_allRealBusinesses.length}');
            return;
          }
          // 🛡️ Guard: إذا كان العدد نفسه ولا توجد معرفات جديدة، تخطي
          if (_allRealBusinesses.isNotEmpty && rawRestaurants.length == _allRealBusinesses.length) {
            final existingIds = _allRealBusinesses.map((b) => b.id).toSet();
            bool hasNew = false;
            for (final item in rawRestaurants) {
              String? id;
              if (item is BusinessModel) {
                id = item.id;
              } else if (item is Map<String, dynamic>) {
                id = (item['businessId'] ?? item['business_id']) as String?;
              }
              if (id != null && !existingIds.contains(id)) {
                hasNew = true;
                break;
              }
            }
            if (!hasNew) {
              developer.log('🛡️ Provider LISTENER SKIP (same size, no new IDs) size=${rawRestaurants.length}');
              return;
            }
            developer.log('🌉 Provider LISTENER: same size but new IDs detected → proceed');
          }
          final List<BusinessModel> businesses = [];
          for (final item in rawRestaurants) {
            try {
              if (item is BusinessModel) {
                businesses.add(item);
              } else if (item is Map<String, dynamic>) {
                businesses.add(BusinessModel.fromJson(item));
              }
            } catch (e) {
              developer.log('⚠️ خطأ في تحويل مطعم: $e');
            }
          }
          
          if (businesses.isNotEmpty && mounted) {
            developer.log('📝 BEFORE setState from Provider: _allRealBusinesses.length = ${_allRealBusinesses.length}');
            
            setState(() {
              _allRealBusinesses = businesses;
              _isLoadingRealData = false;
              // 🛡️ تحديث وقت آخر تحديث للبيانات
              _lastDataUpdateTime = DateTime.now();
            });
            
            developer.log('📝 AFTER setState from Provider: _allRealBusinesses.length = ${_allRealBusinesses.length}');
            developer.log('✅ تم تحديث _allRealBusinesses بـ ${businesses.length} مطعم من Provider');
            
            // تحديث watched IDs للـ status polling
            _updateStatusPollingWatchedIds();
          }
        } else {
          developer.log('⚠️ Provider has no restaurants or is empty');
        }
      }
    });
    
    developer.log('✅ Provider listener registered successfully');
    
    // 🔥 جلب البيانات الموجودة حالياً في Provider (إن وُجدت)
    developer.log('🔍 Checking for existing data in Provider...');
    final rawRestaurants = restaurantListProvider.restaurants;
    if (rawRestaurants != null && rawRestaurants.isNotEmpty) {
      developer.log('✨ Found existing data: ${rawRestaurants.length} restaurants');
      // تحويل وتطبيق فوراً
      final List<BusinessModel> businesses = [];
      for (final item in rawRestaurants) {
        try {
          if (item is BusinessModel) {
            businesses.add(item);
          } else if (item is Map<String, dynamic>) {
            businesses.add(BusinessModel.fromJson(item));
          }
        } catch (e) {
          developer.log('⚠️ خطأ في تحويل مطعم: $e');
        }
      }
      
      if (businesses.isNotEmpty && mounted) {
        developer.log('📝 Applying existing Provider data to _allRealBusinesses');
        setState(() {
          _allRealBusinesses = businesses;
          _isLoadingRealData = false;
          // 🛡️ تحديث وقت آخر تحديث للبيانات
          _lastDataUpdateTime = DateTime.now();
        });
        developer.log('✅ Applied ${businesses.length} existing restaurants');
        _updateStatusPollingWatchedIds();
      }
    } else {
      developer.log('ℹ️ No existing data in Provider yet');
    }
  }
  
  /// 🆕 بدء polling لقائمة المطاعم للتحديثات الفورية
  void _startRestaurantListPolling() {
    developer.log('🚀🚀🚀 _startRestaurantListPolling CALLED');
    final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
    
    // الحصول على region_id من العنوان النشط
    final activeAddress = _deliveryAddressManager.activeAddress;
    developer.log('📍 activeAddress: ${activeAddress?.formattedAddress}');
    developer.log('🗺️ activeAddress.regionId: ${activeAddress?.regionId}');
    
    if (activeAddress?.regionId != null) {
      developer.log('🆕 بدء polling لقائمة المطاعم - Region: ${activeAddress!.regionId}');
      
      // بدء polling - سيتم استدعاء callback عند وجود تحديث
      restaurantListProvider.startPolling(activeAddress.regionId!);
      
      developer.log('✅ Restaurant list polling بدأ بنجاح');
    } else {
      developer.log('⚠️ لا يوجد regionId - تخطي restaurant list polling');
    }
  }
  
  /// 🆕 Bridge: دمج البيانات مباشرة من Provider عندما يفشل addressStream
  void _bridgeProviderBusinessesIfAvailable() {
    try {
      debugPrint('🌉🌉🌉 BRIDGE: محاولة دمج البيانات من Provider...');
      final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
      final rawRestaurants = restaurantListProvider.restaurants;
      if (rawRestaurants == null || rawRestaurants.isEmpty) {
        debugPrint('🌉 BRIDGE: لا توجد بيانات في Provider (restaurants = ${rawRestaurants?.length ?? 0})');
        return;
      }
      // 🛡️ Guard: لا نستبدل قائمة حالية أكبر بقائمة أصغر من الـ Provider
      if (_allRealBusinesses.isNotEmpty && rawRestaurants.length < _allRealBusinesses.length) {
        debugPrint('🛡️ BRIDGE: SKIP — provider count (${rawRestaurants.length}) < current UI count (${_allRealBusinesses.length})');
        return;
      }
      // 🛡️ Guard 2: إذا كانت القائمة الحالية تحتوي على نفس عدد العناصر ولكن معرفات مختلفة، نتحقق إن كان الـ Provider يحتوي على عناصر جديدة
      if (_allRealBusinesses.isNotEmpty && rawRestaurants.length == _allRealBusinesses.length) {
        final currentIds = _allRealBusinesses.map((b) => b.id).toSet();
        bool providerHasNew = false;
        for (final item in rawRestaurants) {
          String? id;
          if (item is BusinessModel) {
            id = item.id;
          } else if (item is Map<String, dynamic>) {
            id = (item['businessId'] ?? item['business_id']) as String?;
          }
          if (id != null && !currentIds.contains(id)) {
            providerHasNew = true;
            break;
          }
        }
        if (!providerHasNew) {
          debugPrint('🛡️ BRIDGE: SKIP — provider has no new IDs compared to current UI list');
          return;
        }
        debugPrint('🌉 BRIDGE: provider has new IDs — proceeding with merge');
      }
      debugPrint('🌉 BRIDGE: وجدنا ${rawRestaurants.length} عنصر في Provider - جاري التحويل...');
      final List<BusinessModel> convertedBusinesses = [];
      for (int i = 0; i < rawRestaurants.length; i++) {
        final item = rawRestaurants[i];
        try {
          if (item is BusinessModel) {
            convertedBusinesses.add(item);
            debugPrint('🌉 BRIDGE: [${i + 1}/${rawRestaurants.length}] عنصر موجود كـ BusinessModel: ${item.businessName}');
          } else if (item is Map<String, dynamic>) {
            debugPrint('🧪 RAW MAP KEYS (${i + 1}): ${item.keys.join(', ')}');
            debugPrint('🧪 RAW businessId=${item['businessId'] ?? item['business_id']} businessName=${item['businessName'] ?? item['business_name']}');
            final business = BusinessModel.fromJson(item);
            convertedBusinesses.add(business);
            debugPrint('🌉 BRIDGE: تم تحويل ${business.businessName} (ID: ${business.id})');
          } else {
            debugPrint('⚠️ BRIDGE: نوع غير معروف: ${item.runtimeType}');
          }
        } catch (e) {
          debugPrint('❌ BRIDGE: خطأ في تحويل عنصر ${i + 1}: $e');
        }
      }
      if (convertedBusinesses.isEmpty) {
        debugPrint('⚠️ BRIDGE: لم نتمكن من تحويل أي مطاعم');
        return;
      }
      debugPrint('✅ BRIDGE: تم تحويل ${convertedBusinesses.length} مطعم بنجاح');
      if (!mounted) {
        debugPrint('❌ BRIDGE: Widget unmounted - إلغاء التحديث');
        return;
      }
      setState(() {
        _allRealBusinesses = convertedBusinesses;
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        _newBusinesses = convertedBusinesses.where((b) {
          final createdAt = b.metadata?['createdAt'];
          if (createdAt is int) {
            return DateTime.fromMillisecondsSinceEpoch(createdAt).isAfter(thirtyDaysAgo);
          }
          return false;
        }).take(10).toList();
        _isLoadingRealData = false;
        _hasMoreRealData = convertedBusinesses.length >= 20;
      });
      debugPrint('🎉 BRIDGE: تم تحديث UI بـ ${_allRealBusinesses.length} مطعم');
      for (var i = 0; i < _allRealBusinesses.length; i++) {
        debugPrint('   • ${_allRealBusinesses[i].businessName} (ID: ${_allRealBusinesses[i].id})');
      }
      _updateStatusPollingWatchedIds();
      _statusPolling.forceImmediateFetch();
    } catch (e, stackTrace) {
      debugPrint('❌ BRIDGE: فشل الدمج: $e');
      debugPrint('Stack: $stackTrace');
    }
  }

  // 🛠 جدولة استرداد دورية للجسر حتى ينجح (مثلاً حالة عدم استدعاء listener)
  void _scheduleBridgeRecovery() {
    int attempts = 0;
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final provider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
      final count = provider.restaurantCount;
      if (count > 0 && _allRealBusinesses.length != count) {
        debugPrint('🛠 Recovery bridge attempt ${attempts + 1} - provider=$count local=${_allRealBusinesses.length}');
        _bridgeProviderBusinessesIfAvailable();
        attempts++;
        if (attempts >= 5) {
          debugPrint('🛑 إيقاف recovery بعد 5 محاولات');
          timer.cancel();
        }
      } else if (count > 0 && _allRealBusinesses.length == count) {
        debugPrint('✅ Recovery: الأعداد متطابقة (count=$count) - إيقاف الجدولة');
        timer.cancel();
      }
    });
  }

  /// معالجة التحديثات العامة للمطعم (تشمل ساعات العمل والحالة)
  void _handleGeneralBusinessUpdate(String businessId, Map<String, dynamic> updateData) {
    if (!mounted) return;
    
    developer.log('Home: معالجة تحديث عام للمطعم $businessId: $updateData');
    
    // تحديث حالة المطعم إذا تم تضمينها
    if (updateData.containsKey('isBusy') && updateData.containsKey('status')) {
      _refreshBusinessStatus(
        businessId, 
        updateData['isBusy'] as bool, 
        updateData['status'] as String,
      );
    }
    
    // تحديث ساعات العمل إذا تم تضمينها
    if (updateData.containsKey('workingHours')) {
      final workingHours = updateData['workingHours'] as Map<String, dynamic>;
      workingHours.forEach((weekday, hours) {
        if (hours is Map<String, dynamic>) {
          _refreshBusinessWorkingHours(businessId, weekday, hours);
        }
      });
    }
  }

  /// 🆕 تهيئة نظام العناوين الذكي Smart Delivery Address System
  Future<void> _initializeSmartDeliveryAddressSystem() async {
    developer.log('🆕 تهيئة Smart Delivery Address System...');
    
    try {
      // تحديد نوع المستخدم
      final isRegistered = SessionService.instance.isLoggedIn;
      final userId = SessionService.instance.currentUserId;
      
      developer.log('👤 نوع المستخدم: ${isRegistered ? "مسجل" : "ضيف"}');
      
      // تهيئة DeliveryAddressManager
      await _deliveryAddressManager.initializeDeliveryAddress(
        userId: userId,
        isRegisteredUser: isRegistered,
      );

      // 🔥 تحميل أولي مباشرة إذا توفّر عنوان نشط بالفعل
      try {
        final initialAddress = _deliveryAddressManager.activeAddress ?? await _deliveryAddressManager.getActiveAddress();
        if (mounted && initialAddress != null) {
          developer.log('🚀 Found initial active address — loading businesses and starting polling');
          await _onActiveAddressAvailable(initialAddress);
        } else {
          developer.log('ℹ️ No initial address yet — waiting for stream event');
        }
      } catch (e) {
        developer.log('⚠️ Initial active address fetch failed: $e');
      }
      
      // الاستماع لتغييرات العنوان
      developer.log('═══════════════════════════════════════════════════');
      developer.log('👂👂👂 CRITICAL: تسجيل listener على addressStream...');
      developer.log('   DeliveryAddressManager hashCode: ${_deliveryAddressManager.hashCode}');
      developer.log('   addressStream hashCode: ${_deliveryAddressManager.addressStream.hashCode}');
      developer.log('   Widget mounted: $mounted');
      developer.log('   Timestamp: ${DateTime.now().toIso8601String()}');
      developer.log('═══════════════════════════════════════════════════');
      
      _deliveryAddressSubscription = _deliveryAddressManager.addressStream.listen(
        (deliveryAddress) {
          developer.log('═══════════════════════════════════════════════════');
          developer.log('🔔🔔🔔 EVENT RECEIVED في addressStream.listen!');
          developer.log('🎯 BREAKTHROUGH: Listener is working!');
          developer.log('📍 تحديث عنوان التوصيل: ${deliveryAddress?.displayName ?? "لا يوجد"}');
          developer.log('   regionId: ${deliveryAddress?.regionId}');
          developer.log('   formattedAddress: ${deliveryAddress?.formattedAddress}');
          developer.log('   latitude: ${deliveryAddress?.latitude}');
          developer.log('   longitude: ${deliveryAddress?.longitude}');
          developer.log('   mounted: $mounted');
          developer.log('   timestamp: ${DateTime.now().toIso8601String()}');
          developer.log('═══════════════════════════════════════════════════');
          
          // استخدام Future.microtask لتأجيل المعالجة
          if (mounted) {
            final emittedAddress = deliveryAddress;
            Future.microtask(() async {
              developer.log('⚡⚡⚡ Future.microtask executing - mounted: $mounted');
              if (!mounted) {
                developer.log('❌ Widget unmounted in microtask');
                return;
              }
              if (emittedAddress != null) {
                developer.log('✅✅✅ عنوان موجود - استدعاء _onActiveAddressAvailable');
                developer.log('   العنوان: ${emittedAddress.displayName}');
                developer.log('   regionId: ${emittedAddress.regionId}');
                await _onActiveAddressAvailable(emittedAddress);
              } else {
                // 🆕 Fallback: لا يوجد عنوان - جلب جميع المطاعم
                developer.log('⚠️ لا يوجد عنوان توصيل - جلب جميع المطاعم');
                _loadAllBusinessesWithoutAddress();
              }
            });
          } else {
            developer.log('❌❌❌ Widget not mounted - ignoring event');
          }
        },
        onError: (error, stackTrace) {
          developer.log('❌❌❌ ERROR in addressStream listener!');
          developer.log('   Error: $error');
          developer.log('   StackTrace: $stackTrace');
          developer.log('⚠️ لن نستدعي _loadAllBusinessesWithoutAddress في onError - نحتفظ بالبيانات الحالية');
          // ❌ تم تعطيل: لا نستدعي _loadAllBusinessesWithoutAddress هنا
          // لأنه قد يتجاوز العنوان المختار ويملأ _nearbyBusinesses بمطاعم GPS
        },
        onDone: () {
          developer.log('⚠️⚠️⚠️ addressStream listener DONE (stream closed)');
          developer.log('   This means the stream was closed unexpectedly');
        },
        cancelOnError: false,
      );
      
      developer.log('═══════════════════════════════════════════════════');
      developer.log('✅✅✅ Listener registered successfully!');
      developer.log('   Subscription hashCode: ${_deliveryAddressSubscription?.hashCode}');
      developer.log('   DeliveryAddressManager hashCode: ${_deliveryAddressManager.hashCode}');
      developer.log('   Ready to receive address events');
      developer.log('═══════════════════════════════════════════════════');
      
      // 🆕 Safety fallback: بعد ثانية واحدة، تحقق من أن البيانات موجودة
      // إذا لم يتم تحميل أي شيء، استخدم bridge لجلب البيانات من Provider
      Future.delayed(const Duration(seconds: 3), () {
        developer.log('⏰⏰⏰ SAFETY CHECK TRIGGERED at ${DateTime.now()}');
        if (!mounted) {
          developer.log('❌ SAFETY: Widget not mounted');
          return;
        }
        
        developer.log('🔍 SAFETY CHECK: فحص حالة البيانات بعد 3 ثواني...');
        developer.log('   _allRealBusinesses.length = ${_allRealBusinesses.length}');
        developer.log('   _isLoadingRealData = $_isLoadingRealData');
        developer.log('   mounted = $mounted');
        
        if (_allRealBusinesses.isEmpty && !_isLoadingRealData) {
          developer.log('⚠️⚠️⚠️ SAFETY: لا توجد بيانات بعد 3 ثواني - تفعيل bridge fallback');
          _bridgeProviderBusinessesIfAvailable();
        } else {
          developer.log('✅ SAFETY: البيانات موجودة بالفعل - لا حاجة لـ bridge');
        }
      });
      
      developer.log('✅ تم تهيئة Smart Delivery Address System');
    } catch (e) {
      developer.log('❌ خطأ في تهيئة Smart Delivery Address System: $e');
      // fallback: استخدام الطريقة القديمة
      _loadRealBusinessData();
    }
  }

  /// 🧭 التعامل عند توفر عنوان نشط: إعادة تشغيل polling وجلب المطاعم للقائمة الرئيسية
  Future<void> _onActiveAddressAvailable(DeliveryAddress address) async {
    if (!mounted) return;

    developer.log('🧭 Handling active address change -> regionId=${address.regionId}');

    // 🛡️ تسجيل وقت تغيير العنوان لحماية Fallback Bridge
    _lastAddressChangeTime = DateTime.now();
    developer.log('⏰ تم تسجيل وقت تغيير العنوان: $_lastAddressChangeTime');
    
    // أعد تشغيل polling لقائمة المطاعم بناءً على regionId الجديد
    try {
      final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
      restaurantListProvider.stopPolling();
      if (address.regionId != null && address.regionId!.isNotEmpty) {
        developer.log('🔁 Restarting restaurant list polling for region ${address.regionId}');
        restaurantListProvider.startPolling(address.regionId!);
      } else {
        developer.log('⚠️ Address has no regionId — skipping provider polling restart');
      }
    } catch (e) {
      developer.log('⚠️ Failed to restart provider polling: $e');
    }

    // جلب المطاعم عبر خدمة الجلب الذكية (تشمل توسعة الجيران عند الحاجة)
    try {
      await _loadBusinessesByDeliveryAddress(address);
    } catch (e) {
      developer.log('⚠️ Failed to load businesses by address: $e');
    }
  }
  
  /// 🆕 جلب المطاعم بناءً على عنوان التوصيل - REWRITTEN
  Future<void> _loadBusinessesByDeliveryAddress(DeliveryAddress deliveryAddress) async {
    developer.log('═══════════════════════════════════════════════════');
    developer.log('🚀🚀🚀 START: _loadBusinessesByDeliveryAddress');
    developer.log('⏰ Timestamp: ${DateTime.now().toIso8601String()}');
    developer.log('📍 العنوان: ${deliveryAddress.displayName}');
    developer.log('🗺️ Region ID: ${deliveryAddress.regionId}');
    developer.log('🎯 TESTING: This is the main data loading function!');
    developer.log('═══════════════════════════════════════════════════');
    
    if (!mounted) {
      developer.log('❌ Widget unmounted - ABORT');
      return;
    }
    
    // 🛡️ GUARD: منع الطلبات المتعددة المتزامنة
    if (_isLoadingRealData) {
      developer.log('⚠️ GUARD: طلب قيد التنفيذ بالفعل - تخطي هذا الطلب');
      return;
    }
    
    setState(() {
      _isLoadingRealData = true;
      // 🔄 لا نقوم بمسح القوائم مباشرةً لتجنب سباق يستبدل قائمة أكبر بقائمة أصغر من Provider
      // سيتم الاستبدال فقط بعد نجاح الجلب الجديد
    });
    
    try {
      // ✅ استدعاء API بناءً على العنوان/المنطقة
      developer.log('📡 استدعاء API: fetchRestaurantsByDeliveryAddress');
      final response = await RestaurantFetchingService.instance.fetchRestaurantsByDeliveryAddress(
        deliveryAddress: deliveryAddress,
        page: 0,
        limit: 50, // زيادة الحد لجلب جميع المطاعم
      );
      
      developer.log('📥 استجابة API: ${response.businesses.length} مطعم');
      
      // ✅ تحويل البيانات إلى BusinessModel
      List<BusinessModel> allBusinesses = [];
      
      developer.log('🔍🔍🔍 START PARSING LOOP: ${response.businesses.length} items');
      
      for (var i = 0; i < response.businesses.length; i++) {
        try {
          final item = response.businesses[i];
          
          // Check if item is already BusinessModel or Map
          if (item is BusinessModel) {
            developer.log('🔄 [${i + 1}/${response.businesses.length}] ALREADY BusinessModel: ${item.businessName}');
            allBusinesses.add(item);
            developer.log('   ✅ ADDED DIRECTLY');
            continue;
          }
          
          final businessName = item['businessName'] ?? item['business_name'] ?? 'غير معروف';
          final businessId = item['businessId'] ?? item['business_id'] ?? 'لا يوجد';
          
          developer.log('🔄 [${i + 1}/${response.businesses.length}] Parsing MAP: $businessName (ID: $businessId)');
          developer.log('   📋 Item type: ${item.runtimeType}');
          developer.log('   📋 Item keys: ${(item as Map).keys.take(10).join(", ")}...');
          
          final business = BusinessModel.fromJson(item as Map<String, dynamic>);
          allBusinesses.add(business);
          
          developer.log('   ✅ SUCCESS - Added to list (total now: ${allBusinesses.length})');
        } catch (e, stackTrace) {
          final item = response.businesses[i];
          final businessName = item is Map ? (item['businessName'] ?? item['business_name'] ?? 'غير معروف') : 'غير معروف';
          final businessId = item is Map ? (item['businessId'] ?? item['business_id'] ?? 'لا يوجد') : 'لا يوجد';
          developer.log('   ❌ FAILED: $businessName (ID: $businessId)');
          developer.log('   💥 Error: $e');
          developer.log('   📋 Stack trace:');
          developer.log('      ${stackTrace.toString().split('\n').take(5).join('\n      ')}');
          continue; // تخطي المطعم الذي فشل
        }
      }
      
      developer.log('🔍🔍🔍 END PARSING LOOP: ${allBusinesses.length} items added');
      
      developer.log('═══════════════════════════════════════════════════');
      developer.log('✅ PARSING COMPLETE: ${allBusinesses.length} مطعم');
      developer.log('═══════════════════════════════════════════════════');
      
      // ✅ حساب المطاعم الجديدة (آخر 30 يوم)
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final newBusinesses = allBusinesses.where((b) {
        final createdAt = b.metadata?['createdAt'];
        if (createdAt is int) {
          return DateTime.fromMillisecondsSinceEpoch(createdAt).isAfter(thirtyDaysAgo);
        }
        return false;
      }).take(10).toList();
      
      developer.log('🆕 مطاعم جديدة: ${newBusinesses.length}');
      
      if (!mounted) {
        developer.log('❌ Widget unmounted before setState - ABORT');
        return;
      }
      
      // ✅ تحديث الحالة
      developer.log('📝 BEFORE setState: _allRealBusinesses.length = ${_allRealBusinesses.length}');
      
      setState(() {
        _allRealBusinesses = allBusinesses;
        _newBusinesses = newBusinesses;
        _nearbyBusinesses = []; // إفراغ تماماً - نعتمد فقط على _allRealBusinesses
        _isLoadingRealData = false;
        _hasMoreRealData = allBusinesses.length >= 50;
        _realDataPage = 0;
        // 🛡️ تحديث وقت آخر تحديث للبيانات
        _lastDataUpdateTime = DateTime.now();
      });
      
      developer.log('📝 AFTER setState: _allRealBusinesses.length = ${_allRealBusinesses.length}');
      developer.log('═══════════════════════════════════════════════════');
      developer.log('✅✅✅ STATE UPDATED SUCCESSFULLY:');
      developer.log('   _allRealBusinesses: ${_allRealBusinesses.length} مطعم');
      developer.log('   _newBusinesses: ${_newBusinesses.length} مطعم');
      developer.log('   _nearbyBusinesses: ${_nearbyBusinesses.length} مطعم (MUST BE 0)');
      developer.log('   ⏰ Timestamp: ${DateTime.now().toIso8601String()}');
      
      // ✅ طباعة تفاصيل كل مطعم
      for (int i = 0; i < _allRealBusinesses.length; i++) {
        final b = _allRealBusinesses[i];
        developer.log('   ✅ [${i + 1}] ${b.businessName}');
        developer.log('       ID: ${b.id}');
        developer.log('       isActive: ${b.isActive}');
        developer.log('       hasPhoto: ${b.businessPhotoUrl.isNotEmpty}');
      }
      developer.log('═══════════════════════════════════════════════════');
      
      // ✅ تحديث status polling
      developer.log('🔄 Calling _updateStatusPollingWatchedIds with ${_allRealBusinesses.length} businesses...');
      _updateStatusPollingWatchedIds();
      _statusPolling.forceImmediateFetch();
      
      developer.log('🎯🎯🎯 DONE: _loadBusinessesByDeliveryAddress - SUCCESS!');
      developer.log('   Final _allRealBusinesses.length = ${_allRealBusinesses.length}');
      developer.log('   ⏰ Completed at: ${DateTime.now().toIso8601String()}');
      developer.log('═══════════════════════════════════════════════════');
    } catch (e) {
      developer.log('❌ خطأ في جلب المطاعم: $e');
      if (mounted) {
        setState(() {
          _isLoadingRealData = false;
        });
      }
    }
  }
  
  /// 🆕 إعادة جلب المطاعم عند تغيير العنوان من AddressDropdown
  /// ✅ إعادة تحميل المطاعم بعد تغيير العنوان من AddressGateScreen
  Future<void> _reloadBusinessesAfterAddressChange() async {
    developer.log('🚀🚀🚀 ENTRY RELOAD: _reloadBusinessesAfterAddressChange');
    developer.log('🔄 إعادة تحميل المطاعم بعد تغيير العنوان...');
    
    if (!mounted) return;
    
    try {
      // الحصول على العنوان النشط الجديد
      final activeAddress = await _deliveryAddressManager.getActiveAddress();
      
      if (activeAddress == null) {
        developer.log('❌ لا يوجد عنوان نشط');
        return;
      }
      
      developer.log('📍 العنوان الجديد: ${activeAddress.formattedAddress}');
      developer.log('🏘️ Region ID: ${activeAddress.regionId ?? "غير محدد"}');
      
      // استخدام method الموجودة لجلب المطاعم
      await _loadBusinessesByDeliveryAddress(activeAddress);
      
      developer.log('✅ تم تحديث المطاعم بنجاح');
      
    } catch (e) {
      developer.log('❌ خطأ في إعادة تحميل المطاعم: $e');
    }
  }
  
  /// 🆕 جلب المطاعم بناءً على موقع الجهاز GPS (إلزامي)
  Future<void> _loadAllBusinessesWithoutAddress() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingRealData = true;
    });
    
    try {
      developer.log('🔄 جلب المطاعم بناءً على موقع الجهاز GPS...');
      
      // الحصول على موقع الجهاز (إلزامي)
      Position? position;
      try {
        // التحقق من إذن الموقع
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission != LocationPermission.denied && 
            permission != LocationPermission.deniedForever) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(Duration(seconds: 10));
          
          developer.log('📍 تم الحصول على الموقع: ${position.latitude}, ${position.longitude}');
        } else {
          developer.log('❌ إذن الموقع مرفوض');
        }
      } catch (e) {
        developer.log('❌ فشل الحصول على الموقع: $e');
      }
      
      if (position != null) {
        // ✅ جلب المطاعم القريبة بناءً على GPS
        developer.log('🎯 جلب المطاعم القريبة (20 كم)...');
        
        final businesses = await BusinessService.getNearbyBusinesses(
          userLatitude: position.latitude,
          userLongitude: position.longitude,
          maxDistanceKm: 20.0,
          limit: 20,
        );
        
        developer.log('✅ تم جلب ${businesses.length} مطعم قريب');
        
        // جلب المطاعم الجديدة من نفس المنطقة
        final newBusinesses = businesses.where((b) {
          final createdAt = b.metadata?['createdAt'];
          if (createdAt is int) {
            final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
            return DateTime.fromMillisecondsSinceEpoch(createdAt).isAfter(thirtyDaysAgo);
          }
          return false;
        }).take(10).toList();
        
        if (mounted) {
          setState(() {
            _allRealBusinesses = businesses;
            _newBusinesses = newBusinesses;
            _nearbyBusinesses = businesses.take(6).toList();
            _isLoadingRealData = false;
            _hasMoreRealData = businesses.length >= 20;
            _realDataPage = 0;
          });
          
          // تحديث status polling
          _updateStatusPollingWatchedIds();
          _statusPolling.forceImmediateFetch();
          
          developer.log('✅ تم عرض المطاعم القريبة من موقعك');
        }
      } else {
        // ❌ لا يوجد GPS - عرض رسالة للمستخدم
        developer.log('❌ لا يمكن جلب المطاعم بدون موقع GPS');
        
        if (mounted) {
          setState(() {
            _isLoadingRealData = false;
            _allRealBusinesses = [];
            _newBusinesses = [];
            _nearbyBusinesses = [];
          });
          
          // عرض رسالة للمستخدم
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'يرجى السماح بالوصول إلى الموقع لعرض المطاعم القريبة منك',
                style: TextStyle(fontSize: 14),
              ),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'السماح',
                textColor: Colors.white,
                onPressed: () async {
                  // إعادة المحاولة
                  await Geolocator.openLocationSettings();
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      developer.log('❌ خطأ في جلب المطاعم: $e');
      if (mounted) {
        setState(() {
          _isLoadingRealData = false;
        });
      }
    }
  }

  /// مساعد: تحويل dynamic إلى BusinessModel
  /// TODO: سيتم استخدامه بعد نشر Lambda Functions الجديدة
  // Future<List<BusinessModel>> _convertDynamicToBusinessModels(List<dynamic> dynamicList) async {
  //   final businesses = <BusinessModel>[];
  //   
  //   for (final item in dynamicList) {
  //     if (item is Map<String, dynamic>) {
  //       try {
  //         businesses.add(BusinessModel.fromJson(item));
  //       } catch (e) {
  //         developer.log('⚠️ خطأ في تحويل business: $e');
  //       }
  //     }
  //   }
  //   
  //   return businesses;
  // }

  Future<void> _initializeAddressSystem() async {
    // تأجيل تهيئة العناوين لتجنب مشكلة setState أثناء البناء
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final addressService = context.read<EnhancedAddressService>();
      await addressService.fetchAddresses();
      
      // تحديد العنوان الافتراضي تلقائياً إذا لم يكن هناك عنوان محدد
      if (mounted && _selectedAddress == null && addressService.defaultAddress != null) {
        setState(() {
          _selectedAddress = addressService.defaultAddress;
        });
      }
      
      // إضافة مستمع لتغييرات العناوين
      addressService.addListener(_onAddressServiceChanged);
    });
  }

  void _onAddressServiceChanged() {
    final addressService = context.read<EnhancedAddressService>();
    
    // تحديث العنوان المختار إذا تم تغيير العنوان الافتراضي
    if (_selectedAddress == null && addressService.defaultAddress != null) {
      setState(() {
        _selectedAddress = addressService.defaultAddress;
      });
    }
    
    // إذا كان العنوان المختار حالياً لم يعد موجوداً، استخدم العنوان الافتراضي الجديد
    if (_selectedAddress != null && addressService.defaultAddress != null) {
      final currentAddressExists = addressService.detailedAddresses
          .any((addr) => addr.id == _selectedAddress!.id);
      
      if (!currentAddressExists) {
        setState(() {
          _selectedAddress = addressService.defaultAddress;
        });
      }
    }
  }
  
  /// 🆕 استمع للتغييرات في RestaurantListProvider ونقل البيانات إلى home_screen
  void _onRestaurantListProviderChanged() {
    developer.log('═══════════════════════════════════════════════════');
    developer.log('🔔🔔🔔 _onRestaurantListProviderChanged CALLED!');
    developer.log('🎯 BREAKTHROUGH: Provider listener is working!');
    developer.log('   Widget mounted: $mounted');
    developer.log('   Timestamp: ${DateTime.now().toIso8601String()}');
    
    if (!mounted) {
      developer.log('❌ Widget not mounted - returning');
      developer.log('═══════════════════════════════════════════════════');
      return;
    }
    
    final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
    
    developer.log('📊 Provider State:');
    developer.log('   Provider hashCode: ${restaurantListProvider.hashCode}');
    developer.log('   isLoading = ${restaurantListProvider.isLoading}');
    developer.log('   restaurants.length = ${restaurantListProvider.restaurants?.length ?? 0}');
    if (restaurantListProvider.restaurants != null) {
      for (int i = 0; i < restaurantListProvider.restaurants!.length; i++) {
        final r = restaurantListProvider.restaurants![i];
        if (r is Map) {
          developer.log('   [$i] ${r['businessName'] ?? 'unknown'} (${r['businessId'] ?? 'no-id'})');
        } else if (r is BusinessModel) {
          developer.log('   [$i] ${r.businessName} (${r.id})');
        }
      }
    }
    
    // ✅ فقط استدعي Bridge عندما يكتمل التحميل (isLoading = false) وتوجد بيانات
    if (!restaurantListProvider.isLoading && 
        restaurantListProvider.restaurants != null && 
        restaurantListProvider.restaurants!.isNotEmpty) {
      
      developer.log('✅✅✅ Provider أنهى التحميل مع ${restaurantListProvider.restaurants!.length} مطعم - triggering bridge');
      developer.log('   Will call _bridgeProviderBusinessesIfAvailable() in microtask');
      
      // استخدام microtask لتجنب setState أثناء build
      Future.microtask(() {
        if (!mounted) return;
        developer.log('🌉 Executing _bridgeProviderBusinessesIfAvailable from Provider listener');
        _bridgeProviderBusinessesIfAvailable();
      });
    } else {
      developer.log('⚠️⚠️⚠️ Provider لا يزال يحمّل أو لا توجد بيانات بعد - سننتظر notification آخر');
      developer.log('   isLoading: ${restaurantListProvider.isLoading}');
      developer.log('   restaurants: ${restaurantListProvider.restaurants != null ? "not null" : "null"}');
      developer.log('   isEmpty: ${restaurantListProvider.restaurants?.isEmpty ?? true}');
    }
    developer.log('═══════════════════════════════════════════════════');
  }

  @override
  void dispose() {
    // إلغاء اشتراك WebSocket
    _businessStatusSubscription?.cancel();
    _webSocketService.onBusinessStatusUpdate = null;
    
    // 🔥 إلغاء جميع اشتراكات المطاعم النشطة
    for (final subscription in _activeBusinessSubscriptions.values) {
      subscription.cancel();
    }
    _activeBusinessSubscriptions.clear();
    
    // 🔥 إلغاء اشتراك polling updates
    _pollingUpdatesSubscription?.cancel();
    
    // 🆕 إزالة listener من RestaurantListProvider
    try {
      final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context, listen: false);
      restaurantListProvider.removeListener(_onRestaurantListProviderChanged);
      restaurantListProvider.stopPolling();
    } catch (e) {
      developer.log('⚠️ Error removing RestaurantListProvider listener: $e');
    }
    
    // 🆕 إلغاء اشتراك Delivery Address
    _deliveryAddressSubscription?.cancel();
    
    _bannerController.dispose();
    _bannerTimer?.cancel();
    _storesController.dispose();
    // إيقاف خدمة polling عند مغادرة الشاشة
    _statusPolling.stop();
    // إزالة مراقب دورة الحياة
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند عودة التطبيق للمقدمة، نفذ جلباً فورياً للحالات لتحديث البطاقات مباشرةً
    if (state == AppLifecycleState.resumed) {
      developer.log('Home: ⚡ App resumed — forcing immediate status fetch');
      _updateStatusPollingWatchedIds();
      _statusPolling.forceImmediateFetch();

      NotificationInboxService.instance.load().catchError((Object _) {});
      // Also consume any pending push-tap navigation.
      _handlePendingPushNavigation();
    }
  }

  Future<void> _handlePendingPushNavigation() async {
    if (!mounted) return;
    if (_isHandlingPendingPush) return;

    _isHandlingPendingPush = true;
    try {
      final pendingTab = await PushNotificationsService.consumePendingTabFromTap();
      if (pendingTab != null && mounted) {
        setState(() {
          _selectedTabIndex = pendingTab;
        });
      }

      final notificationPrefs = await SharedPreferences.getInstance();
      if (notificationPrefs.getBool('pendingWalletFromPushTap') == true) {
        await notificationPrefs.remove('pendingWalletFromPushTap');
        if (mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletTransferScreen()));
      }
      final pendingOrder = await PushNotificationsService.consumeStashedOrderFromTap();
      if (pendingOrder == null || !mounted) return;

      final orderId = (pendingOrder['orderId'] ?? '').toString();
      final orderNumber = (pendingOrder['orderNumber'] ?? '').toString();
      if (orderId.isEmpty) return;

      if (_lastHandledPushOrderId == orderId) return;
      _lastHandledPushOrderId = orderId;

      // Ensure we are on the Orders tab before opening tracking.
      if (mounted && _selectedTabIndex != 4) {
        setState(() {
          _selectedTabIndex = 4;
        });
      }

      // Delay navigation slightly to avoid racing with build/layout.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(
              orderId: orderId,
              orderNumber: orderNumber.isEmpty ? orderId : orderNumber,
            ),
          ),
        );
      });
    } catch (e) {
      developer.log('Home: pending push navigation error: $e');
    } finally {
      _isHandlingPendingPush = false;
    }
  }

  void _setupBannerTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_bannerController.hasClients) {
        _bannerPage = (_bannerPage + 1) % _bannerImages.length;
        _bannerController.animateToPage(
          _bannerPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _scrollListener() {
    // التحميل عندما يصل المستخدم إلى 80% من المحتوى
    if (_storesController.position.pixels >= 
        _storesController.position.maxScrollExtent * 0.8) {
      // تحميل المزيد من البيانات الحقيقية فقط
      if (_hasMoreRealData && !_isLoadingRealData) {
        _loadMoreRealBusinesses();
      }
    }
  }

  // تحميل البيانات الحقيقية للقسمين المحددين فقط
  Future<void> _loadRealBusinessData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingRealData = true;
    });

    try {
      // 🔧 FIX: Wait for session to be ready before making API calls
      await SessionService.instance.waitForSessionReady();
      
      developer.log('🔄 بدء تحميل البيانات الحقيقية باستخدام GPS...');
      
      // الحصول على موقع الجهاز
      Position? position;
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission != LocationPermission.denied && 
            permission != LocationPermission.deniedForever) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(Duration(seconds: 10));
          
          developer.log('📍 تم الحصول على الموقع: ${position.latitude}, ${position.longitude}');
        }
      } catch (e) {
        developer.log('❌ فشل الحصول على الموقع: $e');
      }
      
      if (position != null) {
        // جلب المطاعم بناءً على GPS
        final businesses = await BusinessService.getNearbyBusinesses(
          userLatitude: position.latitude,
          userLongitude: position.longitude,
          maxDistanceKm: 20.0,
          limit: 20,
        );
        
        developer.log('✅ تم تحميل ${businesses.length} مطعم قريب');
        
        // جلب المطاعم الجديدة من نفس النتائج
        final newBusinesses = businesses.where((b) {
          final createdAt = b.metadata?['createdAt'];
          if (createdAt is int) {
            final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
            return DateTime.fromMillisecondsSinceEpoch(createdAt).isAfter(thirtyDaysAgo);
          }
          return false;
        }).take(10).toList();
        
        if (mounted) {
          setState(() {
            _newBusinesses = newBusinesses;
            _allRealBusinesses = businesses;
            _nearbyBusinesses = businesses.take(6).toList();
            _isLoadingRealData = false;
            _hasMoreRealData = businesses.length >= 20;
            _realDataPage = 0;
          });
          
          developer.log('✅ تم تحديث الواجهة بالبيانات الحقيقية');
          
          _updateStatusPollingWatchedIds();
          _statusPolling.forceImmediateFetch();
        }
      } else {
        // لا يوجد GPS - عرض رسالة
        developer.log('❌ لا يمكن جلب المطاعم بدون GPS');
        
        if (mounted) {
          setState(() {
            _isLoadingRealData = false;
            _allRealBusinesses = [];
            _newBusinesses = [];
            _nearbyBusinesses = [];
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'يرجى السماح بالوصول إلى الموقع أو إدخال عنوان للتوصيل',
                style: TextStyle(fontSize: 14),
              ),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'السماح',
                textColor: Colors.white,
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      developer.log('❌ خطأ في تحميل البيانات الحقيقية: $e');
      if (mounted) {
        setState(() {
          _isLoadingRealData = false;
          _hasMoreRealData = false;
        });
      }
    }
  }

  /// 🔥 الاستماع لتحديثات polling وتحديث UI مباشرة
  void _listenToPollingUpdates() {
    _pollingUpdatesSubscription = _statusPolling.statusUpdates.listen(
      (update) {
        final businessId = update['businessId'] as String?;
        final isAvailable = update['isAvailable'] as bool?;
        final acceptingOrders = update['acceptingOrders'] as bool?;
        final isWithinWorkingHours = update['isWithinWorkingHours'] as bool?;
        
        if (businessId != null && mounted) {
          developer.log('🔔 Home: استلام تحديث polling للمطعم $businessId');
          developer.log('   - isAvailable: $isAvailable');
          developer.log('   - acceptingOrders: $acceptingOrders');
          developer.log('   - isWithinWorkingHours: $isWithinWorkingHours');
          
          setState(() {
            bool updated = false;
            
            // تحديث في _newBusinesses
            for (int i = 0; i < _newBusinesses.length; i++) {
              if (_newBusinesses[i].id == businessId) {
                _newBusinesses[i] = _newBusinesses[i].copyWith(
                  isAvailable: isAvailable,
                  acceptingOrders: acceptingOrders,
                );
                updated = true;
                developer.log('   ✅ تم تحديث في قائمة "وصل حديثاً"');
                break;
              }
            }
            
            // تحديث في _allRealBusinesses
            for (int i = 0; i < _allRealBusinesses.length; i++) {
              if (_allRealBusinesses[i].id == businessId) {
                _allRealBusinesses[i] = _allRealBusinesses[i].copyWith(
                  isAvailable: isAvailable,
                  acceptingOrders: acceptingOrders,
                );
                updated = true;
                developer.log('   ✅ تم تحديث في قائمة "جميع المطاعم"');
                break;
              }
            }
            
            // تحديث في _nearbyBusinesses
            for (int i = 0; i < _nearbyBusinesses.length; i++) {
              if (_nearbyBusinesses[i].id == businessId) {
                _nearbyBusinesses[i] = _nearbyBusinesses[i].copyWith(
                  isAvailable: isAvailable,
                  acceptingOrders: acceptingOrders,
                );
                updated = true;
                developer.log('   ✅ تم تحديث في قائمة "الأقرب إليك"');
                break;
              }
            }
            
            if (updated) {
              developer.log('🎉 Home: تم تحديث UI بنجاح للمطعم $businessId');
            }
          });
        }
      },
      onError: (error) {
        developer.log('❌ Home: خطأ في استلام تحديثات polling: $error');
      },
    );
    
    developer.log('✅ Home: تم إعداد الاستماع لتحديثات polling');
  }

  /// تحديث قائمة المعرفات المراقبة لخدمة polling
  void _updateStatusPollingWatchedIds() {
    debugPrint('🔍 _updateStatusPollingWatchedIds CALLED');
    debugPrint('   _newBusinesses.length = ${_newBusinesses.length}');
    debugPrint('   _allRealBusinesses.length = ${_allRealBusinesses.length}');
    debugPrint('   _nearbyBusinesses.length = ${_nearbyBusinesses.length}');
    final allBusinessIds = <String>{};
    for (final b in _newBusinesses) {
      allBusinessIds.add(b.id);
      debugPrint('   ➕ Added from _newBusinesses: ${b.id} (${b.businessName})');
    }
    for (final b in _allRealBusinesses) {
      allBusinessIds.add(b.id);
      debugPrint('   ➕ Added from _allRealBusinesses: ${b.id} (${b.businessName})');
    }
    for (final b in _nearbyBusinesses) {
      allBusinessIds.add(b.id);
      debugPrint('   ➕ Added from _nearbyBusinesses: ${b.id} (${b.businessName})');
    }
    debugPrint('✅ Total unique IDs to watch: ${allBusinessIds.length}');
    _statusPolling.updateWatchedIds(allBusinessIds);
  }

  // تحميل المزيد من البيانات الحقيقية لقسم "جميع المطاعم"
  Future<void> _loadMoreRealBusinesses() async {
    if (_isLoadingRealData || !_hasMoreRealData) return;

    setState(() {
      _isLoadingRealData = true;
    });

    try {
      _realDataPage++;
      developer.log('🔄 تحميل المزيد من المطاعم القريبة...');
      
      // الحصول على موقع الجهاز
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(Duration(seconds: 10));
      } catch (e) {
        developer.log('❌ فشل الحصول على الموقع: $e');
      }
      
      if (position != null) {
        // جلب المزيد من المطاعم بناءً على GPS مع نطاق أوسع
        final moreBusinesses = await BusinessService.getNearbyBusinesses(
          userLatitude: position.latitude,
          userLongitude: position.longitude,
          maxDistanceKm: 20.0 + (_realDataPage * 5.0), // زيادة النطاق تدريجياً
          limit: 20 + (_realDataPage * 10),
        );

        developer.log('✅ تم تحميل ${moreBusinesses.length} مطعم إضافي');

        if (mounted) {
          setState(() {
            if (moreBusinesses.isNotEmpty) {
              // فحص التكرار قبل الإضافة
              final existingIds = _allRealBusinesses.map((b) => b.id).toSet();
              final newBusinesses = moreBusinesses.where((b) => !existingIds.contains(b.id)).toList();
              
              if (newBusinesses.isNotEmpty) {
                _allRealBusinesses.addAll(newBusinesses);
                developer.log('✅ تم إضافة ${newBusinesses.length} مطعم جديد');
              } else {
                developer.log('⚠️ جميع المطاعم المحملة مكررة - توقف التحميل');
                _hasMoreRealData = false;
              }
              
              // التحقق إذا كان هناك المزيد
              _hasMoreRealData = newBusinesses.length >= 10;
            } else {
              _hasMoreRealData = false;
            }
            _isLoadingRealData = false;
          });
          
          developer.log('✅ إجمالي المطاعم المحملة: ${_allRealBusinesses.length}');

          _updateStatusPollingWatchedIds();
          _statusPolling.forceImmediateFetch();
        }
      } else {
        // لا يوجد GPS
        if (mounted) {
          setState(() {
            _isLoadingRealData = false;
            _hasMoreRealData = false;
          });
        }
      }
    } catch (e) {
      developer.log('❌ خطأ في تحميل المزيد من المطاعم: $e');
      if (mounted) {
        setState(() {
          _isLoadingRealData = false;
        });
      }
    }
  }

  // تحويل BusinessModel إلى Store للتوافق مع الكود الحالي
  Store _businessToStore(BusinessModel business, {bool showDistance = false}) {
    developer.log('🖼️ Converting business to store:');
    developer.log('  - Business name: ${business.businessName}');
    developer.log('  - Photo URL: "${business.businessPhotoUrl}"');
    developer.log('  - Show distance: $showDistance');
    
    // إصلاح الأسماء المعروفة الخاطئة
    String correctedBusinessName = business.businessName;
    if (business.businessName == 'اسواق اثير') {
      correctedBusinessName = 'زيت وزعتر';
      developer.log('  ✅ تصحيح اسم المطعم من "${business.businessName}" إلى "$correctedBusinessName"');
    }
    
    // استخدام الصورة الحقيقية من قاعدة البيانات
    String finalImageUrl = business.businessPhotoUrl;
    
    // إذا لم تكن هناك صورة أو كانت فارغة، استخدم صورة افتراضية
    if (finalImageUrl.isEmpty) {
      finalImageUrl = 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400&h=300&fit=crop';
      developer.log('  ⚠️ No image URL found, using fallback image');
    } else {
      developer.log('  ✅ Using real business image: $finalImageUrl');
    }
    
    // 🔥 حساب المسافة الحقيقية من موقع المستخدم
    String? distanceText;
    if (showDistance) {
      developer.log('  🗺️ Distance calculation requested');
      if (business.latitude != null && business.longitude != null) {
        // 🔥 الحصول على إحداثيات المستخدم من العنوان النشط
        final addressManager = DeliveryAddressManager.instance;
        final activeAddress = addressManager.activeAddress;
        
        if (activeAddress != null) {
          // 🔥 استخدام DistanceCalculator لحساب وتنسيق المسافة
          final calculatedDistance = business.calculateDistanceFrom(
            activeAddress.latitude,
            activeAddress.longitude,
          );
          
          if (calculatedDistance != null) {
            // 🔥 تنسيق المسافة (متر أو كيلومتر)
            distanceText = DistanceCalculator.formatDistance(calculatedDistance);
            developer.log('  📍 Calculated real distance: $distanceText');
          } else {
            developer.log('  ❌ Failed to calculate distance');
          }
        } else {
          developer.log('  ⚠️ User location not available from active address');
        }
      } else {
        developer.log('  ❌ Business has no coordinates (lat: ${business.latitude}, lng: ${business.longitude})');
      }
    } else {
      developer.log('  ⏭️ Distance calculation skipped');
    }
    
    // Calculate restaurant availability using new status logic
    // ⚠️ لا نفلتر على isOnline (isClosed) - المطاعم المغلقة يجب أن تظهر في القائمة
    final isRestaurantAvailable = business.isActive && 
                                 business.acceptingOrders && 
                                 !business.isBusy;
    
    developer.log('  🏪 Restaurant status check:');
    developer.log('    - isActive: ${business.isActive}');
    developer.log('    - acceptingOrders: ${business.acceptingOrders}');
    developer.log('    - isBusy: ${business.isBusy}');
    developer.log('    - isOnline (for display only): ${business.isOnline}');
    developer.log('    - Final availability: $isRestaurantAvailable');
    
    // تحديد رسالة الحالة بناءً على سبب عدم التوفر
    String statusMessage = '';
    if (!business.isActive) {
      statusMessage = 'المطعم معطل مؤقتاً';
    } else if (!business.isOnline) {
      // المطعم مغلق - لكن يجب أن يظهر في القائمة
      statusMessage = 'مغلق حالياً';
    } else if (!business.acceptingOrders) {
      statusMessage = 'لا يستقبل طلبات حالياً';
    } else if (business.isBusy) {
      statusMessage = 'مشغول - يرجى المحاولة لاحقاً';
    } else if (isRestaurantAvailable) {
      statusMessage = 'متاح لاستقبال الطلبات';
    }
    
    developer.log('    - Status message: "$statusMessage"');

    final store = Store(
      id: business.id,
      name: correctedBusinessName, // استخدام الاسم المصحح
      image: finalImageUrl,
      logoUrl: finalImageUrl,
      isOpen: isRestaurantAvailable, // Use comprehensive status check
      fee: business.deliveryFee.isNotEmpty ? business.deliveryFee : '5 آلاف',
      rating: business.rating.toStringAsFixed(1),
      reviews: '${(business.rating * 50).round()}', // تقدير عدد المراجعات
      distance: distanceText ?? '', // استخدام المسافة المحسوبة أو فارغة
      time: business.deliveryTime.isNotEmpty ? business.deliveryTime : '30 دقيقة',
      address: business.address,
      category: business.businessType,
      sponsored: business.metadata?['sponsored'] == true,
      // معلومات حالة المطعم الجديدة - use actual business fields
      isOnline: business.isOnline,
      acceptingOrders: business.acceptingOrders,
      isBusy: business.isBusy,
      businessMode: business.metadata?['businessMode'] as String? ?? 'auto',
      currentOrdersCount: business.metadata?['currentOrdersCount'] as int? ?? 0,
      maxOrdersCapacity: business.metadata?['maxOrdersCapacity'] as int? ?? 10,
      statusMessage: statusMessage.isNotEmpty ? statusMessage : (business.metadata?['statusMessage'] as String? ?? ''),
      lastStatusUpdate: business.metadata?['lastStatusUpdate'] as String?,
      businessStatus: business.metadata?['businessStatus'] as Map<String, dynamic>?,
      // بيانات وهمية للقوائم (يمكن تطويرها لاحقاً)
      combos: [],
      sandwiches: [],
      drinks: [],
      extras: [],
      specialties: [],
    );
    
    developer.log('  ✅ Store created with distance: "${store.distance}"');
    return store;
  }

  /// جلب أكواد الخصم الفعالة من المنصة وعرض أول كود لم يرفضه المستخدم
  Future<void> _loadActivePromoCodes() async {
    try {
      final promos = await OrderService().getActivePromoCodes();
      if (promos.isEmpty || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getStringList('dismissed_promo_ids') ?? [];

      final visible = promos.where((p) => !dismissed.contains(p.code)).toList();
      if (visible.isNotEmpty && mounted) {
        setState(() {
          _visiblePromo = visible.first;
        });
      }
    } catch (e) {
      debugPrint('خطأ في جلب أكواد الخصم: $e');
    }
  }

  Future<void> _dismissPromo() async {
    final promo = _visiblePromo;
    if (promo == null) return;

    setState(() {
      _visiblePromo = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList('dismissed_promo_ids') ?? [];
    if (!dismissed.contains(promo.code)) {
      dismissed.add(promo.code);
      await prefs.setStringList('dismissed_promo_ids', dismissed);
    }
  }

  @override
  Widget build(BuildContext context) {
    developer.log('🎨 build() called - _selectedTabIndex: $_selectedTabIndex, _allRealBusinesses.length: ${_allRealBusinesses.length}');
    debugPrint('🧪 BUILD VERSION V2 FALLBACK_SANITIZED - localBusinesses=${_allRealBusinesses.length}');

    // ✅ Fallback bridging: إذا فشل الـ listeners في تحديث القائمة (مثل حالة كارتوشكا)
    // نتحقق هنا في كل build إذا كان Provider يحتوي على عناصر أكثر من _allRealBusinesses
    final restaurantListProvider = Provider.of<RestaurantListProviderWithVersioning>(context); // listen=true
    final providerCount = restaurantListProvider.restaurantCount;
    // 🧪 Diagnostic: Capture provider IDs every build to detect silent divergence even when counts match
    final providerRawList = restaurantListProvider.restaurants ?? [];
    final List<String> providerIds = providerRawList.map((e) {
      if (e is BusinessModel) return e.id; // BusinessModel uses 'id'
      if (e is Map<String, dynamic>) {
        return (e['businessId'] ?? e['business_id'] ?? e['id'] ?? '').toString();
      }
      return 'UNKNOWN_TYPE';
    }).cast<String>().toList();
    final List<String> uiIds = _allRealBusinesses.map((b) => b.id).cast<String>().toList();
    // Difference detection
    final missingInUI = providerIds.where((id) => id.isNotEmpty && !uiIds.contains(id)).toList();
    final extraInUI = uiIds.where((id) => id.isNotEmpty && !providerIds.contains(id)).toList();
    debugPrint('🧪 BUILD DIAG: providerCount=$providerCount uiCount=${_allRealBusinesses.length} providerIds=$providerIds uiIds=$uiIds missingInUI=$missingInUI extraInUI=$extraInUI');
    
    // 🛡️ GUARD 1: لا نقوم بـ Fallback Bridge إذا كنا في عملية تحميل نشطة
    // هذا يمنع استبدال البيانات الجديدة بالبيانات القديمة من Provider
    final bool isActiveliyLoadingNewData = _isLoadingRealData;
    
    // 🛡️ GUARD 2: تحقق من أن Provider يحمل بيانات من نفس المنطقة
    // إذا كان المستخدم قد غيّر العنوان للتو، Provider قد لا يزال يحمل بيانات المنطقة القديمة
    final activeAddress = _deliveryAddressManager.activeAddress;
    final currentRegionId = activeAddress?.regionId;
    final providerRegionIds = <String>{};
    if (restaurantListProvider.restaurants != null) {
      for (final item in restaurantListProvider.restaurants!) {
        if (item is Map<String, dynamic>) {
          final regionId = item['regionId'] ?? item['region_id'];
          if (regionId != null) providerRegionIds.add(regionId.toString());
        }
      }
    }
    final bool providerHasSameRegion = currentRegionId == null || 
        providerRegionIds.isEmpty || 
        providerRegionIds.contains(currentRegionId);
    
    if (!providerHasSameRegion) {
      debugPrint('🛡️ GUARD: Provider region mismatch - current=$currentRegionId provider=$providerRegionIds');
      debugPrint('   سيتم تجاهل Fallback Bridge لأن Provider يحمل بيانات من منطقة مختلفة');
    }
    
    // 🛡️ GUARD 3: لا نسمح بـ Bridge إذا كانت البيانات المحلية أحدث من 2 ثانية
    // هذا يمنع استبدال البيانات الجديدة التي تم جلبها مؤخراً
    final secondsSinceLastUpdate = DateTime.now().difference(_lastDataUpdateTime).inSeconds;
    final bool dataIsFresh = secondsSinceLastUpdate < 2;
    
    if (dataIsFresh) {
      debugPrint('🛡️ GUARD: Data is fresh (${secondsSinceLastUpdate}s old) - skipping bridge');
    }
    
    // 🛡️ GUARD 4: لا نسمح بـ Bridge أثناء 10 ثواني بعد تغيير العنوان
    // هذا يعطي وقتاً كافياً لـ Provider لتحديث بياناته إلى المنطقة الجديدة
    final secondsSinceAddressChange = DateTime.now().difference(_lastAddressChangeTime).inSeconds;
    final bool justChangedAddress = secondsSinceAddressChange < 10;
    
    if (justChangedAddress) {
      debugPrint('🛡️ GUARD: Just changed address (${secondsSinceAddressChange}s ago) - skipping bridge');
      debugPrint('   Provider needs time to sync to new region');
    }
    
    // 🛡️ GUARD 5: Bridge يعمل فقط إذا كانت البيانات المحلية فارغة أو قديمة جداً
    // هذا يجعل Bridge "safety net" حقيقي وليس مصدر تداخل
    final bool localDataEmpty = _allRealBusinesses.isEmpty;
    final bool dataIsVeryOld = secondsSinceLastUpdate > 30; // أكثر من 30 ثانية
    final bool needsBridge = localDataEmpty || dataIsVeryOld;
    
    if (!needsBridge && !localDataEmpty) {
      debugPrint('🛡️ GUARD: Local data is present and recent - Bridge not needed');
      debugPrint('   Provider listener should handle updates normally');
    }
    
    // 🎯 Bridge يعمل فقط كـ "safety net" في حالات محددة جداً:
    // 1. البيانات المحلية فارغة (حالة تحميل أولي فاشل)
    // 2. البيانات قديمة جداً (أكثر من 30 ثانية) وProvider لديه بيانات جديدة
    final shouldBridgeCountMismatch = needsBridge && // ✅ فقط إذا احتجنا لـ Bridge
        providerCount > 0 &&
        restaurantListProvider.restaurants != null &&
        restaurantListProvider.restaurants!.isNotEmpty &&
        !restaurantListProvider.isLoading &&
        !isActiveliyLoadingNewData && // ✅ تعطيل Bridge أثناء التحميل النشط
        providerHasSameRegion && // ✅ فقط إذا كانت نفس المنطقة
        !dataIsFresh && // ✅ فقط إذا كانت البيانات المحلية قديمة
        !justChangedAddress && // ✅ فقط إذا لم يتم تغيير العنوان مؤخراً
        _allRealBusinesses.length != providerCount;

    // New condition: even if counts match, if IDs differ, perform bridging
    // ✅ نضيف نفس الحماية + needsBridge
    final shouldBridgeIdMismatch = needsBridge && // ✅ فقط إذا احتجنا لـ Bridge
        providerCount > 0 && 
        missingInUI.isNotEmpty &&
        !isActiveliyLoadingNewData && // ✅ تعطيل Bridge أثناء التحميل النشط
        providerHasSameRegion && // ✅ فقط إذا كانت نفس المنطقة
        !dataIsFresh && // ✅ فقط إذا كانت البيانات المحلية قديمة
        !justChangedAddress; // ✅ فقط إذا لم يتم تغيير العنوان مؤخراً

    if (shouldBridgeCountMismatch || shouldBridgeIdMismatch) {
      debugPrint('🌉🌉🌉 FALLBACK BRIDGE ACTIVATED - This is rare and means Provider listener failed');
      debugPrint('   Reason: ${localDataEmpty ? "LOCAL_EMPTY" : dataIsVeryOld ? "DATA_VERY_OLD" : "UNKNOWN"}');
      debugPrint('   This should NOT happen during normal address changes');
      
      // تجنب إعادة نفس العملية مرة أخرى إذا لم يتغير شيء
      if (_lastFallbackProviderCount == providerCount && _lastFallbackAppliedCount == _allRealBusinesses.length) {
        debugPrint('⏭️ Fallback bridge skipped (no change since last attempt) provider=$providerCount local=${_allRealBusinesses.length}');
      } else {
        final providerList = restaurantListProvider.restaurants!;
        final List<BusinessModel> bridged = [];
        int mapConverted = 0;
        int modelCopied = 0;
        int invalidCount = 0;
        for (final item in providerList) {
          if (item is BusinessModel) {
            bridged.add(item);
            modelCopied++;
          } else if (item is Map<String, dynamic>) {
            try {
              final model = BusinessModel.fromJson(item);
              bridged.add(model);
              mapConverted++;
            } catch (e) {
              debugPrint('❌ BRIDGE: فشل تحويل Map في fallback bridge: $e');
              invalidCount++;
            }
          } else {
            invalidCount++;
            debugPrint('⚠️ BRIDGE: عنصر غير متوقع في fallback bridge: type=${item.runtimeType}');
          }
        }
        debugPrint('🛠 Fallback bridge triggered in build() - reason=${shouldBridgeCountMismatch ? 'COUNT_MISMATCH' : 'ID_MISMATCH'} providerCount=$providerCount local=${_allRealBusinesses.length} copied=$modelCopied converted=$mapConverted invalid=$invalidCount missingInUI=$missingInUI');
        if (bridged.isNotEmpty) {
          _lastFallbackProviderCount = providerCount;
          // Record intended post-bridge count (bridged length) instead of pre-update local list
          _lastFallbackAppliedCount = bridged.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _allRealBusinesses = bridged;
              _isLoadingRealData = false;
            });
            debugPrint('🔥 Fallback bridge applied - newCount=${_allRealBusinesses.length}');
            _updateStatusPollingWatchedIds();
          });
        } else {
          debugPrint('⚠️ Fallback bridge: لا عناصر صالحة بعد الفحص');
        }
      }
    }
    return PopScope(
      canPop: false, // منع الخروج المباشر
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        // التحقق من التبويب الحالي - فقط في التبويب الرئيسي نظهر رسالة الخروج
        if (_selectedTabIndex != 0) {
          // إذا كان في تبويب آخر، العودة للتبويب الرئيسي
          setState(() => _selectedTabIndex = 0);
          return;
        }
        
        // إظهار تأكيد الخروج فقط في التبويب الرئيسي
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد الخروج'),
            content: const Text('هل تريد إغلاق التطبيق؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('خروج', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        
        if (shouldExit == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: _selectedTabIndex == 0
            ? Stack(
                children: [
                  _buildHomeContentWithStickySearch(),
                  if (_visiblePromo != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: SafeArea(
                        top: false,
                        child: PromoFloatingCard(
                          promo: _visiblePromo!,
                          onDismiss: _dismissPromo,
                        ),
                      ),
                    ),
                ],
              )
            : _buildTabContent(),
        bottomNavigationBar: _buildBottomNavigation(),
      ),
    );
  }

  // محتوى الصفحة الرئيسية مع الشريط العلوي الثابت
  Widget _buildHomeContentWithStickySearch() {
    return Column(
      children: [
        // الشريط العلوي الثابت
        _buildFixedHeader(),
        // المحتوى القابل للتمرير
        Expanded(
          child: SingleChildScrollView(
            controller: _storesController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFiltersSection(),
                _buildBannerSection(),
                _buildStoresSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // الشريط العلوي الثابت (بدون SafeArea)
  Widget _buildFixedHeader() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // صف واحد: شريط العنوان والأيقونات
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  // الجهة اليمنى: شريط العنوان (مصغر)
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final appState = Provider.of<AppStateProvider>(context, listen: false);
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddressGateScreen(
                              isGuest: appState.isGuest,
                              showBackButton: true,
                            ),
                          ),
                        );
                        
                        if (result == true && mounted) {
                          _reloadBusinessesAfterAddressChange();
                        }
                      },
                      child: StreamBuilder<DeliveryAddress?>(
                        stream: DeliveryAddressManager.instance.addressStream,
                        initialData: DeliveryAddressManager.instance.activeAddress,
                        builder: (context, snapshot) {
                          final address = snapshot.data;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, color: AppColors.primary, size: 18),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    address?.label ?? 'اختر عنوان التوصيل',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 18),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // الجهة اليسرى: الأيقونات (المحفظة، الإشعارات، السلة)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const WalletTransferScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 24),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          child: ValueListenableBuilder<bool>(valueListenable: NotificationInboxService.hasUnread,builder:(_,unread,__)=>Badge(isLabelVisible:unread,backgroundColor:AppColors.secondary,child:const Icon(Icons.notifications_outlined,color:AppColors.primary,size:24))),
                        ),
                      ),
                      Consumer<AppStateProvider>(
                        builder: (context, appState, child) {
                          return ModernCartIcon(
                            badgeCount: appState.cartItemsCount,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CartScreen(
                                    storeId: _getStoreIdFromCart(appState),
                                    storeName: _getStoreNameFromCart(appState),
                                    stores: _allRealBusinesses.map((business) => _businessToStore(business, showDistance: true)).toList(),
                                  ),
                                ),
                              );
                            },
                            color: AppColors.primary,
                            size: 24,
                            isGlassmorphic: false,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // الصف الثالث: شريط البحث وأيقونة اكتشف (بدون SafeArea)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  // شريط البحث
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const Scaffold(
                              body: Center(
                                child: Text(
                                  'شاشة البحث المحسنة غير متاحة مؤقتاً',
                                  style: TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search, color: Colors.grey[400], size: 24),
                            const SizedBox(width: 12),
                            Text(
                              'ابحث عن مطاعم أو أطباق...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // أيقونة اكتشف
                  GestureDetector(
                    onTap: () {
                      // تمرير المطاعم المصفاة حسب regionId إلى شاشة الخريطة
                      // هذه المطاعم تم تصفيتها مسبقاً في _onActiveAddressAvailable
                      // بناءً على العنوان المختار من قبل الزبون
                      developer.log('🗺️ فتح شاشة الخريطة مع ${_allRealBusinesses.length} مطعم مصفى');
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MapScreenNew(
                            businesses: _allRealBusinesses, // المطاعم المصفاة حسب regionId
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                      ),
                      child: Icon(
                        Icons.explore,
                        size: 24,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // شريط الفلاتر الأفقي
  Widget _buildFiltersSection() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // فلتر "رتب حسب" مع قائمة منسدلة
          _buildSortFilterButton(),
          const SizedBox(width: 8),
          // فلتر "مفتوح الآن"
          _buildFilterChip(
            label: 'مفتوح الآن',
            icon: Icons.access_time,
            isSelected: _filterOpenNow,
            onTap: () => setState(() => _filterOpenNow = !_filterOpenNow),
          ),
          const SizedBox(width: 8),
          // فلتر "توصيل مجاني"
          _buildFilterChip(
            label: 'توصيل مجاني',
            icon: Icons.delivery_dining,
            isSelected: _filterFreeDelivery,
            onTap: () => setState(() => _filterFreeDelivery = !_filterFreeDelivery),
          ),
          const SizedBox(width: 8),
          // فلتر "عروض"
          _buildFilterChip(
            label: 'عروض',
            icon: Icons.local_offer,
            isSelected: _filterOffers,
            onTap: () => setState(() => _filterOffers = !_filterOffers),
          ),
        ],
      ),
    );
  }

  // زر فلتر "رتب حسب" مع قائمة منسدلة
  Widget _buildSortFilterButton() {
    final isSelected = _selectedSortOption != 'رتب حسب';
    return GestureDetector(
      onTap: () => _showSortOptionsBottomSheet(),
      child: Container(
        // إزالة الارتفاع الثابت واستخدام قيود مرنة بحيث يحتضن النص بدون فراغ زائد
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        constraints: const BoxConstraints(minHeight: 26),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          // شكل كبسولة أنحف
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected 
                ? AppColors.primary 
                : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _selectedSortOption,
              style: TextStyle(
                fontSize: 12.5,
                color: isSelected 
                    ? AppColors.secondary 
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                height: 1.05, // تقليل الفراغ العلوي والسفلي قدر الإمكان
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: isSelected ? AppColors.secondary : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  // عرض قائمة خيارات الترتيب
  void _showSortOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'رتب حسب',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildSortOption('الأقرب'),
              _buildSortOption('الأسرع توصيلاً'),
              _buildSortOption('أعلى تقييماً'),
              _buildSortOption('أ-ي'),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // خيار ترتيب واحد
  Widget _buildSortOption(String option) {
    final isSelected = _selectedSortOption == option;
    return ListTile(
      title: Text(
        option,
        style: TextStyle(
          fontSize: 15,
          color: isSelected ? AppColors.secondary : AppColors.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: AppColors.secondary, size: 22)
          : null,
      onTap: () {
        setState(() => _selectedSortOption = option);
        Navigator.pop(context);
        // TODO: تطبيق الترتيب على قائمة المطاعم
      },
    );
  }

  // بناء زر فلتر واحد
  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        constraints: const BoxConstraints(minHeight: 22),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected 
                ? AppColors.primary 
                : AppColors.border,
            width: 1,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // الشريط العلوي القابل للتمرير (بدون شريط البحث)
  Widget _buildBannerSection() {
    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: PageView.builder(
        controller: _bannerController,
        itemCount: _bannerImages.length,
        onPageChanged: (index) => setState(() => _bannerPage = index),
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: AssetImage(_bannerImages[index]),
                fit: BoxFit.cover,
                onError: (exception, stackTrace) {},
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStoresSection() {
    developer.log('🏗️ _buildStoresSection() - بدء بناء قسم المطاعم');
    developer.log('   - _allRealBusinesses.length: ${_allRealBusinesses.length}');
    developer.log('   - _newBusinesses.length: ${_newBusinesses.length}');
    developer.log('   - _nearbyBusinesses.length: ${_nearbyBusinesses.length}');
    // طباعة تفاصيل أول 5 مطاعم
    developer.log('📋 تفاصيل المطاعم في _allRealBusinesses:');
    for (int i = 0; i < _allRealBusinesses.length && i < 5; i++) {
      final b = _allRealBusinesses[i];
      developer.log('   [${i + 1}] ${b.businessName} (ID: ${b.id})');
      developer.log('       isActive: ${b.isActive}');
      developer.log('       address: ${b.address}');
      developer.log('       photoUrl: ${b.businessPhotoUrl.length > 50 ? b.businessPhotoUrl.substring(0, 50) + "..." : b.businessPhotoUrl}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // قسم وصل حديثاً
        _buildNewArrivalsSection(),
        
        // قسم الأقرب إليك
        _buildNearestStoresSection(),
        
        // قسم الأكثر شهرة
        _buildPopularStoresSection(),
        
        // قسم جميع المطاعم
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'جميع المطاعم',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        // ✅ استخدام Builder مباشرة بدون Consumer لأن البيانات تأتي من _allRealBusinesses (state محلي)
        Builder(
          builder: (context) {
            developer.log('═══════════════════════════════════════════════════════');
            developer.log('🔍 Builder "جميع المطاعم" يُعاد build الآن');
            developer.log('   - _allRealBusinesses.length: ${_allRealBusinesses.length}');
            developer.log('   - _isLoadingRealData: $_isLoadingRealData');
            
            if (_allRealBusinesses.isNotEmpty) {
              developer.log('   - أول 3 مطاعم في _allRealBusinesses:');
              for (int i = 0; i < _allRealBusinesses.length && i < 3; i++) {
                developer.log('     ${i + 1}. ${_allRealBusinesses[i].businessName}');
              }
            }
            developer.log('═══════════════════════════════════════════════════════');
            
            // استخدام البيانات الحقيقية فقط
            final allStores = <Store>[];
            
            // إضافة البيانات الحقيقية فقط
            if (_allRealBusinesses.isNotEmpty) {
              developer.log('📋 تحويل ${_allRealBusinesses.length} مطعم إلى Store objects...');
              try {
                for (var i = 0; i < _allRealBusinesses.length; i++) {
                  try {
                    final business = _allRealBusinesses[i];
                    developer.log('🔄 [${i + 1}/${_allRealBusinesses.length}] تحويل: ${business.businessName}');
                    final store = _businessToStore(business, showDistance: true);
                    allStores.add(store);
                    developer.log('   ✅ نجح التحويل');
                  } catch (e, stackTrace) {
                    developer.log('   ❌ فشل التحويل: $e');
                    developer.log('   Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
                  }
                }
                developer.log('✅ تم تحويل ${allStores.length} مطعم بنجاح من ${_allRealBusinesses.length}');
              } catch (e, stackTrace) {
                developer.log('❌ خطأ في تحويل المطاعم إلى Store objects: $e');
                developer.log('Stack: $stackTrace');
              }
            } else {
              developer.log('⚠️ _allRealBusinesses فارغة - لا توجد مطاعم للتحويل');
            }
            
            // إذا لم تكن هناك بيانات حقيقية، عرض رسالة التحميل
            if (allStores.isEmpty && _isLoadingRealData) {
              developer.log('⏳ عرض مؤشر التحميل...');
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('جاري تحميل المطاعم...', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              );
            }
            
            // إذا لم تكن هناك بيانات حقيقية وانتهى التحميل، عرض رسالة فارغة
            if (allStores.isEmpty && !_isLoadingRealData) {
              developer.log('❌ لا توجد مطاعم لعرضها');
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.restaurant, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('لا توجد مطاعم متاحة حالياً', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('يرجى المحاولة مرة أخرى لاحقاً', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              );
            }
            
            developer.log('✅ عرض ${allStores.length} مطعم في القائمة');
            return Consumer<FavoritesModel>(
              builder: (context, favModel, child) {
                return Column(
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: allStores.length,
                      itemBuilder: (context, index) {
                        final store = allStores[index];
                        return EnhancedRestaurantCard(
                          key: ValueKey(store.id),
                          store: store,
                          isCompact: false,
                          onTap: () {
                            developer.log('🏪 تم النقر على المطعم: ${store.name}');
                            try {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => StoreDetailScreen(
                                    store: store,
                                  ),
                                ),
                              );
                            } catch (e) {
                              developer.log('❌ خطأ في التنقل إلى StoreDetailScreen: $e');
                            }
                          },
                        );
                      },
                    ),
                    // عرض مؤشر التحميل أو رسالة النهاية
                    if (_isLoadingRealData)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text('جاري تحميل المزيد...', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    else if (!_hasMoreRealData && allStores.isNotEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'تم عرض جميع المطاعم المتاحة',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 1:
        return _buildFavoritesTab();
      case 3:
        return _buildMapScreen();
      case 4:
        return const OrdersScreen();
      case 5:
        return const ImprovedAccountScreen();
      default:
        return _buildHomeContentWithStickySearch();
    }
  }

  Widget _buildFavoritesTab() {
    return Consumer<FavoritesModel>(
      builder: (context, favoritesModel, child) {
        return FavoriteStoresScreen(
          favoritesModel: favoritesModel,
          allStores: _allRealBusinesses.map((business) => _businessToStore(business, showDistance: true)).toList(),
        );
      },
    );
  }

  Widget _buildMapScreen() {
    // عرض شاشة الخريطة مع المطاعم المصفاة حسب المنطقة
    return MapScreenNew(
      businesses: _allRealBusinesses,
    );
  }

  Widget _buildBottomNavigation() {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (appState.cartItemsCount > 0) 
              AnimatedCartBar(
                storeName: _getStoreNameFromCart(appState),
                isExpanded: false,
                storeId: _getStoreIdFromCart(appState),
                stores: _allRealBusinesses.map((business) => _businessToStore(business, showDistance: true)).toList(),
              ),
            CustomBottomNavigation(
              currentIndex: _selectedTabIndex,
              onTap: (index) => setState(() => _selectedTabIndex = index),
            ),
          ],
        );
      },
    );
  }

  // دوال الأقسام المختلفة
  Widget _buildNewArrivalsSection() {
    return Consumer<FavoritesModel>(
      builder: (context, favModel, child) {
        final newStores = _getNewStores();
        
        if (newStores.isEmpty) {
          return const SizedBox.shrink(); // لا تعرض شيئاً إذا لم تكن هناك مطاعم جديدة
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'وصل حديثاً',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: newStores.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.only(left: 12),
                    child: EnhancedRestaurantCard(
                      key: ValueKey(newStores[index].id),
                      store: newStores[index],
                      isCompact: true,
                      onTap: () {
                        developer.log('🏪 تم النقر على المطعم: ${newStores[index].name}');
                        try {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoreDetailScreen(
                                store: newStores[index],
                              ),
                            ),
                          );
                        } catch (e) {
                          developer.log('❌ خطأ في التنقل إلى StoreDetailScreen: $e');
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildNearestStoresSection() {
    return Consumer<FavoritesModel>(
      builder: (context, favModel, child) {
        final nearbyStores = _getNearbyStores();
        
        if (nearbyStores.isEmpty) {
          return const SizedBox.shrink(); // لا تعرض شيئاً إذا لم تكن هناك مطاعم قريبة
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'الأقرب إليك',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: nearbyStores.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.only(left: 12),
                    child: EnhancedRestaurantCard(
                      key: ValueKey(nearbyStores[index].id),
                      store: nearbyStores[index],
                      isCompact: true,
                      onTap: () {
                        developer.log('🏪 تم النقر على المطعم: ${nearbyStores[index].name}');
                        try {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoreDetailScreen(
                                store: nearbyStores[index],
                              ),
                            ),
                          );
                        } catch (e) {
                          developer.log('❌ خطأ في التنقل إلى StoreDetailScreen: $e');
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPopularStoresSection() {
    return Consumer<FavoritesModel>(
      builder: (context, favModel, child) {
        final popularStores = _getPopularStores();
        
        if (popularStores.isEmpty) {
          return const SizedBox.shrink(); // لا تعرض شيئاً إذا لم تكن هناك مطاعم شائعة
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'الأكثر شهرة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: popularStores.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.only(left: 12),
                    child: EnhancedRestaurantCard(
                      key: ValueKey(popularStores[index].id),
                      store: popularStores[index],
                      isCompact: true,
                      onTap: () {
                        developer.log('🏪 تم النقر على المطعم: ${popularStores[index].name}');
                        try {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoreDetailScreen(
                                store: popularStores[index],
                              ),
                            ),
                          );
                        } catch (e) {
                          developer.log('❌ خطأ في التنقل إلى StoreDetailScreen: $e');
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  // دوال للحصول على البيانات المفلترة بتوزيع ذكي
  List<Store> _getNearbyStores() {
    developer.log('═══════════════════════════════════════════════════');
    developer.log('🔍 _getNearbyStores() called');
    developer.log('   _allRealBusinesses: ${_allRealBusinesses.length} مطعم');
    developer.log('   _nearbyBusinesses: ${_nearbyBusinesses.length} مطعم');
    
    // ✅ المنطق البسيط: استخدم _allRealBusinesses دائماً إذا كان موجوداً
    // (لأنه يحتوي على مطاعم المنطقة من العنوان المُختار)
    if (_allRealBusinesses.isNotEmpty) {
      developer.log('✅ استخدام _allRealBusinesses (مطاعم المنطقة)');
      
      // ✅ أخذ أول 6 مطاعم وتحويلها
      final stores = _allRealBusinesses
          .take(6)
          .map((business) => _businessToStore(business, showDistance: true))
          .toList();
      
      developer.log('📤 OUTPUT: ${stores.length} مطعم');
      for (int i = 0; i < stores.length; i++) {
        developer.log('   [${i + 1}] ${stores[i].name} (ID: ${stores[i].id})');
      }
      developer.log('═══════════════════════════════════════════════════');
      
      return stores;
    }
    
    // ⚠️ Fallback: فقط إذا _allRealBusinesses فارغ، استخدم GPS
    if (_nearbyBusinesses.isNotEmpty) {
      developer.log('⚠️ FALLBACK: استخدام _nearbyBusinesses (GPS)');
      
      final stores = _nearbyBusinesses
          .map((business) => _businessToStore(business, showDistance: true))
          .toList();
      
      developer.log('📤 OUTPUT: ${stores.length} مطعم (من GPS)');
      developer.log('═══════════════════════════════════════════════════');
      
      return stores;
    }
    
    // ❌ لا توجد مطاعم على الإطلاق
    developer.log('❌ NO RESTAURANTS AVAILABLE');
    developer.log('═══════════════════════════════════════════════════');
    return [];
  }
  
  List<Store> _getNewStores() {
    if (_newBusinesses.isNotEmpty) {
      return _newBusinesses.map((business) => _businessToStore(business, showDistance: true)).toList();
    }
    return [];
  }
  
  List<Store> _getPopularStores() {
    developer.log('🔍 _getPopularStores() called - Total: ${_allRealBusinesses.length}');
    
    if (_allRealBusinesses.isEmpty) {
      developer.log('❌ No businesses available');
      return [];
    }
    
    // ✅ تحويل جميع المطاعم (بدون تخطي أي شيء)
    final allStores = _allRealBusinesses
        .map((business) => _businessToStore(business, showDistance: true))
        .toList();
    
    // ✅ ترتيب حسب التقييم
    allStores.sort((a, b) => double.parse(b.rating).compareTo(double.parse(a.rating)));
    
    developer.log('📤 OUTPUT: ${allStores.length} مطعم (sorted by rating)');
    return allStores;
  }

  // دوال مساعدة لاستخراج معلومات المتجر من السلة
  String _getStoreNameFromCart(AppStateProvider appState) {
    if (appState.cartItems.isNotEmpty) {
      // 1. أولاً محاولة الحصول على اسم المتجر من بيانات السلة
      final storeName = appState.cartItems.first['store_name'] as String?;
      developer.log('🔍 _getStoreNameFromCart: store_name من السلة = "$storeName"');
      
      // قائمة الأسماء المرفوضة (الافتراضية/الخاطئة)
      final rejectedNames = ['متجر', 'المطعم', 'عربة التسوق'];
      
      if (storeName != null && 
          storeName.isNotEmpty && 
          !rejectedNames.contains(storeName)) {
        developer.log('✅ _getStoreNameFromCart: استخدام اسم من السلة = "$storeName"');
        return storeName;
      }
      
      // 2. إذا لم نجد اسم المتجر الصحيح في السلة، نحاول البحث عنه في قائمة المطاعم
      final storeId = appState.cartItems.first['store_id'] as String?;
      developer.log('🔍 _getStoreNameFromCart: store_id من السلة = "$storeId"');
      developer.log('🔍 _getStoreNameFromCart: عدد المطاعم المحملة = ${_allRealBusinesses.length}');
      
      if (storeId != null && _allRealBusinesses.isNotEmpty) {
        try {
          final business = _allRealBusinesses.firstWhere(
            (business) => business.id == storeId,
            orElse: () => throw StateError('لم يتم العثور على المطعم'),
          );
          
          developer.log('✅ _getStoreNameFromCart: وجد المطعم = "${business.businessName}"');
          
          if (business.businessName.isNotEmpty && !rejectedNames.contains(business.businessName)) {
            return business.businessName;
          }
        } catch (e) {
          developer.log('❌ _getStoreNameFromCart: لم يتم العثور على المطعم بـ ID: $storeId');
        }
      }
    }
    developer.log('⚠️ _getStoreNameFromCart: إرجاع القيمة الافتراضية "متجر"');
    return 'متجر';
  }

  String? _getStoreIdFromCart(AppStateProvider appState) {
    if (appState.cartItems.isNotEmpty) {
      return appState.cartItems.first['store_id'] as String?;
    }
    return null;
  }

}

