import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/store.dart';
import '../models/dish.dart';
import '../models/product_model.dart';
import '../models/working_hours_model.dart';
import '../models/favorites_model.dart';
import '../models/business_suggestion_data.dart';
import '../services/business_service.dart';
import '../services/working_hours_service.dart';
import '../services/restaurant_availability_service.dart';
import '../services/subscription_manager.dart';
import '../services/status_polling_service.dart'; // 🔥 جديد
import '../providers/app_state_provider.dart';
import '../providers/versioning_providers.dart';
import '../widgets/animated_cart_bar.dart';
import 'dish_detail_screen.dart';

import 'dart:async';

// 🏗️ فئة جديدة لتحديد حالة توفر الأطباق بناءً على حالة المطعم
class DishAvailability {
  final bool isAvailable;
  final String reasonText;
  final String message;
  final IconData icon;
  final Color statusColor;

  const DishAvailability({
    required this.isAvailable,
    required this.reasonText,
    required this.message,
    required this.icon,
    required this.statusColor,
  });
}

class StoreDetailScreen extends StatefulWidget {
  final Store store;

  const StoreDetailScreen({
    super.key,
    required this.store,
  });

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  TabController? _tabController;
  final ScrollController _scrollCtrl = ScrollController();
  bool _collapsed = false;
  static const _primaryPink = AppColors.primary;

  // البيانات من الباك إند
  Map<String, List<ProductModel>> _categoryProducts = {};
  bool _isLoading = true;
  String? _error;
  final Map<String, GlobalKey> _keys = {};
  bool _dataLoaded = false; // إضافة متغير لتتبع حالة التحميل
  
  // ساعات العمل
  BusinessWorkingHours? _workingHours;

  // دالة مساعدة للتحقق من وجود منتجات في الفئات
  bool _hasNoProducts() {
    if (_categoryProducts.isEmpty) return true;
    
    // التحقق من أن جميع الفئات فارغة
    for (final products in _categoryProducts.values) {
      if (products.isNotEmpty) {
        return false; // يوجد منتجات في هذه الفئة
      }
    }
    return true; // جميع الفئات فارغة
  }
  
  bool _loadingWorkingHours = true;
  
  // متغيرات تحديث حالة المطعم
  bool _loadingBusinessStatus = true;
  Timer? _statusRefreshTimer;
  
  // خدمة توفر المطاعم الجديدة
  final RestaurantAvailabilityService _availabilityService = 
      RestaurantAvailabilityService.instance;
  RestaurantAvailabilityStatus? _availabilityStatus;
  String? _currentWeekdayFromBackend; // 🔥 اليوم الحالي من Backend (timezone المطعم)
  
  // SubscriptionManager للتحديثات من Polling (بدون WebSocket)
  final SubscriptionManager _subscriptionManager = SubscriptionManager.instance;
  late final String _subscriberId;
  StreamSubscription<Map<String, dynamic>>? _businessStatusSubscription;
  
  // 🔥 خدمة polling ومستمع لتحديثاتها
  final StatusPollingService _statusPolling = StatusPollingService.instance;
  StreamSubscription<Map<String, dynamic>>? _pollingUpdatesSubscription;
  
  // 🔥 تتبع آخر تحديث لتجنب تضارب التحديثات
  DateTime? _lastUpdateTime;

  String _displayCategoryTitle(String title, {int maxChars = 26}) {
    final trimmed = title.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}...';
  }

  @override
  void initState() {
    super.initState();
    developer.log('🏗️ StoreDetailScreen initState');
    
    // تهيئة SubscriptionManager
    _subscriberId = _subscriptionManager.generateSubscriberId('store_detail_${widget.store.id}');
    
    // ✅ تأخير تحديد حالة المفضلة حتى بعد تحميل FavoritesModel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        // Favorite state is handled via Consumer widgets
      });
      developer.log('✅ تم تحديد حالة المفضلة الأولية: للمطعم: ${widget.store.name}');
    });
    
    // إضافة مستمعات
    _scrollCtrl.addListener(_updateCollapsedState);
    _scrollCtrl.addListener(_handleScrollTabSync);
    WidgetsBinding.instance.addObserver(this);
    
    // جلب البيانات من الباك إند
    _loadBusinessData();
    _loadWorkingHours();
    _loadBusinessStatus();
    _startBusinessStatusUpdates();
    
    // 🔥 إعداد اشتراك SubscriptionManager (يستقبل تحديثات polling)
    _setupSubscriptionListener();
    
    // 🔥 بدء خدمة polling وإضافة هذا المطعم للمراقبة
    _statusPolling.start();
    _statusPolling.updateWatchedIds([widget.store.id]);
    
    // 🔥 الاستماع لتحديثات polling
    _listenToPollingUpdates();
    
    // 🆕 بدء menu polling للتحديثات الفورية
    _startMenuPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    developer.log('🔄 StoreDetailScreen didChangeDependencies');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    developer.log('🔄 StoreDetailScreen: تغيير حالة التطبيق: $state');
    
    if (state == AppLifecycleState.resumed && mounted) {
      // عند العودة للتطبيق - تحديث الحالة من الكاش
      _loadBusinessStatus();
    }
  }

  // 🆕 احتفاظ بـ reference للـ provider قبل dispose
  MenuProviderWithVersioning? _menuProvider;

  @override
  void dispose() {
    developer.log('🗑️ StoreDetailScreen dispose');
    WidgetsBinding.instance.removeObserver(this);
    _tabController?.dispose();
    _scrollCtrl.dispose();
    _statusRefreshTimer?.cancel();
    _businessStatusSubscription?.cancel();
    
    // 🔥 إلغاء اشتراك polling updates
    _pollingUpdatesSubscription?.cancel();
    
    // 🆕 إيقاف menu polling باستخدام reference محفوظة
    _menuProvider?.stopPolling();
    
    // إلغاء الاشتراك من SubscriptionManager
    _subscriptionManager.unsubscribeFromBusinessStatus(widget.store.id, _subscriberId);
    
    super.dispose();
  }

  /// 🆕 بدء polling للمنيو والمخزون للتحديثات الفورية
  void _startMenuPolling() {
    // حفظ reference للـ provider قبل استخدامه
    _menuProvider = Provider.of<MenuProviderWithVersioning>(context, listen: false);
    
    developer.log('🆕 بدء menu polling للمطعم: ${widget.store.id}');
    
    // بدء polling مع interval 30 ثانية
    _menuProvider!.startPolling(widget.store.id);
    
    // إضافة listener للتحديثات
    _menuProvider!.addListener(() {
      if (mounted && !_menuProvider!.isLoading) {
        developer.log('🔔 تحديث متاح للمنيو - إعادة التحميل...');
        _loadBusinessData();
      }
    });
    
    developer.log('✅ Menu polling بدأ بنجاح');
  }

  Future<void> _loadBusinessData() async {
    if (!mounted) return;
    
    // منع التحميل المتكرر إذا كانت البيانات موجودة بالفعل
    if (_dataLoaded && _categoryProducts.isNotEmpty && _error == null) {
      developer.log('📋 البيانات موجودة مسبقاً - تجاهل إعادة التحميل');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      developer.log('🔍 جاري تحميل منتجات المطعم: ${widget.store.name} (ID: ${widget.store.id})');
      
      final categoryProducts = await BusinessService.getBusinessCategoriesAndProducts(widget.store.id);
      
      if (!mounted) return;
      
      developer.log('📦 تم تحميل ${categoryProducts.length} فئة من المنتجات');
      for (final category in categoryProducts.keys) {
        developer.log('   📂 $category: ${categoryProducts[category]?.length ?? 0} منتج');
      }
      
      final realSections = categoryProducts.keys.toList();
      
      // 🔥 حفظ بيانات المطعم للاقتراحات في AppStateProvider
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      final businessSuggestionData = BusinessSuggestionData(
        businessId: widget.store.id,
        businessName: widget.store.name,
        businessType: widget.store.businessType,
        availableCategories: realSections,
      );
      appState.setBusinessSuggestionData(widget.store.id, businessSuggestionData);
      developer.log('💾 تم حفظ بيانات المطعم للاقتراحات: $businessSuggestionData');
      developer.log('🔍 businessType from Store: "${widget.store.businessType}"');
      developer.log('🔍 isRestaurant check: ${businessSuggestionData.isRestaurant}');
      developer.log('📋 availableCategories (${realSections.length}): ${realSections.join(", ")}');
      
      // إنشاء TabController جديد فقط إذا كانت هناك فئات
      TabController? newTabController;
      if (realSections.isNotEmpty) {
        newTabController = TabController(length: realSections.length, vsync: this);
      }

      // حفظ مرجع للـ TabController القديم للتخلص منه بأمان
      final oldController = _tabController;
      
      setState(() {
        _categoryProducts = categoryProducts;
        _isLoading = false;
        _dataLoaded = true; // تعيين حالة التحميل الناجح
        _tabController = newTabController;
        
        // تحديث keys للفئات الحقيقية
        _keys.clear();
        for (final categoryName in realSections) {
          _keys[categoryName] = GlobalKey();
        }
      });
      
      // التخلص من TabController القديم بأمان
      if (oldController != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }
      
      developer.log('✅ تم تحديث الواجهة بنجاح - ${categoryProducts.length} فئة');
    } catch (e) {
      developer.log('❌ خطأ في تحميل البيانات: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _dataLoaded = false; // إعادة تعيين حالة التحميل عند الخطأ
        });
      }
    }
  }

  Future<void> _loadWorkingHours() async {
    if (!mounted) return;
    
    setState(() {
      _loadingWorkingHours = true;
    });

    try {
      developer.log('🕒 جاري تحميل ساعات العمل للمطعم: ${widget.store.id}');
      
      // استخدام الطريقة الجديدة للحصول على ساعات العمل لجميع الأيام
      final allWorkingHours = await WorkingHoursService.getAllBusinessWorkingHours(widget.store.id);
      
      if (mounted) {
        setState(() {
          if (allWorkingHours != null && allWorkingHours.isNotEmpty) {
            _workingHours = BusinessWorkingHours(
              businessId: widget.store.id,
              workingHours: allWorkingHours,
            );
            developer.log('✅ تم تحميل ساعات العمل بنجاح - ${allWorkingHours.length} أيام');
            developer.log('📋 ساعات العمل: ${allWorkingHours.map((h) => '${h.weekday}: ${h.opening}-${h.closing}').join(', ')}');
          } else {
            _workingHours = null;
            developer.log('⚠️ لا توجد ساعات عمل محددة للمطعم');
          }
          _loadingWorkingHours = false;
        });
        
        if (_workingHours?.hasWorkingHours == true) {
          developer.log('📅 المطعم ${_workingHours?.isOpenNow == true ? "مفتوح" : "مغلق"} حالياً');
        }
      }
    } catch (e) {
      developer.log('❌ خطأ في تحميل ساعات العمل: $e');
      if (mounted) {
        setState(() {
          _loadingWorkingHours = false;
          // في حالة الخطأ، ننشئ كائن فارغ
          _workingHours = BusinessWorkingHours(
            businessId: widget.store.id,
            workingHours: [],
          );
        });
      }
    }
  }

  // 🔥 الاستماع لتحديثات polling وتحديث حالة المطعم
  void _listenToPollingUpdates() {
    _pollingUpdatesSubscription = _statusPolling.statusUpdates.listen(
      (update) {
        final businessId = update['businessId'] as String?;
        
        if (businessId == widget.store.id && mounted) {
          developer.log('🔔 StoreDetail: استلام تحديث polling للمطعم $businessId');
          _handleBusinessStatusUpdate(update);
        }
      },
      onError: (error) {
        developer.log('❌ StoreDetail: خطأ في استلام تحديثات polling: $error');
      },
    );
    
    developer.log('✅ StoreDetail: تم إعداد الاستماع لتحديثات polling');
  }

  void _updateCollapsedState() {
    if (!_scrollCtrl.hasClients) return;
    
    // حساب الموضع الدقيق لشريط التبويبات الأصلي
    // الهيدر الجديد: 540px (صورة الغلاف 500px + الحاوية البيضاء 40px)
    // محتويات الحاوية قبل التبويبات:
    // - Status Badge: ~60px
    // - معلومات التوصيل: ~80px  
    // - شريط البحث: ~50px
    // - المساحات: ~40px
    // إجمالي المحتوى قبل التبويبات: ~230px
    final tabBarActualPosition = 540.0 + 230.0; // ~770px
    final isCollapsed = _scrollCtrl.offset > tabBarActualPosition;
    
    if (isCollapsed != _collapsed) {
      setState(() {
        _collapsed = isCollapsed;
      });
    }
  }

  void _handleScrollTabSync() {
    if (_categoryProducts.isEmpty || _tabController == null) return;
    
    for (int i = 0; i < _categoryProducts.length; i++) {
      final key = _keys[_categoryProducts.keys.elementAt(i)];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox;
        final position = box.localToGlobal(Offset.zero, ancestor: null).dy;
        if (position >= 0 && position < 200) {
          if (_tabController!.index != i) {
            _tabController!.animateTo(i);
          }
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    developer.log('🎨 بناء StoreDetailScreen: _isLoading=$_isLoading, _error=$_error, categories=${_categoryProducts.length}');
    
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Stack(
        children: [
          Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.white,
            body: _isLoading
                ? _buildLoadingWidget()
                : _error != null
                    ? _buildErrorWidget()
                    : _categoryProducts.isEmpty || _hasNoProducts()
                        ? _buildEmptyWidget()
                        : _buildMainContent(),
          ),
          
          // شريط التطبيق المنهار (collapsed app bar)
          if (!_isLoading && _error == null && _categoryProducts.isNotEmpty && !_hasNoProducts())
            _buildCollapsedAppBar(),
          
          // شريط السلة كـ overlay منفصل
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildCartBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildCartBar() {
    return Builder(
      builder: (context) {
        return Consumer<AppStateProvider>(
          builder: (context, appState, child) {
            final hasCartItems = appState.hasCartItemsForStore(widget.store.id);
            developer.log('🛒 Consumer بناء _buildCartBar: hasCartItems=$hasCartItems');
            
            // إظهار الشريط فقط إذا كانت هناك عناصر في السلة لهذا المطعم
            if (!hasCartItems) {
              return const SizedBox.shrink();
            }
            
            return AnimatedCartBar(
              storeName: widget.store.name,
              isExpanded: true,
              storeId: widget.store.id,
              stores: [widget.store],
            );
          },
        );
      },
    );
  }

  Widget _buildMainContent() {
    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            _buildSliverInfoSection(),
            // محتوى المطعم الرئيسي
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white, // خلفية بيضاء صريحة
                child: Column(
                  children: [
                    // قسم معلومات التوصيل والاستلام - تصميم compact
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          // معلومات التوصيل
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'التوصيل',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.store.time,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // خط فاصل
                          Container(
                            width: 1,
                            height: 30,
                            color: Colors.grey.shade300,
                          ),
                          
                          // معلومات الرسوم
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'رسوم التوصيل',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.store.fee,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // شريط البحث الفعّال
                    InkWell(
                      onTap: _showSearchDialog, // تفعيل وظيفة البحث
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              color: Colors.grey.shade500,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'البحث في ${widget.store.name}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // شريط التبويبات كجزء من الحاوية البيضاء
                    if (_tabController != null)
                      Container(
                        color: Colors.transparent,
                        child: Material(
                          color: Colors.transparent,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            labelColor: Colors.black,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: AppColors.primary,
                            indicatorWeight: 3,
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.normal,
                              fontSize: 14,
                            ),
                            tabs: _categoryProducts.keys
                                .map((category) => Tab(
                                      child: SizedBox(
                                        width: 170,
                                        child: Text(
                                          _displayCategoryTitle(category, maxChars: 22),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            onTap: (index) {
                              final categoryName = _categoryProducts.keys.elementAt(index);
                              final key = _keys[categoryName];
                              if (key?.currentContext != null) {
                                Scrollable.ensureVisible(
                                  key!.currentContext!,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              }
                              HapticFeedback.lightImpact();
                            },
                          ),
                        ),
                      ),
                    
                    // عرض جميع الأقسام داخل نفس الحاوية
                    ...(_categoryProducts.keys.map((categoryTitle) => 
                      _buildIntegratedSection(categoryTitle)
                    ).toList()),
                    
                    // مساحة إضافية في النهاية
                    const SizedBox(height: 100), // مساحة إضافية للـ cart bar
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: _primaryPink,
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'جاري تحميل البيانات...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'خطأ في تحميل البيانات',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadBusinessData,
              icon: const Icon(Icons.refresh, color: AppColors.secondary),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryPink,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.restaurant_menu,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'لا توجد منتجات متاحة',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'يبدو أن هذا المطعم لم يضع منتجاته بعد\nجرب مطعماً آخر أو تحقق لاحقاً',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _loadBusinessData,
                  icon: const Icon(Icons.refresh, color: AppColors.secondary),
                  label: const Text(
                    'إعادة المحاولة',
                    style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryPink,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back, color: _primaryPink),
                  label: Text(
                    'العودة للمطاعم',
                    style: TextStyle(color: _primaryPink, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _primaryPink),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverInfoSection() {
    return SliverList(
      delegate: SliverChildListDelegate([
        // Header مع صورة الغلاف والمعلومات - تصميم Wendy's
        _buildWendysStyleHeader(),
      ]),
    );
  }

  /// تصميم Header يحاكي Wendy's مع صورة غلاف وطبقة معلومات
  Widget _buildWendysStyleHeader() {
    return SizedBox(
      height: 540, // ارتفاع الهيدر مع الحاوية البيضاء
      child: Stack(
        children: [
          // صورة الغلاف
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 500, // ارتفاع الصورة 500px
            child: Hero(
              tag: 'store_image_${widget.store.id}',
              child: Container(
                width: double.infinity,
                height: 480, // تقليل الارتفاع لإظهار المعلومات كاملة
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  // إزالة جميع الظلال
                ),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // صورة المطعم
                    if (widget.store.image.isNotEmpty && widget.store.image.contains('://'))
                      Image.network(
                        widget.store.image,
                        width: double.infinity,
                        height: 480, // تطابق الارتفاع المحدث للحاوية
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildDefaultBackgroundForHeader();
                        },
                      )
                    else
                      _buildDefaultBackgroundForHeader(),
                  
                  // طبقة overlay متدرجة محسنة - محدودة بنفس حجم الصورة
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.3),
                            Colors.black.withValues(alpha: 0.6),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  
                  // 🔥 طبقة overlay بيضاء خفيفة أسفل الصورة لتحسين التباين مع الحاوية البيضاء
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.2),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // تأثير لمعان خفيف
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.1),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.05),
                          ],
                          stops: const [0.0, 0.3, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
          
          // زر الرجوع
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: _buildActionButton(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          
          // أيقونات التفاعل في الأسفل اليسار مع انيميشن
          Positioned(
            bottom: 104, // رفع الأيقونات بـ 20 بكسل إضافية لتتناسق مع معلومات المطعم
            left: 16,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 800),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(-50 * (1 - value), 0),
                  child: Opacity(
                    opacity: value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // أيقونة المعلومات مع انيميشن - الأولى من الأعلى
                        _buildAnimatedActionButton(
                          icon: Icons.info_outline,
                          delay: const Duration(milliseconds: 200),
                          onPressed: () {
                            _showStoreInfoBottomSheet();
                          },
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // أيقونة القلب للتفضيل مع انيميشن - الثانية
                        Consumer<FavoritesModel>(
                          builder: (context, favoritesModel, child) {
                            final isFav = favoritesModel.isStoreFavorite(widget.store.id);
                            return _buildAnimatedActionButton(
                              icon: isFav ? Icons.favorite : Icons.favorite_border,
                              iconColor: AppColors.secondary, // استخدام اللون الثانوي دائماً
                              delay: const Duration(milliseconds: 100),
                              onPressed: () async {
                                HapticFeedback.lightImpact();
                                try {
                                  await favoritesModel.toggleStoreFavorite(
                                    widget.store.id,
                                    widget.store.name,
                                    storeImage: widget.store.image,
                                    storeCategory: widget.store.category,
                                  );
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('حدث خطأ في تحديث المفضلة: ${e.toString()}'),
                                        backgroundColor: AppColors.secondary,
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // شعار المطعم مع انيميشن - الأخيرة وأكبر من البقية
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 600),
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          builder: (context, logoValue, child) {
                            return Transform.scale(
                              scale: logoValue,
                              child: _buildEnhancedRestaurantLogo(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          

          
          // معلومات المطعم على الجهة اليمنى مع انيميشن
          Positioned(
            bottom: 104, // رفع المعلومات بـ 20 بكسل إضافية عن صورة الغلاف
            right: 16,
            left: 80, // مساحة للأيقونات على اليسار
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 1000),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 50 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // اسم المطعم بخط كبير وتأثير متدرج
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            widget.store.name,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              foreground: Paint()
                                ..shader = LinearGradient(
                                  colors: [
                                    Colors.white,
                                    Colors.white.withValues(alpha: 0.9),
                                  ],
                                ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 2),
                                  blurRadius: 6,
                                  color: Colors.black54,
                                ),
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                  color: Colors.black38,
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // التقييم والمراجعات بتصميم بسيط
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.store.rating,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(${_getReviewsText()})',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // عنوان المطعم بتصميم بسيط
                        if (widget.store.address.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: Colors.white.withValues(alpha: 0.8),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.store.address,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        
                        const SizedBox(height: 12),
                        
                        // معلومات سريعة محسنة (وقت التوصيل، المسافة، والرسوم)
                        Row(
                          children: [
                            _buildEnhancedQuickInfo(Icons.access_time, widget.store.time, 'دقيقة'),
                            const SizedBox(width: 16),
                            if (widget.store.distance.isNotEmpty) ...[
                              _buildEnhancedQuickInfo(Icons.location_on, widget.store.distance, ''),
                              const SizedBox(width: 16),
                            ],
                            _buildEnhancedQuickInfo(Icons.delivery_dining, widget.store.fee, ''),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // 🎯 الحاوية البيضاء النظيفة مع Status Badge في الجهة اليسرى
          Positioned(
            bottom: 20, // تقليل offset لخفض الحاوية أكثر من الصورة
            left: 0,
            right: 0,
            height: 60,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
                // إزالة جميع الظلال
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    // Status Badge في الجهة اليسرى
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 800),
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Opacity(
                            opacity: value,
                            child: _buildSimpleBusinessStatusBadge(),
                          ),
                        );
                      },
                    ),
                    const Spacer(), // مساحة فارغة لدفع المحتوى للأطراف
                    // يمكن إضافة عناصر أخرى في الجهة اليمنى لاحقاً
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }



  /// خلفية افتراضية للهيدر مع ارتفاع مخصص
  Widget _buildDefaultBackgroundForHeader() {
    return Container(
      width: double.infinity,
      height: 480, // تطابق الارتفاع المحدث للصورة
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.6),
            AppColors.secondary.withValues(alpha: 0.8),
            AppColors.primary.withValues(alpha: 0.4),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // تأثير دوائر خلفية
          Positioned(
            top: 50,
            right: 30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 50,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          // أيقونة المطعم الرئيسية
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.restaurant_menu,
              size: 80,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// زر التفاعل الدائري المحسن
  Widget _buildActionButton({
    required IconData icon,
    Color? iconColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 44, // زيادة الحجم من 36 إلى 44
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary, // Border باللون الأساسي
          width: 2, // زيادة سمك البوردر قليلاً
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: iconColor ?? AppColors.secondary,
          size: 20, // زيادة حجم الأيقونة من 16 إلى 20
        ),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// زر التفاعل الدائري المتحرك
  Widget _buildAnimatedActionButton({
    required IconData icon,
    Color? iconColor,
    Duration delay = Duration.zero,
    required VoidCallback onPressed,
  }) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 500 + delay.inMilliseconds),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: _buildActionButton(
            icon: icon,
            iconColor: iconColor,
            onPressed: onPressed,
          ),
        );
      },
    );
  }

  /// شعار المطعم المحسن الكبير للأسفل اليسار
  Widget _buildEnhancedRestaurantLogo() {
    return Container(
      width: 60, // زيادة الحجم من 50 إلى 60 ليكون أكبر بشكل ملحوظ من الأيقونات (44)
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary, // Border باللون الأساسي
          width: 2, // زيادة سمك البوردر
        ),
      ),
      child: ClipOval(
        child: widget.store.image.isNotEmpty && widget.store.image.contains('://')
            ? Image.network(
                widget.store.image,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildEnhancedDefaultLogo();
                },
              )
            : _buildEnhancedDefaultLogo(),
      ),
    );
  }



  /// شعار افتراضي محسن كبير
  Widget _buildEnhancedDefaultLogo() {
    return Container(
      width: 60, // تحديث الحجم ليتناسب مع الحاوية الجديدة
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.3),
            AppColors.secondary.withValues(alpha: 0.2),
            AppColors.primary.withValues(alpha: 0.1),
          ],
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.restaurant_menu,
        color: AppColors.secondary,
        size: 28, // زيادة حجم الأيقونة الداخلية من 24 إلى 28
      ),
    );
  }





  /// معلومات سريعة بتصميم بسيط ونظيف
  Widget _buildEnhancedQuickInfo(IconData icon, String text, String suffix) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.8),
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          suffix.isNotEmpty ? '$text $suffix' : text,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.8),
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// نص المراجعات
  String _getReviewsText() {
    // يمكن ربطها بالبيانات الفعلية لاحقاً
    return '100+ مراجعة';
  }

  /// عرض معلومات إضافية عن المطعم
  void _showStoreInfoBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معلومات ${widget.store.name}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // معلومات تفصيلية
                      _buildInfoRow(Icons.star, 'التقييم', widget.store.rating),
                      _buildInfoRow(Icons.access_time, 'وقت التوصيل', widget.store.time),
                      _buildInfoRow(Icons.delivery_dining, 'رسوم التوصيل', widget.store.fee),
                      if (widget.store.address.isNotEmpty)
                        _buildInfoRow(Icons.location_on, 'العنوان', widget.store.address),
                      if (widget.store.category != null)
                        _buildInfoRow(Icons.restaurant_menu, 'الفئة', widget.store.category!),
                      
                      const SizedBox(height: 24),
                      
                      // قسم ساعات العمل المحسن
                      _buildEnhancedWorkingHoursSection(setSheetState),
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// صف معلومات في Bottom Sheet
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.secondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }





  /// بناء قسم متكامل داخل الحاوية الموحدة بحواف مستديرة
  Widget _buildIntegratedSection(String title) {
    final products = _categoryProducts[title] ?? [];
    
    return Container(
      key: _keys[title],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // خط فاصل بين الأقسام (عدا القسم الأول)
          if (_categoryProducts.keys.first != title)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.grey[300]!,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          
          // عنوان القسم
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _displayCategoryTitle(title, maxChars: 40),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${products.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // قائمة المنتجات
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return _buildProductCard(product);
            },
          ),
        ],
      ),
    );
  }



  Widget _buildProductCard(ProductModel product) {
    // 🔥 استخدام نظام الأولويات المتطور لتحديد حالة إتاحة الطبق
    final dishAvailability = _getDishAvailability(product);
    final canOrder = dishAvailability.isAvailable;
    
    // التحقق من حالة المطعم
    final canRestaurantAcceptOrders = _canRestaurantAcceptOrders();
    final isRestaurantUnavailable = !canRestaurantAcceptOrders;
    final isCompletelyUnavailable = isRestaurantUnavailable || !canOrder;
    
    developer.log('🎯 StoreDetailScreen _buildProductCard للمنتج ${product.name}:');
    developer.log('   - _availabilityStatus != null: ${_availabilityStatus != null}');
    if (_availabilityStatus != null) {
      developer.log('   - _availabilityStatus.isWithinWorkingHours: ${_availabilityStatus!.isWithinWorkingHours}');
      developer.log('   - _availabilityStatus.acceptingOrders: ${_availabilityStatus!.acceptingOrders}');
      developer.log('   - _availabilityStatus.isAvailable: ${_availabilityStatus!.isAvailable}');
    }
    developer.log('   - dishAvailability.reasonText: ${dishAvailability.reasonText}');
    developer.log('   - canOrder: $canOrder');
    developer.log('   - isRestaurantUnavailable: $isRestaurantUnavailable');
    developer.log('   - isCompletelyUnavailable: $isCompletelyUnavailable');
    
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween<double>(begin: 1.0, end: isCompletelyUnavailable ? 0.6 : 1.0),
      builder: (context, opacity, child) {
        return Transform.scale(
          scale: isCompletelyUnavailable ? 0.98 : 1.0,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isCompletelyUnavailable 
                ? Colors.grey.shade100 
                : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isCompletelyUnavailable 
                ? Border.all(color: Colors.grey.shade300, width: 1)
                : null,
              boxShadow: isCompletelyUnavailable
                ? [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
            ),
            child: Stack(
              children: [
                // محتوى الكارت الأساسي
                Opacity(
                  opacity: opacity,
                  child: child!,
                ),
                
                // طبقة التعتيم والرسالة عند عدم توفر المطعم
                if (isRestaurantUnavailable)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _getRestaurantStatusColor().withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),                           child: Row(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               Icon(
                                 _getRestaurantStatusIcon(),
                                 color: AppColors.secondary,
                                 size: 16,
                               ),
                               const SizedBox(width: 6),
                               Text(
                                 _getRestaurantStatusMessage() ?? 'غير متاح',
                                 style: const TextStyle(
                                   color: AppColors.secondary,
                                   fontSize: 12,
                                   fontWeight: FontWeight.w600,
                                 ),
                               ),                    ],
                  ),
                ),
              ),
            ),
          ),
          

              ],
            ),
          ),
        );
      },
      child: InkWell(
        onTap: () async {
          // التحقق من حالة المطعم أولاً
          bool canRestaurantAcceptOrders = _canRestaurantAcceptOrders();
          String? restaurantStatusMessage = _getRestaurantStatusMessage();
          
          if (!canRestaurantAcceptOrders) {
            // عرض رسالة حالة المطعم
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_getRestaurantStatusIcon(), color: AppColors.secondary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          restaurantStatusMessage ?? 'المطعم غير متاح حالياً',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                backgroundColor: _getRestaurantStatusColor().withValues(alpha: 0.9),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: EdgeInsets.fromLTRB(16, 16, 16, 
                  MediaQuery.of(context).padding.bottom + 100
                ),
                duration: const Duration(seconds: 3),
                elevation: 6,
              ),
            );
            return;
          }
          
          // التحقق من حالة الطبق الفردي
          if (!canOrder) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(dishAvailability.icon, color: AppColors.secondary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dishAvailability.message,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                backgroundColor: dishAvailability.statusColor.withValues(alpha: 0.9),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: EdgeInsets.fromLTRB(16, 16, 16, 
                  MediaQuery.of(context).padding.bottom + 100
                ),
                duration: const Duration(seconds: 3),
                elevation: 6,
              ),
            );
            return;
          }
          
          // الطبق والمطعم متاحان - المتابعة للشاشة التفصيلية
          try {
            final dish = Dish(
              id: product.id,
              name: product.name,
              description: product.description,
              imageUrls: product.imageUrl.isNotEmpty ? [product.imageUrl] : [],
              likesPercent: 85,
              likesCount: 120,
              basePrice: product.price,
              optionGroups: [],
            );
            
            developer.log('🔄 بدء التنقل لشاشة تفاصيل الطبق');
            developer.log('  منتج: ${product.name}');
            developer.log('  تمرير productData: نعم');
            
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DishDetailScreen(
                  dish: dish,
                  storeId: widget.store.id,
                  storeName: widget.store.name, // تمرير اسم المتجر
                  storeAddress: widget.store.address, // تمرير عنوان المتجر للسائقين
                  productData: product, // تمرير بيانات المنتج الكاملة
                ),
              ),
            );
            
            developer.log('🔙 العودة من شاشة تفاصيل الطبق');
            developer.log('  النتيجة: $result');
            developer.log('  حالة البيانات الحالية: _isLoading=$_isLoading, _error=$_error, categories=${_categoryProducts.length}');
            
            // التحقق من البيانات بعد العودة وإعادة تحميلها إذا لزم الأمر
            if (mounted) {
              // التحقق من حالة البيانات وإعادة تحميلها فقط إذا كانت مفقودة حقاً
              if (!_dataLoaded && _categoryProducts.isEmpty && _error == null && !_isLoading) {
                developer.log('⚠️ البيانات مفقودة بعد العودة - إعادة تحميل');
                _loadBusinessData();
              }
            }
          } catch (e) {
            developer.log('❌ خطأ في التنقل: $e');
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 120,
            child: Row(
              children: [
                // معلومات المنتج - الجهة اليمنى
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // اسم الطبق
                      Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: canOrder ? Colors.black87 : Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 6),
                      
                      // وصف الطبق
                      if (product.description.isNotEmpty)
                        Expanded(
                          child: Text(
                            product.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: canOrder ? Colors.grey[600] : Colors.grey.shade500,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      
                      const Spacer(),
                      
                      // السعر والمعلومات السفلية
                      Row(
                        children: [
                          if (canOrder)
                            // السعر بتصميم بسيط
                            Text(
                              '${product.price.toStringAsFixed(0)} د.ع',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: Colors.black,
                              ),
                            )
                          else
                            // حالة عدم الإتاحة
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  dishAvailability.icon,
                                  color: dishAvailability.statusColor,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  dishAvailability.reasonText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: dishAvailability.statusColor,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // صورة المنتج - الجهة اليسرى
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // الصورة الأساسية
                            product.imageUrl.isNotEmpty
                                ? Image.network(
                                    product.imageUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        color: Colors.grey[200],
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            color: _primaryPink,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              _primaryPink.withValues(alpha: 0.3),
                                              _primaryPink.withValues(alpha: 0.6),
                                            ],
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.fastfood,
                                          size: 40,
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
                                          _primaryPink.withValues(alpha: 0.3),
                                          _primaryPink.withValues(alpha: 0.6),
                                        ],
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.fastfood,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                            
                            // طبقة عدم الإتاحة للطبق الفردي فقط
                            if (!canOrder)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Icon(
                                    dishAvailability.icon,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    
                    // زر الإضافة في الزاوية السفلى اليسرى
                    if (canOrder && !isRestaurantUnavailable)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 300),
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  // إضافة الطبق إلى السلة مباشرة
                                  _addToCart(product);
                                },
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: AppColors.secondary,
                                    size: 20,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// قسم ساعات العمل المحسن في Bottom Sheet
  Widget _buildEnhancedWorkingHoursSection(StateSetter setSheetState) {
    // إذا كان يتم تحميل البيانات
    if (_loadingWorkingHours) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!, width: 1),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: AppColors.secondary,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'جاري تحميل ساعات العمل...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // إذا لم تتوفر بيانات ساعات العمل
    if (_workingHours == null || !_workingHours!.hasWorkingHours) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.grey[400],
              size: 24,
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'ساعات العمل غير متوفرة حالياً',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // تحديد الحالة الحالية
    bool? isWithinWorkingHours;
    String currentStatusText = '';
    
    if (_availabilityStatus != null) {
      isWithinWorkingHours = _availabilityStatus!.isWithinWorkingHours;
      currentStatusText = isWithinWorkingHours == true 
          ? _getWorkingHoursStatusText() 
          : 'مغلق حالياً';
    } else if (_workingHours != null) {
      final statusInfo = _workingHours!.statusInfo;
      isWithinWorkingHours = statusInfo['isOpen'] as bool;
      currentStatusText = statusInfo['text'] as String;
    }

    // تحديد أيقونة الحالة الحالية
    IconData currentStatusIcon = isWithinWorkingHours == true 
        ? Icons.check_circle 
        : Icons.cancel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عنوان القسم
        Row(
          children: [
            Icon(
              Icons.access_time,
              color: AppColors.secondary,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              'ساعات العمل',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // الحالة الحالية
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                currentStatusIcon,
                color: isWithinWorkingHours == true ? AppColors.secondary : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الحالة الحالية',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentStatusText.isNotEmpty ? currentStatusText : 'غير محددة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isWithinWorkingHours == true ? AppColors.secondary : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // جدول ساعات العمل
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!, width: 1),
          ),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Text(
                  'ساعات العمل',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              // Days list
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _workingHours!.sortedWorkingHours.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.grey[200],
                ),
                itemBuilder: (context, index) {
                  final dayHours = _workingHours!.sortedWorkingHours[index];
                  // 🔥 استخدام اليوم الحالي من Backend (timezone المطعم) بدلاً من DateTime.now()
                  final isToday = _currentWeekdayFromBackend != null
                      ? dayHours.weekday.toLowerCase() == _currentWeekdayFromBackend!.toLowerCase()
                      : dayHours.weekday.toLowerCase() == _getCurrentWeekday(DateTime.now().weekday).toLowerCase();
                  
                  String displayText = 'غير متاح';
                  bool isDayClosed = false;
                  
                  // تحديد نص العرض وحالة اليوم
                  if (_workingHours != null && _workingHours!.hasWorkingHours) {
                    final dayName = dayHours.weekday.toLowerCase();
                    final matchingApiData = _workingHours!.sortedWorkingHours
                        .where((apiDay) => apiDay.weekday.toLowerCase() == dayName)
                        .firstOrNull;
                    
                    if (matchingApiData != null) {
                      if (matchingApiData.isWorkingDay && 
                          matchingApiData.opening.isNotEmpty && 
                          matchingApiData.closing.isNotEmpty && 
                          matchingApiData.opening != 'none' && 
                          matchingApiData.closing != 'none' &&
                          matchingApiData.opening != 'closed' && 
                          matchingApiData.closing != 'closed') {
                        displayText = '${_formatTimeTo12Hour(matchingApiData.opening)} - ${_formatTimeTo12Hour(matchingApiData.closing)}';
                        isDayClosed = false;
                      } else {
                        displayText = 'مغلق';
                        isDayClosed = true;
                      }
                    } else {
                      displayText = 'مغلق';
                      isDayClosed = true;
                    }
                  }
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    color: isToday ? Colors.grey[100] : Colors.transparent,
                    child: Row(
                      children: [
                        // Day indicator
                        if (isToday)
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        if (isToday) const SizedBox(width: 12),
                        
                        // Day name
                        Expanded(
                          flex: 2,
                          child: Text(
                            dayHours.arabicWeekday,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                              color: isToday ? AppColors.primary : Colors.black87,
                            ),
                          ),
                        ),
                        
                        // Status icon and time
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Icon(
                                isDayClosed ? Icons.block : Icons.access_time,
                                size: 16,
                                color: isDayClosed ? AppColors.primary : AppColors.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                    color: isDayClosed 
                                        ? AppColors.primary 
                                        : (isToday ? AppColors.primary : Colors.grey[700]),
                                  ),
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }



  String _getCurrentWeekday(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Monday';
    }
  }

  /// تحديد نص حالة ساعات العمل بناءً على البيانات المتوفرة
  String _getWorkingHoursStatusText() {
    try {
      // 🔥 استخدام isWithinWorkingHours من _availabilityStatus (محسوب في Backend بـ timezone المطعم)
      // بدلاً من الحساب المحلي الذي يستخدم timezone الجهاز
      final isWithinWorkingHoursFromAPI = _availabilityStatus?.isWithinWorkingHours ?? false;
      
      // 🔥 أولوية عليا: استخدام بيانات _workingHours من API (البيانات الصحيحة)
      if (_workingHours != null && _workingHours!.hasWorkingHours) {
        final todayWorkingHours = _workingHours!.todayWorkingHours;
        
        // فحص إذا كان اليوم له ساعات عمل صحيحة
        if (todayWorkingHours != null && 
            todayWorkingHours.isWorkingDay &&
            todayWorkingHours.opening.isNotEmpty &&
            todayWorkingHours.closing.isNotEmpty &&
            todayWorkingHours.opening != 'none' &&
            todayWorkingHours.closing != 'none' &&
            todayWorkingHours.opening != 'closed' &&
            todayWorkingHours.closing != 'closed') {
          
          // 🔥 استخدام الحساب من Backend بدلاً من الحساب المحلي
          // لأن Backend يستخدم timezone المطعم وليس timezone الجهاز
          if (isWithinWorkingHoursFromAPI) {
            // المطعم مفتوح الآن - اعرض وقت الإغلاق
            final closingTime = _formatTimeTo12Hour(todayWorkingHours.closing);
            return 'مفتوح حتى $closingTime';
          } else {
            // المطعم مغلق الآن - اعرض وقت الفتح القادم
            final openingTime = _formatTimeTo12Hour(todayWorkingHours.opening);
            return 'مغلق - يفتح الساعة $openingTime';
          }
        } else {
          // اليوم مغلق - لا توجد ساعات عمل صحيحة
          return 'مغلق';
        }
      }
      
      // احتياطي: إذا لم تتوفر بيانات API، استخدم _availabilityStatus
      if (_availabilityStatus != null && _availabilityStatus!.workingHours.isNotEmpty) {
        final now = DateTime.now();
        final dayName = _getDayNameFromWeekday(now.weekday);
        final todayHours = _availabilityStatus!.workingHours[dayName];
        
        if (todayHours != null) {
          // فحص إذا كان اليوم مغلق
          if (todayHours.opening.isEmpty || todayHours.closing.isEmpty || 
              todayHours.opening == 'none' || todayHours.closing == 'none' ||
              todayHours.opening == 'closed' || todayHours.closing == 'closed') {
            return 'مغلق';
          }
          
          // 🔥 استخدام الحساب من Backend (نفس المنطق في الجزء الرئيسي)
          if (isWithinWorkingHoursFromAPI) {
            final closingTime = _formatTimeTo12Hour(todayHours.closing);
            return 'مفتوح حتى $closingTime';
          } else {
            final openingTime = _formatTimeTo12Hour(todayHours.opening);
            return 'مغلق - يفتح الساعة $openingTime';
          }
        }
      }
      
      return 'ساعات العمل غير محددة';
    } catch (e) {
      developer.log('❌ خطأ في تحديد نص حالة ساعات العمل: $e');
      return 'ساعات العمل غير محددة';
    }
  }

  /// تحويل رقم اليوم إلى اسم اليوم بالإنجليزية (بأحرف كبيرة تطابق تنسيق API)
  String _getDayNameFromWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }

  /// تحويل الوقت من 24 ساعة إلى 12 ساعة
  String _formatTimeTo12Hour(String time24) {
    try {
      final parts = time24.split(':');
      if (parts.length != 2) return time24;
      
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      
      if (hour == 0) {
        return '12:${minute.toString().padLeft(2, '0')} ص';
      } else if (hour < 12) {
        return '$hour:${minute.toString().padLeft(2, '0')} ص';
      } else if (hour == 12) {
        return '12:${minute.toString().padLeft(2, '0')} م';
      } else {
        return '${hour - 12}:${minute.toString().padLeft(2, '0')} م';
      }
    } catch (e) {
      return time24;
    }
  }

  /// بناء مؤشر حالة المطعم البسيط تحت صورة الغلاف (المكان الوحيد لعرض حالة المطعم)
  /// حالات "مغلق" و "مشغول" تظهر هنا فقط وليس على الأطباق الفردية
  Widget _buildSimpleBusinessStatusBadge() {
    if (_loadingBusinessStatus) {
      // حالة التحميل - بادج واضحة مع انيميشن
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'جاري التحديث...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    if (_availabilityStatus != null) {
      final isAvailable = _availabilityStatus!.isAvailable;
      final acceptingOrders = _availabilityStatus!.acceptingOrders;
      final isWithinWorkingHours = _availabilityStatus!.isWithinWorkingHours;
      final reasonUnavailable = _availabilityStatus!.reasonUnavailable;
      
      // 🔥 تسجيل الحالة الحالية للتشخيص
      developer.log('🎨 StoreDetailScreen: عرض بادج الحالة:');
      developer.log('   - isAvailable: $isAvailable');
      developer.log('   - acceptingOrders: $acceptingOrders');
      developer.log('   - isWithinWorkingHours: $isWithinWorkingHours');
      developer.log('   - reasonUnavailable: $reasonUnavailable');
      
      // 🔥 الأولوية لـ isAvailable (الحالة الإجمالية من API)
      if (!isAvailable) {
        // المطعم غير متاح - تحديد السبب
        if (!isWithinWorkingHours) {
          // مغلق بسبب ساعات العمل
          return _buildProminentStatusBadge(
            text: 'مغلق',
            icon: Icons.access_time,
            backgroundColor: Colors.red.shade50,
            textColor: Colors.red.shade700,
            borderColor: Colors.red.shade200,
            iconColor: Colors.red.shade600,
          );
        } else if (!acceptingOrders) {
          // مشغول أو لا يستقبل طلبات
          return _buildProminentStatusBadge(
            text: reasonUnavailable?.isNotEmpty == true ? reasonUnavailable! : 'مشغول',
            icon: Icons.pause_circle,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            textColor: AppColors.primary,
            borderColor: AppColors.primary.withValues(alpha: 0.3),
            iconColor: AppColors.primary,
          );
        } else {
          // غير متاح لسبب آخر
          return _buildProminentStatusBadge(
            text: reasonUnavailable?.isNotEmpty == true ? reasonUnavailable! : 'غير متاح',
            icon: Icons.cancel,
            backgroundColor: Colors.red.shade50,
            textColor: Colors.red.shade700,
            borderColor: Colors.red.shade200,
            iconColor: Colors.red.shade600,
          );
        }
      }
      
      // 🔥 تحقق من ساعات العمل حتى لو كان متاح
      if (!isWithinWorkingHours) {
        // مغلق بسبب ساعات العمل
        return _buildProminentStatusBadge(
          text: 'مغلق',
          icon: Icons.access_time,
          backgroundColor: Colors.red.shade50,
          textColor: Colors.red.shade700,
          borderColor: Colors.red.shade200,
          iconColor: Colors.red.shade600,
        );
      }
      
      // 4. متاح ومفتوح - بادج خضراء بارزة
      return _buildProminentStatusBadge(
        text: 'مفتوح',
        icon: Icons.check_circle,
        backgroundColor: Colors.green.shade50,
        textColor: Colors.green.shade700,
        borderColor: Colors.green.shade200,
        iconColor: Colors.green.shade600,
      );
    } else if (_workingHours != null) {
      // الرجوع لـ _workingHours كخيار احتياطي
      final isOpenNow = _workingHours!.isOpenNow;
      
      if (!isOpenNow) {
        return _buildProminentStatusBadge(
          text: 'مغلق حالياً',
          icon: Icons.access_time,
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          textColor: AppColors.primary,
          borderColor: AppColors.primary.withValues(alpha: 0.3),
          iconColor: AppColors.primary,
        );
      } else {
        return _buildProminentStatusBadge(
          text: 'مفتوح',
          icon: Icons.check_circle,
          backgroundColor: Colors.green.shade50,
          textColor: Colors.green.shade700,
          borderColor: Colors.green.shade200,
          iconColor: Colors.green.shade600,
        );
      }
    } else {
      // حالة افتراضية - بادج رمادية
      return _buildProminentStatusBadge(
        text: 'جاري التحقق...',
        icon: Icons.refresh,
        backgroundColor: Colors.grey.shade100,
        textColor: Colors.grey.shade600,
        borderColor: Colors.grey.shade300,
        iconColor: Colors.grey.shade500,
      );
    }
  }

  /// بناء بادج حالة المطعم البارزة والواضحة
  Widget _buildProminentStatusBadge({
    required String text,
    required IconData icon,
    required Color backgroundColor,
    required Color textColor,
    required Color borderColor,
    required Color iconColor,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween<double>(begin: 0.8, end: 1.0),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: borderColor, width: 1.5),
              // إزالة جميع الظلال من Status Badge
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: iconColor,
                ),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// تحميل حالة المطعم من RestaurantAvailabilityService الجديد
  Future<void> _loadBusinessStatus({bool skipCache = false}) async {
    if (!mounted) return;
    
    setState(() {
      _loadingBusinessStatus = true;
    });

    try {
      developer.log('🔍 جاري تحميل حالة المطعم: ${widget.store.id}');
      
      // استخدام الخدمة الجديدة
      final availabilityStatus = await _availabilityService.checkRestaurantAvailability(
        widget.store.id,
        skipCache: skipCache,
      );
      
      if (mounted) {
        setState(() {
          _availabilityStatus = availabilityStatus;
          _loadingBusinessStatus = false;
        });
        
        developer.log('✅ تم تحميل حالة المطعم: ${availabilityStatus.isAvailable ? "متاح" : availabilityStatus.reasonUnavailable}');
      }
    } catch (e) {
      developer.log('❌ خطأ في تحميل حالة المطعم: $e');
      if (mounted) {
        setState(() {
          _loadingBusinessStatus = false;
          // إنشاء حالة افتراضية متاحة عند الخطأ (بدلاً من غير متاحة)
          // هذا يضمن أن المطاعم تبقى قابلة للطلب حتى عند فشل تحميل الحالة
          _availabilityStatus = RestaurantAvailabilityStatus(
            businessId: widget.store.id,
            isAvailable: true, // افتراضياً متاح
            acceptingOrders: true, // افتراضياً يقبل طلبات
            isWithinWorkingHours: true, // افتراضياً مفتوح
            workingHours: {},
            checkedAt: DateTime.now(),
            reasonUnavailable: '', // لا يوجد سبب لعدم التوفر
          );
        });
        
        developer.log('⚠️ تم استخدام حالة افتراضية متاحة بسبب فشل تحميل حالة المطعم');
      }
    }
  }
  /// معالجة التحديث الفوري لحالة المطعم مع دعم كامل لتحديثات ساعات العمل و isClosed
  Future<void> _handleBusinessStatusUpdate(Map<String, dynamic> updateData) async {
    try {
      developer.log('🚀 StoreDetailScreen: دخل _handleBusinessStatusUpdate مع بيانات: $updateData');
      
      final businessId = updateData['businessId'] as String?;
      // توحيد المفاتيح بين polling و WebSocket
      final canAcceptOrders = (updateData['canAcceptOrders'] as bool?) ?? (updateData['acceptingOrders'] as bool?);
      final isBusy = updateData['isBusy'] as bool?;
      final statusMessage = updateData['statusMessage'] as String?;
      final isAvailableDirect = updateData['isAvailable'] as bool?; // من polling
      final isWithinWorkingHoursDirect = updateData['isWithinWorkingHours'] as bool?; // من polling
      final source = updateData['source'] as String?; // 'polling' أو نوع الحدث
      
      // 🔥 معالجة تحديثات ساعات العمل و isClosed
      final workingHours = updateData['workingHours'] as Map<String, dynamic>?;
      final workingHoursUpdated = updateData['workingHoursUpdated'] as bool?;
      final forceStatusRecheck = updateData['forceStatusRecheck'] as bool?;
      final dayUpdated = updateData['dayUpdated'] as String?;
      final isClosedToday = updateData['isClosed'] as bool?;
      final isDayClosed = updateData['isDayClosed'] as bool?;
      final eventType = updateData['eventType'] as String?;

      if (businessId == widget.store.id && mounted) {
        developer.log('🔄 StoreDetailScreen: تحديث فوري لحالة المطعم ${widget.store.id}');
        developer.log('   - canAcceptOrders: $canAcceptOrders');
        developer.log('   - isBusy: $isBusy');
        developer.log('   - statusMessage: $statusMessage');
        developer.log('   - workingHoursUpdated: $workingHoursUpdated');
        developer.log('   - workingHours: $workingHours');
        developer.log('   - forceStatusRecheck: $forceStatusRecheck');
        developer.log('   - dayUpdated: $dayUpdated');
        developer.log('   - isClosedToday: $isClosedToday');
        developer.log('   - isDayClosed: $isDayClosed');
        developer.log('   - eventType: $eventType');

        // 🔥 معالجة خاصة لتحديثات isClosed (تحديث فوري بدون استدعاء الخادم)
        if ((eventType == 'day_closed' || eventType == 'day_opened' || eventType == 'working_hours_update') &&
            workingHoursUpdated == true && workingHours != null) {
          
          developer.log('⚡ StoreDetailScreen: معالجة فورية لتحديث isClosed/ساعات العمل');
          
          // تحديث فوري لحالة ساعات العمل
          final Map<String, WorkingHours?> convertedWorkingHours = {};
          workingHours.forEach((day, hoursData) {
            if (hoursData is Map<String, dynamic>) {
              // فحص حالة isClosed
              final isClosed = hoursData['isClosed'] as bool? ?? false;
              final opening = hoursData['open'] as String? ?? hoursData['opening'] as String? ?? '';
              final closing = hoursData['close'] as String? ?? hoursData['closing'] as String? ?? '';
              
              if (isClosed) {
                // إذا كان مغلق، ضع قيم خاصة
                convertedWorkingHours[day] = WorkingHours(opening: '', closing: '');
              } else {
                // إذا كان مفتوح، استخدم الساعات الفعلية
                convertedWorkingHours[day] = WorkingHours(opening: opening, closing: closing);
              }
              
              developer.log('   - $day: isClosed=$isClosed, opening=$opening, closing=$closing');
            }
          });
          
          // تحديد حالة isWithinWorkingHours الجديدة
          final now = DateTime.now();
          final currentDayName = _getDayNameFromWeekday(now.weekday);
          bool newIsWithinWorkingHours = true;
          
          // البحث عن اليوم الحالي في البيانات المحدثة
          for (final dayName in ['saturday', 'Saturday', 'SATURDAY', currentDayName]) {
            final todayData = workingHours[dayName];
            if (todayData is Map<String, dynamic>) {
              final isClosed = todayData['isClosed'] as bool? ?? false;
              if (isClosed) {
                newIsWithinWorkingHours = false;
                developer.log('🚫 المطعم مغلق اليوم: $dayName (isClosed=true)');
                break;
              } else {
                // فحص ساعات العمل العادية
                final opening = todayData['open'] as String? ?? todayData['opening'] as String? ?? '';
                final closing = todayData['close'] as String? ?? todayData['closing'] as String? ?? '';
                if (opening.isNotEmpty && closing.isNotEmpty && opening != 'none' && closing != 'none') {
                  // فحص إذا كان الوقت الحالي ضمن ساعات العمل
                  newIsWithinWorkingHours = _isCurrentTimeWithinWorkingHours(opening, closing);
                  developer.log('⏰ فحص ساعات العمل: $opening-$closing -> $newIsWithinWorkingHours');
                }
                break;
              }
            }
          }
          
          // إنشاء حالة جديدة مع البيانات المحدثة فورياً
          final newAvailabilityStatus = RestaurantAvailabilityStatus(
            businessId: widget.store.id,
            isAvailable: (canAcceptOrders ?? (_availabilityStatus?.acceptingOrders ?? true)) && newIsWithinWorkingHours,
            acceptingOrders: canAcceptOrders ?? (_availabilityStatus?.acceptingOrders ?? true),
            isWithinWorkingHours: newIsWithinWorkingHours,
            workingHours: convertedWorkingHours,
            checkedAt: DateTime.now(),
            reasonUnavailable: _getReasonFromStatus(isBusy, canAcceptOrders, statusMessage, newIsWithinWorkingHours),
          );
          
          // تطبيق التحديث فورياً
          setState(() {
            _availabilityStatus = newAvailabilityStatus;
            _loadingBusinessStatus = false;
          });
          
          developer.log('✅ تم تحديث فوري لحالة isClosed في StoreDetailScreen:');
          developer.log('   - isWithinWorkingHours: $newIsWithinWorkingHours');
          developer.log('   - isAvailable: ${newAvailabilityStatus.isAvailable}');
          developer.log('   - reasonUnavailable: ${newAvailabilityStatus.reasonUnavailable}');
          
          // إعادة تحميل ساعات العمل من قاعدة البيانات للحصول على التفاصيل الكاملة
          if (workingHoursUpdated == true || forceStatusRecheck == true) {
            developer.log('🕒 إعادة تحميل ساعات العمل الكاملة من قاعدة البيانات');
            await _loadWorkingHours();
          }
          
          // عرض إشعار التحديث
          _showBusinessStatusUpdateNotification(updateData);
          
          // 🔥 قراءة فورية من Cache لضمان الدقة
          await _refreshBusinessStatus();
          
          return; // انتهاء المعالجة الفورية
        }
        
        // 🚀 للتحديثات العادية
        if (source == 'polling' && mounted) {
          // 🔥 إعطاء الأولوية لـ isAvailableNow من API (الأدق)
          final isAvailableNow = updateData['isAvailableNow'] as bool?;
          final currentStatus = updateData['currentStatus'] as String?;
          final isClosed = updateData['isClosed'] as bool?;
          final currentWeekday = updateData['currentWeekday'] as String?; // 🔥 اليوم الحالي
          
          developer.log('🔍 StoreDetailScreen: بيانات polling:');
          developer.log('   - isAvailableNow: $isAvailableNow');
          developer.log('   - currentStatus: $currentStatus');
          developer.log('   - isClosed: $isClosed');
          developer.log('   - acceptingOrders: $canAcceptOrders');
          developer.log('   - isWithinWorkingHours: $isWithinWorkingHoursDirect');
          developer.log('   - currentWeekday: $currentWeekday'); // 🔥 debug
          
          // 🔥 حفظ اليوم الحالي من Backend
          if (currentWeekday != null) {
            _currentWeekdayFromBackend = currentWeekday;
          }
          
          // تحديث مباشر بدون طلب شبكة اعتماداً على البيانات المرسلة من خدمة polling
          // 🔥 استخدام isAvailableNow كمصدر رئيسي للحقيقة
          final effectiveIsAvailable = isAvailableNow ?? (
            (isAvailableDirect != null)
                ? isAvailableDirect
                : ((canAcceptOrders ?? false) && (isWithinWorkingHoursDirect ?? false))
          );
          
          // 🔥 استخدام isWithinWorkingHoursDirect من Backend (محسوب بـ timezone صحيح)
          final effectiveIsWithinWorkingHours = isWithinWorkingHoursDirect ?? _availabilityStatus?.isWithinWorkingHours ?? true;

          final updatedStatus = RestaurantAvailabilityStatus(
            businessId: widget.store.id,
            isAvailable: effectiveIsAvailable,
            acceptingOrders: canAcceptOrders ?? _availabilityStatus?.acceptingOrders ?? false,
            isWithinWorkingHours: effectiveIsWithinWorkingHours,
            workingHours: _availabilityStatus?.workingHours ?? {},
            checkedAt: DateTime.now(),
            reasonUnavailable: _getReasonFromStatus(isBusy, canAcceptOrders, statusMessage, effectiveIsWithinWorkingHours),
          );

          developer.log('✅ StoreDetailScreen: تحديث حالة المطعم:');
          developer.log('   - isAvailable: ${updatedStatus.isAvailable}');
          developer.log('   - acceptingOrders: ${updatedStatus.acceptingOrders}');
          developer.log('   - isWithinWorkingHours: ${updatedStatus.isWithinWorkingHours}');

          setState(() {
            _availabilityStatus = updatedStatus;
            _loadingBusinessStatus = false;
          });
          // تعطيل SnackBar المزعجة - فقط تحديث UI
          // _showBusinessStatusUpdateNotification(updateData);
        } else {
          await _refreshBusinessStatus();
        }
        
        // 🔥 إجبار rebuild إضافي للتأكد من التحديث المرئي
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {});
            developer.log('🔄 إعادة build إضافية للتأكد من التحديث المرئي في StoreDetailScreen');
          }
        });
      }
    } catch (e) {
      developer.log('❌ خطأ في معالجة تحديث حالة المطعم في StoreDetailScreen: $e');
    }
  }

  /// بدء تحديث دوري لحالة المطعم
  void _startBusinessStatusUpdates() {
    // تحديث كل 30 ثانية
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _refreshBusinessStatus();
      } else {
        timer.cancel();
      }
    });
  }

  /// إجبار إعادة تحميل حالة المطعم من الخادم
  Future<void> _refreshBusinessStatus() async {
    if (!mounted) return;
    
    try {
      developer.log('🔄 تحديث دوري لحالة المطعم: ${widget.store.id}');
      
      // استخدام الخدمة الجديدة
      final newAvailabilityStatus = await _availabilityService.checkRestaurantAvailability(widget.store.id);
      
      if (mounted && _availabilityStatus != null) {
        // التحقق من تغيير الحالة
        if (_availabilityStatus!.isAvailable != newAvailabilityStatus.isAvailable || 
            _availabilityStatus!.acceptingOrders != newAvailabilityStatus.acceptingOrders) {
          
          developer.log('📊 تغييرت حالة المطعم من ${_availabilityStatus!.isAvailable ? "متاح" : "غير متاح"} إلى ${newAvailabilityStatus.isAvailable ? "متاح" : "غير متاح"}');
          
          setState(() {
            _availabilityStatus = newAvailabilityStatus;
          });
        }
      }
    } catch (e) {
      developer.log('❌ خطأ في تحديث حالة المطعم: $e');
    }
  }

  /// إعداد WebSocket listener لتحديثات فورية - يدعم كلا النوعين من التحديثات
  void _setupSubscriptionListener() {
    try {
      developer.log('🔌 StoreDetailScreen: إعداد SubscriptionManager للمطعم: ${widget.store.id}');
      
      // إلغاء أي اشتراك سابق
      _businessStatusSubscription?.cancel();
      
      // الاشتراك في تحديثات polling من SubscriptionManager
      _businessStatusSubscription = _subscriptionManager
          .subscribeToBusinessStatus(widget.store.id, _subscriberId)
          .listen(
        (updateData) async {
          developer.log('📥 StoreDetail: استقبال تحديث من ${updateData['source'] ?? 'unknown'} للمطعم: ${widget.store.id}');
          
          // Debouncing: منع التحديثات المتعددة خلال ثانية واحدة
          final now = DateTime.now();
          if (_lastUpdateTime != null &&
              now.difference(_lastUpdateTime!).inMilliseconds < 1000) {
            developer.log('⏭️ تجاهل تحديث متكرر (debouncing)');
            return;
          }
          _lastUpdateTime = now;
          
          // معالجة التحديث
          await _handleBusinessStatusUpdate(updateData);
        },
        onError: (error) {
          developer.log('❌ خطأ في استقبال تحديثات المطعم: $error');
        },
        onDone: () {
          developer.log('⚠️ تم إغلاق stream للمطعم ${widget.store.id} - إعادة إعداد');
          if (mounted) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) _setupSubscriptionListener();
            });
          }
        },
      );
      
      developer.log('✅ تم إعداد SubscriptionManager بنجاح للمطعم: ${widget.store.id}');
    } catch (e) {
      developer.log('❌ خطأ في إعداد SubscriptionManager: $e');
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _setupSubscriptionListener();
      });
    }
  }

  /// عرض إشعار تحديث حالة المطعم
  void _showBusinessStatusUpdateNotification(Map<String, dynamic> updateData) {
    if (!mounted) return;
    
    final canAcceptOrders = updateData['canAcceptOrders'] as bool? ?? true;
    final statusMessage = updateData['statusMessage'] as String? ?? '';
    
    String message;
    Color backgroundColor;
    IconData icon;
    
    if (canAcceptOrders) {
      message = statusMessage.isNotEmpty ? statusMessage : 'المطعم متاح الآن لاستقبال الطلبات';
      backgroundColor = AppColors.primary;
      icon = Icons.check_circle;
    } else {
      message = statusMessage.isNotEmpty ? statusMessage : 'المطعم غير متاح حالياً لاستقبال الطلبات';
      backgroundColor = AppColors.secondary;
      icon = Icons.info;
    }
    
    // التحقق مرة أخرى قبل عرض الـ SnackBar
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// فحص إذا كان الوقت الحالي ضمن ساعات العمل
  bool _isCurrentTimeWithinWorkingHours(String opening, String closing) {
    try {
      final now = DateTime.now();
      final currentTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      
      // تحويل الأوقات إلى دقائق لسهولة المقارنة
      int timeToMinutes(String time) {
        final parts = time.split(':');
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
      
      final currentMinutes = timeToMinutes(currentTime);
      final openingMinutes = timeToMinutes(opening);
      final closingMinutes = timeToMinutes(closing);
      
      // التعامل مع الحالات العادية والحالات التي تتجاوز منتصف الليل
      if (closingMinutes > openingMinutes) {
        // حالة عادية (مثل 08:00 - 22:00)
        return currentMinutes >= openingMinutes && currentMinutes <= closingMinutes;
      } else {
        // حالة تتجاوز منتصف الليل (مثل 22:00 - 06:00)
        return currentMinutes >= openingMinutes || currentMinutes <= closingMinutes;
      }
    } catch (e) {
      developer.log('خطأ في فحص ساعات العمل: $e');
      return true; // افتراض أنه مفتوح في حالة الخطأ
    }
  }

  /// الحصول على سبب عدم الإتاحة
  String _getReasonFromStatus(bool? isBusy, bool? canAcceptOrders, String? statusMessage, bool isWithinWorkingHours) {
    if (!isWithinWorkingHours) {
      return 'مغلق';
    }
    
    if (isBusy == true || canAcceptOrders == false) {
      return statusMessage?.isNotEmpty == true ? statusMessage! : 'مشغول';
    }
    
    return 'متاح';
  }

  /// التحقق من قدرة المطعم على قبول الطلبات
  bool _canRestaurantAcceptOrders() {
    // Priority 1: Check working hours
    bool isRestaurantOpen = true;
    
    if (_availabilityStatus != null) {
      isRestaurantOpen = _availabilityStatus!.isWithinWorkingHours;
    } else if (_workingHours != null) {
      isRestaurantOpen = _workingHours!.isOpenNow;
    }
    
    if (!isRestaurantOpen) {
      return false;
    }

    // Priority 2: Check if accepting orders (busy)
    if (_availabilityStatus != null && !_availabilityStatus!.acceptingOrders) {
      return false;
    }

    // Priority 3: Check general availability
    if (_availabilityStatus != null && !_availabilityStatus!.isAvailable) {
      return false;
    }

    return true;
  }

  /// الحصول على رسالة حالة المطعم
  String? _getRestaurantStatusMessage() {
    // Priority 1: Check working hours
    bool isRestaurantOpen = true;
    
    if (_availabilityStatus != null) {
      isRestaurantOpen = _availabilityStatus!.isWithinWorkingHours;
    } else if (_workingHours != null) {
      isRestaurantOpen = _workingHours!.isOpenNow;
    }
    
    if (!isRestaurantOpen) {
      return 'المطعم مغلق حالياً وفقاً لساعات العمل';
    }

    // Priority 2: Check if accepting orders (busy)
    if (_availabilityStatus != null && !_availabilityStatus!.acceptingOrders) {
      final reason = _availabilityStatus!.reasonUnavailable;
      if (reason?.isNotEmpty == true) {
        return reason;
      }
      return 'المطعم مشغول ولا يستقبل طلبات جديدة حالياً';
    }

    // Priority 3: Check general availability
    if (_availabilityStatus != null && !_availabilityStatus!.isAvailable) {
      final reason = _availabilityStatus!.reasonUnavailable;
      if (reason?.isNotEmpty == true) {
        return reason;
      }
      return 'المطعم غير متاح حالياً';
    }

    return null;
  }

  /// الحصول على أيقونة حالة المطعم
  IconData _getRestaurantStatusIcon() {
    bool isRestaurantOpen = true;
    
    if (_availabilityStatus != null) {
      isRestaurantOpen = _availabilityStatus!.isWithinWorkingHours;
    } else if (_workingHours != null) {
      isRestaurantOpen = _workingHours!.isOpenNow;
    }
    
    if (!isRestaurantOpen) {
      return Icons.access_time;
    }

    if (_availabilityStatus != null && !_availabilityStatus!.acceptingOrders) {
      return Icons.schedule;
    }

    if (_availabilityStatus != null && !_availabilityStatus!.isAvailable) {
      return Icons.info;
    }

    return Icons.check_circle;
  }

  /// الحصول على لون حالة المطعم
  Color _getRestaurantStatusColor() {
    // Priority 1: Check working hours
    bool isRestaurantOpen = true;
    
    if (_availabilityStatus != null) {
      isRestaurantOpen = _availabilityStatus!.isWithinWorkingHours;
    } else if (_workingHours != null) {
      isRestaurantOpen = _workingHours!.isOpenNow;
    }
    
    if (!isRestaurantOpen) {
      return AppColors.primary; // مغلق بسبب ساعات العمل - استخدام اللون الأساسي
    }

    // Priority 2: Check if accepting orders (busy)
    if (_availabilityStatus != null && !_availabilityStatus!.acceptingOrders) {
      return AppColors.secondary; // مشغول أو لا يستقبل طلبات - استخدام اللون الثانوي
    }

    // Priority 3: Check general availability
    if (_availabilityStatus != null && !_availabilityStatus!.isAvailable) {
      return AppColors.secondary; // غير متاح بشكل عام - استخدام اللون الثانوي
    }

    return Colors.green; // متاح ومفتوح
  }

  /// دالة لتحديد حالة إتاحة الطبق
  DishAvailability _getDishAvailability(ProductModel product) {
    // التحقق من السعر - إذا كان السعر 0 أو أقل، المنتج غير متاح
    if (product.price <= 0) {
      return const DishAvailability(
        isAvailable: false,
        reasonText: 'غير متاح',
        message: 'هذا المنتج غير متاح حالياً',
        icon: Icons.remove_circle,
        statusColor: Colors.red,
      );
    }

    // التحقق من الاسم - إذا كان فارغاً، المنتج غير صالح
    if (product.name.trim().isEmpty) {
      return const DishAvailability(
        isAvailable: false,
        reasonText: 'غير صالح',
        message: 'بيانات المنتج غير صالحة',
        icon: Icons.error,
        statusColor: Colors.red,
      );
    }

    // المنتج متاح
    return const DishAvailability(
      isAvailable: true,
      reasonText: 'متاح',
      message: 'المنتج متاح للطلب',
      icon: Icons.check_circle,
      statusColor: Colors.green,
    );
  }

  /// إضافة منتج إلى السلة
  void _addToCart(ProductModel product) {
    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      
      // طباعة عنوان المطعم للتشخيص
      developer.log('🏪 _addToCart: إضافة منتج للسلة من المطعم:');
      developer.log('  اسم المطعم: ${widget.store.name}');
      developer.log('  معرف المطعم: ${widget.store.id}');
      developer.log('  عنوان المطعم: "${widget.store.address}"');
      developer.log('  طول العنوان: ${widget.store.address.length} حرف');
      developer.log('  هل العنوان فارغ؟ ${widget.store.address.isEmpty}');
      developer.log('  هل العنوان يحتوي على "متوفر"؟ ${widget.store.address.contains("متوفر")}');
      
      // تحديد العنوان النهائي للمطعم
      final finalStoreAddress = widget.store.address.isEmpty || widget.store.address.contains('متوفر') 
                               ? 'عنوان المطعم غير محدد - ${widget.store.name}' 
                               : widget.store.address;
      
      developer.log('📍 العنوان النهائي المستخدم في السلة: "$finalStoreAddress"');
      
      // إنشاء عنصر السلة
      print('🛒 إضافة إلى السلة - معلومات صورة المطعم:');
      print('  - Store ID: ${widget.store.id}');
      print('  - Store Name: ${widget.store.name}');
      print('  - Store Image: "${widget.store.image}"');
      print('  - Store Image Length: ${widget.store.image.length}');
      print('  - Store Image isEmpty: ${widget.store.image.isEmpty}');
      
      final cartItem = {
        'id': product.id,
        'name': product.name,
        'price': product.price,
        'description': product.description,
        'image': product.imageUrl,
        'quantity': 1,
        'store_id': widget.store.id,
        'store_name': widget.store.name,
        'store_address': finalStoreAddress, // عنوان المطعم للسائقين
        'store_image': widget.store.image, // ✅ صورة المطعم للسائقين
        'customizations': <Map<String, dynamic>>[], // قائمة فارغة من التخصيصات
        'special_instructions': '', // تعليمات خاصة فارغة
        'total_price': product.price, // السعر الإجمالي
      };
      
      // إضافة العنصر للسلة
      appState.addToCart(cartItem);
      
      developer.log('✅ تم إضافة ${product.name} إلى السلة');
      
      // عرض رسالة تأكيد
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.shopping_cart, color: AppColors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم إضافة ${product.name} إلى السلة',
                    style: const TextStyle(color: AppColors.secondary),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.fromLTRB(16, 16, 16, 
              MediaQuery.of(context).padding.bottom + 100
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      developer.log('❌ خطأ في إضافة المنتج للسلة: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إضافة المنتج للسلة: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// بناء شريط التطبيق المنهار الذي يظهر عند التمرير للأعلى
  Widget _buildCollapsedAppBar() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      top: _collapsed ? 0 : -200,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              // الجزء العلوي: اسم المطعم والأيقونات
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // أيقونة القائمة (يسار)
                    IconButton(
                      onPressed: _showCategoriesBottomSheet,
                      icon: const Icon(Icons.menu, color: Colors.black87),
                      tooltip: 'عرض القائمة',
                    ),
                    
                    // مساحة مرنة
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.store.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    
                    // أيقونة البحث (يمين)
                    IconButton(
                      onPressed: _showSearchDialog,
                      icon: const Icon(Icons.search, color: Colors.black87),
                      tooltip: 'البحث',
                    ),
                  ],
                ),
              ),
              
              // التبويبات
              if (_tabController != null)
                Container(
                  child: Material(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                      ),
                      tabs: _categoryProducts.keys
                          .map((category) => Tab(text: category))
                          .toList(),
                      onTap: (index) {
                        final categoryName = _categoryProducts.keys.elementAt(index);
                        final key = _keys[categoryName];
                        if (key?.currentContext != null) {
                          Scrollable.ensureVisible(
                            key!.currentContext!,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        }
                        HapticFeedback.lightImpact();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// عرض قائمة منسدلة بجميع الأقسام للوصول السريع
  void _showCategoriesBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.restaurant_menu, color: Colors.black87),
                  const SizedBox(width: 12),
                  const Text(
                    'أقسام القائمة',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // قائمة الأقسام
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _categoryProducts.length,
                itemBuilder: (context, index) {
                  final category = _categoryProducts.keys.elementAt(index);
                  final products = _categoryProducts[category] ?? [];
                  
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.restaurant,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                    ),
                    title: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      '${products.length} عنصر',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      
                      // التنقل إلى القسم المحدد
                      final key = _keys[category];
                      if (key?.currentContext != null) {
                        Scrollable.ensureVisible(
                          key!.currentContext!,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                        );
                      }
                      
                      // تحديث التبويب
                      if (_tabController != null) {
                        _tabController!.animateTo(index);
                      }
                      
                      HapticFeedback.lightImpact();
                    },
                  );
                },
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// عرض قائمة البحث المنبثقة من الأسفل
  void _showSearchDialog() {
    final TextEditingController searchController = TextEditingController();
    List<ProductModel> searchResults = [];
    bool isSearching = false;
    Timer? searchTimer; // إضافة timer للـ debouncing

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.search,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'البحث في القائمة',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        searchTimer?.cancel(); // تنظيف الـ timer عند الإغلاق
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close, color: Colors.grey),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Search Field
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.grey[200]!,
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: (value) {
                      // إلغاء البحث السابق
                      searchTimer?.cancel();
                      
                      setModalState(() {
                        isSearching = value.isNotEmpty;
                      });
                      
                      if (value.isNotEmpty) {
                        // إضافة delay قصير لتحسين الأداء
                        searchTimer = Timer(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            _performSearch(value, setModalState, (results) {
                              searchResults = results;
                            });
                          }
                        });
                      } else {
                        setModalState(() {
                          searchResults.clear();
                        });
                      }
                    },
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        _performSearch(value, setModalState, (results) {
                          searchResults = results;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'ابحث عن طبق أو مشروب...',
                      hintStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 16,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.search,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                searchTimer?.cancel(); // إلغاء البحث المُعلَّق
                                searchController.clear();
                                setModalState(() {
                                  searchResults.clear();
                                  isSearching = false;
                                });
                              },
                              icon: Icon(
                                Icons.clear,
                                color: Colors.grey[400],
                                size: 20,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              
              // Content Area
              Expanded(
                child: isSearching
                    ? _buildSearchResults(searchResults, setModalState)
                    : _buildSearchSuggestions(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // تنفيذ البحث المحسن
  void _performSearch(String query, StateSetter setModalState, Function(List<ProductModel>) onResults) {
    if (query.trim().isEmpty) {
      setModalState(() {
        onResults([]);
      });
      return;
    }

    List<ProductModel> results = [];
    final searchTerm = query.toLowerCase().trim();
    
    // البحث في جميع المنتجات مع ترتيب النتائج حسب الصلة
    for (final categoryProducts in _categoryProducts.values) {
      for (final product in categoryProducts) {
        final productName = product.name.toLowerCase();
        final productDescription = product.description.toLowerCase();
        
        // البحث الدقيق أولاً (يبدأ بالكلمة)
        if (productName.startsWith(searchTerm)) {
          results.insert(0, product); // إضافة في المقدمة
        }
        // البحث في اسم المنتج
        else if (productName.contains(searchTerm)) {
          results.add(product);
        }
        // البحث في الوصف
        else if (productDescription.contains(searchTerm)) {
          results.add(product);
        }
      }
    }
    
    // إزالة المكررات (في حالة وجود منتج يحتوي على الكلمة في الاسم والوصف)
    final uniqueResults = <ProductModel>[];
    final addedIds = <String>{};
    
    for (final product in results) {
      if (!addedIds.contains(product.id)) {
        uniqueResults.add(product);
        addedIds.add(product.id);
      }
    }
    
    setModalState(() {
      onResults(uniqueResults);
    });
  }

  // عرض نتائج البحث
  Widget _buildSearchResults(List<ProductModel> results, StateSetter setModalState) {
    if (results.isEmpty) {
      return _buildEmptySearchResults();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final product = results[index];
        return _buildSearchResultItem(product, setModalState);
      },
    );
  }

  // عنصر نتيجة البحث
  Widget _buildSearchResultItem(ProductModel product, StateSetter setModalState) {
    final dishAvailability = _getDishAvailability(product);
    final canOrder = dishAvailability.isAvailable;
    final canRestaurantAcceptOrders = _canRestaurantAcceptOrders();
    final isCompletelyUnavailable = !canRestaurantAcceptOrders || !canOrder;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: isCompletelyUnavailable ? null : () async {
          Navigator.pop(context); // إغلاق البحث
          
          // التحقق من حالة المطعم مرة أخرى قبل الانتقال
          bool canRestaurantAcceptOrders = _canRestaurantAcceptOrders();
          String? restaurantStatusMessage = _getRestaurantStatusMessage();
          
          if (!canRestaurantAcceptOrders) {
            // عرض رسالة حالة المطعم
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_getRestaurantStatusIcon(), color: AppColors.secondary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          restaurantStatusMessage ?? 'المطعم غير متاح حالياً',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                backgroundColor: _getRestaurantStatusColor().withValues(alpha: 0.9),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: EdgeInsets.fromLTRB(16, 16, 16, 
                  MediaQuery.of(context).padding.bottom + 100
                ),
                duration: const Duration(seconds: 3),
                elevation: 6,
              ),
            );
            return;
          }
          
          // التحقق من حالة الطبق الفردي
          if (!canOrder) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(dishAvailability.icon, color: AppColors.secondary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dishAvailability.message,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                backgroundColor: dishAvailability.statusColor.withValues(alpha: 0.9),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: EdgeInsets.fromLTRB(16, 16, 16, 
                  MediaQuery.of(context).padding.bottom + 100
                ),
                duration: const Duration(seconds: 3),
                elevation: 6,
              ),
            );
            return;
          }
          
          // الانتقال لتفاصيل الطبق مع تمرير productData
          final dish = Dish(
            id: product.id,
            name: product.name,
            description: product.description,
            imageUrls: product.imageUrl.isNotEmpty ? [product.imageUrl] : [],
            likesPercent: 85,
            likesCount: 120,
            basePrice: product.price,
            optionGroups: [],
          );

          try {
            developer.log('🔄 بدء التنقل لشاشة تفاصيل الطبق من البحث');
            developer.log('  منتج: ${product.name}');
            developer.log('  تمرير productData: نعم');
            
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DishDetailScreen(
                  dish: dish,
                  storeId: widget.store.id,
                  storeName: widget.store.name, // تمرير اسم المتجر
                  storeAddress: widget.store.address, // تمرير عنوان المتجر للسائقين
                  productData: product, // تمرير بيانات المنتج الكاملة
                ),
              ),
            );
            
            developer.log('🔙 العودة من شاشة تفاصيل الطبق (من البحث)');
            developer.log('  النتيجة: $result');
          } catch (e) {
            developer.log('❌ خطأ في التنقل من البحث: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('خطأ في فتح تفاصيل الطبق: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primary.withValues(alpha: 0.1), // إضافة تأثير splash
        highlightColor: AppColors.primary.withValues(alpha: 0.05), // إضافة تأثير highlight
        child: Opacity(
          opacity: isCompletelyUnavailable ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // صورة المنتج
                Hero( // إضافة Hero animation للصورة
                  tag: 'search_product_${product.id}',
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[100],
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: product.imageUrl.isNotEmpty
                          ? Image.network(
                              product.imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.restaurant,
                                  color: Colors.grey[400],
                                  size: 30,
                                );
                              },
                            )
                          : Icon(
                              Icons.restaurant,
                              color: Colors.grey[400],
                              size: 30,
                            ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // معلومات المنتج
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isCompletelyUnavailable ? Colors.grey : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (product.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          product.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: isCompletelyUnavailable ? Colors.grey : Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${product.price.toStringAsFixed(0)} د.ع',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isCompletelyUnavailable ? Colors.grey : AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          if (!isCompletelyUnavailable)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.add,
                                color: AppColors.primary,
                                size: 16,
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'غير متاح',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // عرض اقتراحات البحث
  Widget _buildSearchSuggestions() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 48,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'ابحث عن طبق أو مشروب',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'اكتب اسم الطبق أو المكون للعثور على ما تريد',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }



  // عرض عدم وجود نتائج
  Widget _buildEmptySearchResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'لم نجد أي نتائج',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جرب البحث بكلمات مختلفة أو تصفح القائمة',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }


}


