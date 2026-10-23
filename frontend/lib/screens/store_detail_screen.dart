import '../services/storefront_pricing.dart';
import '../widgets/storefront_value.dart';
import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import '../models/store.dart';
import '../models/store_discount.dart';
import '../models/dish.dart';
import '../models/product_model.dart';
import '../models/working_hours_model.dart';
import '../models/favorites_model.dart';
import '../models/business_suggestion_data.dart';
import '../models/order_model.dart';
import '../services/business_service.dart';
import '../services/working_hours_service.dart';
import '../services/restaurant_availability_service.dart';
import '../services/order_service.dart';
import '../services/subscription_manager.dart';
import '../services/status_polling_service.dart'; // 🔥 جديد
import '../providers/app_state_provider.dart';
import '../providers/versioning_providers.dart';
import '../widgets/animated_cart_bar.dart';
import '../widgets/clear_cart_sheet.dart';
import '../widgets/restaurant_menu_components.dart';
import '../services/delivery_address_manager.dart';
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
  final String? initialCategoryName;

  const StoreDetailScreen({
    super.key,
    required this.store,
    this.initialCategoryName,
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

  /// ارتفاع الهيدر الموسع (صورة الغلاف)
  static const double _kExpandedHeight = 470.0;
  List<StoreDiscount> _menuOffers = [];

  /// منع تعارض الـ scroll-spy مع التنقل عبر التبويبات
  bool _isTabTapScrolling = false;

  /// أطباق سبق طلبها من هذا المطعم (قسم "طلبت من هنا من قبل")
  List<OrderItem> _previousOrderItems = [];

  // البيانات من الباك إند
  Map<String, List<ProductModel>> _categoryProducts = {};
  bool _isLoading = true;
  String? _error;
  final Map<String, GlobalKey> _keys = {};
  bool _openedInitialCategory = false;
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

  Timer? _statusRefreshTimer;

  // خدمة توفر المطاعم الجديدة
  final RestaurantAvailabilityService _availabilityService =
      RestaurantAvailabilityService.instance;
  RestaurantAvailabilityStatus? _availabilityStatus;
  String?
  _currentWeekdayFromBackend; // 🔥 اليوم الحالي من Backend (timezone المطعم)

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
    _subscriberId = _subscriptionManager.generateSubscriberId(
      'store_detail_${widget.store.id}',
    );

    // ✅ تأخير تحديد حالة المفضلة حتى بعد تحميل FavoritesModel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        // Favorite state is handled via Consumer widgets
      });
      developer.log(
        '✅ تم تحديد حالة المفضلة الأولية: للمطعم: ${widget.store.name}',
      );
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
    _loadPreviousOrderItems();
    _loadMenuOffers();

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
    _subscriptionManager.unsubscribeFromBusinessStatus(
      widget.store.id,
      _subscriberId,
    );

    super.dispose();
  }

  /// 🆕 بدء polling للمنيو والمخزون للتحديثات الفورية
  void _startMenuPolling() {
    // حفظ reference للـ provider قبل استخدامه
    _menuProvider = Provider.of<MenuProviderWithVersioning>(
      context,
      listen: false,
    );

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

  Future<void> _loadBusinessData({
    bool force = false,
    bool showLoading = true,
  }) async {
    if (!mounted) return;

    // منع التحميل المتكرر إذا كانت البيانات موجودة بالفعل (إلا عند السحب للتحديث)
    if (!force &&
        _dataLoaded &&
        _categoryProducts.isNotEmpty &&
        _error == null) {
      developer.log('📋 البيانات موجودة مسبقاً - تجاهل إعادة التحميل');
      return;
    }

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }

    try {
      developer.log(
        '🔍 جاري تحميل منتجات المطعم: ${widget.store.name} (ID: ${widget.store.id})',
      );

      final categoryProducts =
          await BusinessService.getBusinessCategoriesAndProducts(
            widget.store.id,
          );

      if (!mounted) return;

      developer.log('📦 تم تحميل ${categoryProducts.length} فئة من المنتجات');
      for (final category in categoryProducts.keys) {
        developer.log(
          '   📂 $category: ${categoryProducts[category]?.length ?? 0} منتج',
        );
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
      appState.setBusinessSuggestionData(
        widget.store.id,
        businessSuggestionData,
      );
      developer.log(
        '💾 تم حفظ بيانات المطعم للاقتراحات: $businessSuggestionData',
      );
      developer.log(
        '🔍 businessType from Store: "${widget.store.businessType}"',
      );
      developer.log(
        '🔍 isRestaurant check: ${businessSuggestionData.isRestaurant}',
      );
      developer.log(
        '📋 availableCategories (${realSections.length}): ${realSections.join(", ")}',
      );

      // إنشاء TabController جديد فقط إذا كانت هناك فئات
      TabController? newTabController;
      if (realSections.isNotEmpty) {
        newTabController = TabController(
          length: realSections.length,
          vsync: this,
        );
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

      if (!_openedInitialCategory && widget.initialCategoryName != null) {
        _openedInitialCategory = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final index = realSections.indexOf(widget.initialCategoryName!);
          if (index < 0) return;
          _tabController?.animateTo(index);
          final categoryContext =
              _keys[widget.initialCategoryName]?.currentContext;
          if (categoryContext != null)
            Scrollable.ensureVisible(
              categoryContext,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
        });
      }

      // التخلص من TabController القديم بأمان
      if (oldController != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }

      developer.log(
        '✅ تم تحديث الواجهة بنجاح - ${categoryProducts.length} فئة',
      );
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
      final allWorkingHours =
          await WorkingHoursService.getAllBusinessWorkingHours(widget.store.id);

      if (mounted) {
        setState(() {
          if (allWorkingHours != null && allWorkingHours.isNotEmpty) {
            _workingHours = BusinessWorkingHours(
              businessId: widget.store.id,
              workingHours: allWorkingHours,
            );
            developer.log(
              '✅ تم تحميل ساعات العمل بنجاح - ${allWorkingHours.length} أيام',
            );
            developer.log(
              '📋 ساعات العمل: ${allWorkingHours.map((h) => '${h.weekday}: ${h.opening}-${h.closing}').join(', ')}',
            );
          } else {
            _workingHours = null;
            developer.log('⚠️ لا توجد ساعات عمل محددة للمطعم');
          }
          _loadingWorkingHours = false;
        });

        if (_workingHours?.hasWorkingHours == true) {
          developer.log(
            '📅 المطعم ${_workingHours?.isOpenNow == true ? "مفتوح" : "مغلق"} حالياً',
          );
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
          developer.log(
            '🔔 StoreDetail: استلام تحديث polling للمطعم $businessId',
          );
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

    // الهيدر منهار عندما يتجاوز التمرير (الارتفاع الموسع - ارتفاع الشريط)
    final collapseThreshold = _kExpandedHeight - kToolbarHeight;
    final isCollapsed = _scrollCtrl.offset >= collapseThreshold;

    if (isCollapsed != _collapsed) {
      setState(() {
        _collapsed = isCollapsed;
      });
    }
  }

  void _handleScrollTabSync() {
    if (_isTabTapScrolling) return; // تجاهل أثناء التنقل عبر التبويب
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

  /// 🔄 السحب للأسفل لتحديث الأسعار/التوفر
  Future<void> _handleRefresh() async {
    developer.log('🔄 pull-to-refresh: إعادة تحميل بيانات المطعم');
    await Future.wait([
      _loadBusinessData(force: true, showLoading: false),
      _loadWorkingHours(),
      _loadBusinessStatus(skipCache: true),
      _loadMenuOffers(),
    ]);
  }

  /// 🧾 تحميل أطباق سبق طلبها المستخدم من هذا المطعم (قسم إعادة الطلب)
  Future<void> _loadPreviousOrderItems() async {
    try {
      final orderService = OrderService();
      // يتجاهل تلقائياً في حالة الضيوف (getOrders تتطلب تسجيل الدخول)
      await orderService.getOrders(page: 1, limit: 50);
      if (!mounted) return;

      final orders =
          orderService.orders
              .where((o) => o.storeId == widget.store.id)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final seen = <String>{};
      final items = <OrderItem>[];
      for (final order in orders) {
        for (final item in order.items) {
          final key = item.productId.isNotEmpty ? item.productId : item.dishId;
          if (key.isEmpty || seen.contains(key)) continue;
          seen.add(key);
          items.add(item);
          if (items.length >= 10) break;
        }
        if (items.length >= 10) break;
      }

      if (items.isNotEmpty && mounted) {
        setState(() {
          _previousOrderItems = items;
        });
        developer.log(
          '🧾 تم العثور على ${items.length} طبق سابق في هذا المطعم',
        );
      }
    } catch (e) {
      // الضيوف أو أي خطأ: لا نعرض القسم
      developer.log('ℹ️ تعذر تحميل الطلبات السابقة لهذا المطعم: $e');
    }
  }

  ProductModel? _findProductById(String id) {
    if (id.isEmpty) return null;
    for (final products in _categoryProducts.values) {
      for (final product in products) {
        if (product.id == id) return product;
      }
    }
    return null;
  }

  /// فتح لوحة الطبق من قسم "طلبت من هنا من قبل"
  Future<void> _openReorderItem(OrderItem item) async {
    HapticFeedback.lightImpact();
    final product = _findProductById(
      item.productId.isNotEmpty ? item.productId : item.dishId,
    );

    if (!mounted) return;

    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا الطبق لم يعد متوفراً في القائمة'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

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

      await showDishDetailBottomSheet(
        context,
        dish: dish,
        storeId: widget.store.id,
        storeName: widget.store.name,
        storeAddress: widget.store.address,
        productData: product,
      );
    } catch (e) {
      developer.log('❌ خطأ في فتح اللوحة السفلية من قسم إعادة الطلب: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    developer.log(
      '🎨 بناء StoreDetailScreen: _isLoading=$_isLoading, _error=$_error, categories=${_categoryProducts.length}',
    );

    final hasMenu =
        !_isLoading &&
        _error == null &&
        _categoryProducts.isNotEmpty &&
        !_hasNoProducts();

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            body:
                _isLoading
                    ? _buildLoadingWidget()
                    : _error != null
                    ? _buildErrorWidget()
                    : !hasMenu
                    ? _buildEmptyWidget()
                    : _buildMainContent(),
          ),

          // زر السلة العائم (يظهر فقط عندما توجد عناصر لهذا المطعم)
          if (hasMenu)
            Positioned(left: 0, right: 0, bottom: 0, child: _buildCartBar()),
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
            developer.log(
              '🛒 Consumer بناء _buildCartBar: hasCartItems=$hasCartItems',
            );

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
    final canAcceptOrders = _canRestaurantAcceptOrders();

    return Stack(
      children: [
        RefreshIndicator(
          color: _primaryPink,
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            controller: _scrollCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1) الهيدر المنهار (SliverAppBar مع صورة الغلاف والمعلومات)
              _buildSliverAppBar(),

              // 2) بانر "مغلق/مشغول" - يبقى الطلب معطلاً لكن الصفحة تظل مفتوحة
              if (!canAcceptOrders) _buildClosedBanner(),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 3, 16, 0),
                  child: RestaurantSummaryCard(
                    store: widget.store,
                    onDetails: _showStoreInfoBottomSheet,
                  ),
                ),
              ),
              if (_menuOffers.isNotEmpty)
                SliverToBoxAdapter(child: _buildMenuOffers()),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'ماذا تشتهي اليوم؟',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: Color(0xff171717),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _showSearchDialog,
                        tooltip: 'ابحث في القائمة',
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              _buildStickyHeader(),
              if (_categoryProducts.values.any((items) => items.isNotEmpty))
                SliverToBoxAdapter(child: _buildFeaturedDishes()),

              // 5) قسم "طلبت من هنا من قبل"
              if (_previousOrderItems.isNotEmpty)
                SliverToBoxAdapter(child: _buildReorderSection()),

              // 6) أقسام المنيو
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      ...(_categoryProducts.keys
                          .map(
                            (categoryTitle) =>
                                _buildIntegratedSection(categoryTitle),
                          )
                          .toList()),
                      // مساحة إضافية للزر العائم للسلة
                      const SizedBox(height: 110),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingWidget() {
    // ✨ هيكل تحميل shimmer (بدلاً من السبانر)
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صورة الغلاف
            Container(
              height: _kExpandedHeight,
              width: double.infinity,
              color: Colors.white,
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 200,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 140,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
            // عناصر منيو وهمية
            for (int i = 0; i < 5; i++)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            const SizedBox(height: 100),
          ],
        ),
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
                style: TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryPink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
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
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryPink,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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
                    style: TextStyle(
                      color: _primaryPink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _primaryPink),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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

  // ============================================================
  // 🏗️ هيكل الصفحة الجديد (SliverAppBar منهار + أقسام لاصقة)
  // ============================================================

  /// 1) SliverAppBar المنهار: صورة الغلاف + اسم المطعم + أزرار الرجوع/المشاركة/المفضلة
  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: _kExpandedHeight,
      backgroundColor: Colors.white,
      elevation: _collapsed ? 2 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      automaticallyImplyLeading: false,
      leading: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, top: 6, bottom: 6),
        child: _buildActionButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8, top: 6, bottom: 6),
          child: _buildActionButton(
            icon: Icons.search,
            onPressed: _showSearchDialog,
          ),
        ),
        // زر مشاركة المطعم
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8, top: 6, bottom: 6),
          child: _buildActionButton(
            icon: Icons.share_outlined,
            onPressed: _shareStore,
          ),
        ),
        // زر المفضلة
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 12, top: 6, bottom: 6),
          child: Consumer<FavoritesModel>(
            builder: (context, favoritesModel, child) {
              final isFav = favoritesModel.isStoreFavorite(widget.store.id);
              return _buildActionButton(
                icon: isFav ? Icons.favorite : Icons.favorite_border,
                iconColor: AppColors.secondary,
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
                          content: Text(
                            'حدث خطأ في تحديث المفضلة: ${e.toString()}',
                          ),
                          backgroundColor: AppColors.secondary,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
              );
            },
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        centerTitle: true,
        titlePadding: const EdgeInsetsDirectional.only(
          start: 64,
          end: 110,
          bottom: 14,
        ),
        title:
            _collapsed
                ? Text(
                  widget.store.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                )
                : null,
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'store_image_${widget.store.id}',
              child:
                  widget.store.image.isNotEmpty
                      ? Image.network(
                        widget.store.image,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => _buildDefaultBackgroundForHeader(),
                      )
                      : _buildDefaultBackgroundForHeader(),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .35, .7, 1],
                  colors: [
                    Color(0x26000000),
                    Color(0x00000000),
                    Color(0xc2403527),
                    Color(0xff403527),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 22,
              child: RestaurantHeroDetails(
                store: widget.store,
                onDetails: _showStoreInfoBottomSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// صورة الغلاف مع معلومات المطعم (الحالة الموسعة)
  void _shareStore() {
    HapticFeedback.lightImpact();
    SharePlus.instance.share(
      ShareParams(
        text: 'اطلب من ${widget.store.name} عبر تطبيق Wizz',
        subject: widget.store.name,
      ),
    );
  }

  /// 2) بانر "مغلق/مشغول" — تبقى الصفحة مفتوحة لكن الطلب معطل
  Widget _buildClosedBanner() {
    final message = _getRestaurantStatusMessage() ?? 'المطعم غير متاح حالياً';
    final openingText = _getWorkingHoursStatusText();

    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        color: Colors.red.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              _getRestaurantStatusIcon(),
              color: Colors.red.shade700,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$message • $openingText',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3) تبويبات الفئات اللاصقة عند التمرير
  Widget _buildStickyHeader() {
    final headerHeight = _tabController != null ? 66.0 : 0.0;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyMenuHeaderDelegate(
        height: headerHeight,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              // تبويبات الفئات
              if (_tabController != null)
                Expanded(
                  child: Material(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.black87,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: const Color(0xff191919),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      indicatorPadding: const EdgeInsets.symmetric(vertical: 9),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                      ),
                      tabAlignment: TabAlignment.start,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                      tabs:
                          _categoryProducts.keys
                              .map(
                                (category) => Tab(
                                  child: Text(
                                    _displayCategoryTitle(
                                      category,
                                      maxChars: 22,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                              .toList(),
                      onTap: (index) {
                        final categoryName = _categoryProducts.keys.elementAt(
                          index,
                        );
                        final key = _keys[categoryName];
                        if (key?.currentContext != null) {
                          _isTabTapScrolling = true;
                          Scrollable.ensureVisible(
                            key!.currentContext!,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          ).then((_) {
                            Future.delayed(
                              const Duration(milliseconds: 120),
                              () {
                                _isTabTapScrolling = false;
                              },
                            );
                          });
                        }
                        HapticFeedback.lightImpact();
                      },
                    ),
                  ),
                ),

              // خط فاصل عند اللصق
              const Divider(height: 1, color: Color(0xffe5e5e5)),
            ],
          ),
        ),
      ),
    );
  }

  /// شريط البحث في المنيو (يفتح لوحة البحث)
  Widget _buildReorderSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Icon(Icons.history, color: AppColors.secondary, size: 20),
                SizedBox(width: 8),
                Text(
                  'طلبت من هنا من قبل',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _previousOrderItems.length,
              itemBuilder: (context, index) {
                return _buildReorderCard(_previousOrderItems[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderCard(OrderItem item) {
    final product = _findProductById(
      item.productId.isNotEmpty ? item.productId : item.dishId,
    );
    final image = item.dishImage ?? '';

    return Container(
      width: 230,
      margin: const EdgeInsetsDirectional.only(end: 12),
      child: Material(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _openReorderItem(item),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child:
                        image.isNotEmpty
                            ? Image.network(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    Icons.fastfood,
                                    color: Colors.grey,
                                  ),
                                );
                              },
                            )
                            : Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.fastfood,
                                color: Colors.grey,
                              ),
                            ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.dishName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.unitPrice.toStringAsFixed(0)} د.ع',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (product != null)
                  const Icon(
                    Icons.add_circle,
                    color: AppColors.primary,
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
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

  /// زر التفاعل الدائري بنمط طلبات
  Widget _buildActionButton({
    required IconData icon,
    Color? iconColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor ?? const Color(0xff222222), size: 20),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// نص المراجعات
  void _showStoreInfoBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
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
                              _buildInfoRow(Icons.star, 'التقييم', widget.store.ratingValue > 0 ? widget.store.rating : 'جديد'),
                              _buildInfoRow(Icons.timer_outlined, 'وقت التحضير', '', content: StorefrontValue(branchId:widget.store.id,field:StorefrontField.preparation,initialPreparationMinutes:widget.store.averagePreparationMinutes)),
                              _buildInfoRow(Icons.access_time, 'الوصول المتوقع', '', content: StorefrontValue(branchId:widget.store.id,field:StorefrontField.arrival)),
                              _buildInfoRow(Icons.delivery_dining, 'رسوم التوصيل', '', content: StorefrontValue(branchId:widget.store.id,field:StorefrontField.fee)),
                              _buildInfoRow(Icons.route_outlined, 'المسافة', '', content: StorefrontValue(branchId:widget.store.id,field:StorefrontField.distance)),
                              ListenableBuilder(listenable:StorefrontPricing.instance,builder:(context,_){
                                final items=context.watch<AppStateProvider>().cartItems.where((item)=>item['store_id']==widget.store.id).toList();
                                final minimum=StorefrontPricing.instance.minimumIqd(widget.store.id,items);
                                return _buildInfoRow(Icons.shopping_basket_outlined,'الحد الأدنى للأصناف',minimum==null?'غير محدد':'$minimum د.ع');
                              }),
                              if (widget.store.address.isNotEmpty)
                                _buildInfoRow(Icons.location_on, 'العنوان', widget.store.address),
                              if (widget.store.category != null)
                                _buildInfoRow(Icons.restaurant_menu, 'الفئة', widget.store.category=='restaurant'?'مطعم':widget.store.category!),

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
  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Widget? content,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.secondary, size: 20),
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
            child:
                content ??
                Text(
                  value,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
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

          // قائمة المنتجات الرأسية بنمط طلبات
          Column(
            children: [
              for (var i = 0; i < products.length; i++) ...[
                Builder(
                  builder: (context) {
                    final product = products[i];
                    final availability = _getDishAvailability(product);
                    final available =
                        availability.isAvailable &&
                        _canRestaurantAcceptOrders();
                    return RestaurantMenuTile(
                      product: product,
                      available: available,
                      isBestseller: product.isFeatured,
                      unavailableReason: availability.reasonText,
                      onDetails: () => _openMenuProduct(product),
                      onAdd: () => _addToCart(product),
                    );
                  },
                ),
                if (i < products.length - 1)
                  const Divider(height: 1, color: Color(0xffeeeeee)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openMenuProduct(ProductModel product) async {
    if (!_canRestaurantAcceptOrders() ||
        !_getDishAvailability(product).isAvailable) {
      return;
    }
    await showDishDetailBottomSheet(
      context,
      dish: Dish(
        id: product.id,
        name: product.name,
        description: product.description,
        imageUrls: product.imageUrl.isEmpty ? [] : [product.imageUrl],
        likesPercent: 0,
        likesCount: 0,
        basePrice: product.price,
        optionGroups: [],
      ),
      storeId: widget.store.id,
      storeName: widget.store.name,
      storeAddress: widget.store.address,
      productData: product,
    );
  }

  Future<void> _loadMenuOffers() async {
    try {
      final offers = await OrderService().getStoreDiscounts(
        widget.store.id,
        addressId: DeliveryAddressManager.instance.activeAddress?.addressId,
      );
      if (mounted) setState(() => _menuOffers = offers);
    } catch (_) {
      if (mounted) setState(() => _menuOffers = []);
    }
  }

  Widget _buildMenuOffers() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'العروض والمزايا',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xff171717),
          ),
        ),
        const SizedBox(height: 14),
        ..._menuOffers.map(
          (offer) =>
              offer.imageUrl?.isNotEmpty == true
                  ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildImageOfferCard(offer),
                  )
                  : Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xffe5e5e5)),
                      color: Colors.white,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sell_rounded,
                          color: Color(0xffce2c20),
                          size: 27,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${offer.displayValue} • ${offer.title}',
                                style: const TextStyle(
                                  color: Color(0xffba261d),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              if (offer.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(
                                    offer.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              Text(
                                offer.termsSummary,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      ],
    ),
  );

  Widget _buildFeaturedDishes() {
    final all = _categoryProducts.values.expand((items) => items).toList();
    final featured = all.where((p) => p.isFeatured).toList();
    final products = (featured.isEmpty ? all : featured).take(8).toList();
    return SizedBox(
      height: 265,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final product = products[index];
          final available =
              _getDishAvailability(product).isAvailable &&
              _canRestaurantAcceptOrders();
          return SizedBox(
            width: 195,
            child: InkWell(
              onTap: available ? () => _openMenuProduct(product) : null,
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          width: 195,
                          height: 158,
                          child:
                              product.imageUrl.isNotEmpty
                                  ? Image.network(
                                    product.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (_, __, ___) => const ColoredBox(
                                          color: Color(0xfff2f2f2),
                                          child: Icon(
                                            Icons.restaurant,
                                            color: Colors.black26,
                                          ),
                                        ),
                                  )
                                  : const ColoredBox(
                                    color: Color(0xfff2f2f2),
                                    child: Icon(
                                      Icons.restaurant,
                                      color: Colors.black26,
                                    ),
                                  ),
                        ),
                      ),
                      PositionedDirectional(
                        end: 9,
                        bottom: 9,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            tooltip: 'إضافة ${product.name}',
                            onPressed:
                                available ? () => _addToCart(product) : null,
                            icon: const Icon(Icons.add, color: Colors.black),
                            constraints: const BoxConstraints.tightFor(
                              width: 38,
                              height: 38,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${product.price.toStringAsFixed(0)} د.ع',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageOfferCard(StoreDiscount offer) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe2e2e2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.network(
            offer.imageUrl!,
            width: double.infinity,
            height: 150,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) => Container(
                  width: double.infinity,
                  height: 150,
                  color: const Color(0xffedf1f5),
                  child: const Icon(
                    Icons.local_offer_outlined,
                    color: Colors.black26,
                    size: 40,
                  ),
                ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _buildOfferCardBody(offer, isYellow: false),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferCardBody(StoreDiscount offer, {required bool isYellow}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    offer.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xff1a1a1a),
                    ),
                  ),
                  if (offer.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        offer.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    isYellow
                        ? const Color(0xffffe082)
                        : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                offer.displayValue,
                style: TextStyle(
                  color:
                      isYellow
                          ? const Color(0xffe65100)
                          : AppColors.secondaryDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 14,
              color: Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                offer.termsSummary.isNotEmpty ? offer.termsSummary : offer.displayValue,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

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
            Icon(Icons.info_outline, color: Colors.grey[400], size: 24),
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
      currentStatusText =
          isWithinWorkingHours == true
              ? _getWorkingHoursStatusText()
              : 'مغلق حالياً';
    } else if (_workingHours?.hasWorkingHours == true) {
      final statusInfo = _workingHours!.statusInfo;
      isWithinWorkingHours = statusInfo['isOpen'] as bool;
      currentStatusText = statusInfo['text'] as String;
    }

    // تحديد أيقونة الحالة الحالية
    IconData currentStatusIcon =
        isWithinWorkingHours == true ? Icons.check_circle : Icons.cancel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عنوان القسم
        Row(
          children: [
            Icon(Icons.access_time, color: AppColors.secondary, size: 24),
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
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: Row(
            children: [
              Icon(
                currentStatusIcon,
                color:
                    isWithinWorkingHours == true
                        ? AppColors.secondary
                        : AppColors.primary,
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
                      currentStatusText.isNotEmpty
                          ? currentStatusText
                          : 'غير محددة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color:
                            isWithinWorkingHours == true
                                ? AppColors.secondary
                                : AppColors.primary,
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
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
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
                separatorBuilder:
                    (context, index) =>
                        Divider(height: 1, color: Colors.grey[200]),
                itemBuilder: (context, index) {
                  final dayHours = _workingHours!.sortedWorkingHours[index];
                  // 🔥 استخدام اليوم الحالي من Backend (timezone المطعم) بدلاً من DateTime.now()
                  final isToday =
                      _currentWeekdayFromBackend != null
                          ? dayHours.weekday.toLowerCase() ==
                              _currentWeekdayFromBackend!.toLowerCase()
                          : dayHours.weekday.toLowerCase() ==
                              _getCurrentWeekday(
                                DateTime.now().weekday,
                              ).toLowerCase();

                  String displayText = 'غير متاح';
                  bool isDayClosed = false;

                  // تحديد نص العرض وحالة اليوم
                  if (_workingHours != null && _workingHours!.hasWorkingHours) {
                    final dayName = dayHours.weekday.toLowerCase();
                    final matchingApiData =
                        _workingHours!.sortedWorkingHours
                            .where(
                              (apiDay) =>
                                  apiDay.weekday.toLowerCase() == dayName,
                            )
                            .firstOrNull;

                    if (matchingApiData != null) {
                      if (matchingApiData.isWorkingDay &&
                          matchingApiData.opening.isNotEmpty &&
                          matchingApiData.closing.isNotEmpty &&
                          matchingApiData.opening != 'none' &&
                          matchingApiData.closing != 'none' &&
                          matchingApiData.opening != 'closed' &&
                          matchingApiData.closing != 'closed') {
                        displayText =
                            '${_formatTimeTo12Hour(matchingApiData.opening)} - ${_formatTimeTo12Hour(matchingApiData.closing)}';
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
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
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
                              fontWeight:
                                  isToday ? FontWeight.bold : FontWeight.w500,
                              color:
                                  isToday ? AppColors.primary : Colors.black87,
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
                                color:
                                    isDayClosed
                                        ? AppColors.primary
                                        : AppColors.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight:
                                        isToday
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                    color:
                                        isDayClosed
                                            ? AppColors.primary
                                            : (isToday
                                                ? AppColors.primary
                                                : Colors.grey[700]),
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
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }

  /// تحديد نص حالة ساعات العمل بناءً على البيانات المتوفرة
  String _getWorkingHoursStatusText() {
    try {
      // 🔥 استخدام isWithinWorkingHours من _availabilityStatus (محسوب في Backend بـ timezone المطعم)
      // بدلاً من الحساب المحلي الذي يستخدم timezone الجهاز
      final isWithinWorkingHoursFromAPI =
          _availabilityStatus?.isWithinWorkingHours ?? false;

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
      if (_availabilityStatus != null &&
          _availabilityStatus!.workingHours.isNotEmpty) {
        final now = DateTime.now();
        final dayName = _getDayNameFromWeekday(now.weekday);
        final todayHours = _availabilityStatus!.workingHours[dayName];

        if (todayHours != null) {
          // فحص إذا كان اليوم مغلق
          if (todayHours.opening.isEmpty ||
              todayHours.closing.isEmpty ||
              todayHours.opening == 'none' ||
              todayHours.closing == 'none' ||
              todayHours.opening == 'closed' ||
              todayHours.closing == 'closed') {
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

  /// تحميل حالة المطعم من RestaurantAvailabilityService الجديد
  Future<void> _loadBusinessStatus({bool skipCache = false}) async {
    if (!mounted) return;

    try {
      developer.log('🔍 جاري تحميل حالة المطعم: ${widget.store.id}');

      // استخدام الخدمة الجديدة
      final availabilityStatus = await _availabilityService
          .checkRestaurantAvailability(widget.store.id, skipCache: skipCache);

      if (mounted) {
        setState(() {
          _availabilityStatus = availabilityStatus;
        });

        developer.log(
          '✅ تم تحميل حالة المطعم: ${availabilityStatus.isAvailable ? "متاح" : availabilityStatus.reasonUnavailable}',
        );
      }
    } catch (e) {
      developer.log('❌ خطأ في تحميل حالة المطعم: $e');
      if (mounted) {
        setState(() {
          _availabilityStatus = null;
        });

        developer.log('⚠️ حالة التوفر غير معروفة بعد فشل التحقق');
      }
    }
  }

  /// معالجة التحديث الفوري لحالة المطعم مع دعم كامل لتحديثات ساعات العمل و isClosed
  Future<void> _handleBusinessStatusUpdate(
    Map<String, dynamic> updateData,
  ) async {
    try {
      developer.log(
        '🚀 StoreDetailScreen: دخل _handleBusinessStatusUpdate مع بيانات: $updateData',
      );

      final businessId = updateData['businessId'] as String?;
      // توحيد المفاتيح بين polling و WebSocket
      final canAcceptOrders =
          (updateData['canAcceptOrders'] as bool?) ??
          (updateData['acceptingOrders'] as bool?);
      final isBusy = updateData['isBusy'] as bool?;
      final statusMessage = updateData['statusMessage'] as String?;
      final isAvailableDirect =
          updateData['isAvailable'] as bool?; // من polling
      final isWithinWorkingHoursDirect =
          updateData['isWithinWorkingHours'] as bool?; // من polling
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
        developer.log(
          '🔄 StoreDetailScreen: تحديث فوري لحالة المطعم ${widget.store.id}',
        );
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
        if ((eventType == 'day_closed' ||
                eventType == 'day_opened' ||
                eventType == 'working_hours_update') &&
            workingHoursUpdated == true &&
            workingHours != null) {
          developer.log(
            '⚡ StoreDetailScreen: معالجة فورية لتحديث isClosed/ساعات العمل',
          );

          // تحديث فوري لحالة ساعات العمل
          final Map<String, WorkingHours?> convertedWorkingHours = {};
          workingHours.forEach((day, hoursData) {
            if (hoursData is Map<String, dynamic>) {
              // فحص حالة isClosed
              final isClosed = hoursData['isClosed'] as bool? ?? false;
              final opening =
                  hoursData['open'] as String? ??
                  hoursData['opening'] as String? ??
                  '';
              final closing =
                  hoursData['close'] as String? ??
                  hoursData['closing'] as String? ??
                  '';

              if (isClosed) {
                // إذا كان مغلق، ضع قيم خاصة
                convertedWorkingHours[day] = WorkingHours(
                  opening: '',
                  closing: '',
                );
              } else {
                // إذا كان مفتوح، استخدم الساعات الفعلية
                convertedWorkingHours[day] = WorkingHours(
                  opening: opening,
                  closing: closing,
                );
              }

              developer.log(
                '   - $day: isClosed=$isClosed, opening=$opening, closing=$closing',
              );
            }
          });

          // تحديد حالة isWithinWorkingHours الجديدة
          final now = DateTime.now();
          final currentDayName = _getDayNameFromWeekday(now.weekday);
          bool newIsWithinWorkingHours = true;

          // البحث عن اليوم الحالي في البيانات المحدثة
          for (final dayName in [
            'saturday',
            'Saturday',
            'SATURDAY',
            currentDayName,
          ]) {
            final todayData = workingHours[dayName];
            if (todayData is Map<String, dynamic>) {
              final isClosed = todayData['isClosed'] as bool? ?? false;
              if (isClosed) {
                newIsWithinWorkingHours = false;
                developer.log('🚫 المطعم مغلق اليوم: $dayName (isClosed=true)');
                break;
              } else {
                // فحص ساعات العمل العادية
                final opening =
                    todayData['open'] as String? ??
                    todayData['opening'] as String? ??
                    '';
                final closing =
                    todayData['close'] as String? ??
                    todayData['closing'] as String? ??
                    '';
                if (opening.isNotEmpty &&
                    closing.isNotEmpty &&
                    opening != 'none' &&
                    closing != 'none') {
                  // فحص إذا كان الوقت الحالي ضمن ساعات العمل
                  newIsWithinWorkingHours = _isCurrentTimeWithinWorkingHours(
                    opening,
                    closing,
                  );
                  developer.log(
                    '⏰ فحص ساعات العمل: $opening-$closing -> $newIsWithinWorkingHours',
                  );
                }
                break;
              }
            }
          }

          // إنشاء حالة جديدة مع البيانات المحدثة فورياً
          final newAvailabilityStatus = RestaurantAvailabilityStatus(
            businessId: widget.store.id,
            isAvailable:
                (canAcceptOrders ??
                    (_availabilityStatus?.acceptingOrders ?? true)) &&
                newIsWithinWorkingHours,
            acceptingOrders:
                canAcceptOrders ??
                (_availabilityStatus?.acceptingOrders ?? true),
            isWithinWorkingHours: newIsWithinWorkingHours,
            workingHours: convertedWorkingHours,
            checkedAt: DateTime.now(),
            reasonUnavailable: _getReasonFromStatus(
              isBusy,
              canAcceptOrders,
              statusMessage,
              newIsWithinWorkingHours,
            ),
          );

          // تطبيق التحديث فورياً
          setState(() {
            _availabilityStatus = newAvailabilityStatus;
          });

          developer.log('✅ تم تحديث فوري لحالة isClosed في StoreDetailScreen:');
          developer.log('   - isWithinWorkingHours: $newIsWithinWorkingHours');
          developer.log(
            '   - isAvailable: ${newAvailabilityStatus.isAvailable}',
          );
          developer.log(
            '   - reasonUnavailable: ${newAvailabilityStatus.reasonUnavailable}',
          );

          // إعادة تحميل ساعات العمل من قاعدة البيانات للحصول على التفاصيل الكاملة
          if (workingHoursUpdated == true || forceStatusRecheck == true) {
            developer.log(
              '🕒 إعادة تحميل ساعات العمل الكاملة من قاعدة البيانات',
            );
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
          final currentWeekday =
              updateData['currentWeekday'] as String?; // 🔥 اليوم الحالي

          developer.log('🔍 StoreDetailScreen: بيانات polling:');
          developer.log('   - isAvailableNow: $isAvailableNow');
          developer.log('   - currentStatus: $currentStatus');
          developer.log('   - isClosed: $isClosed');
          developer.log('   - acceptingOrders: $canAcceptOrders');
          developer.log(
            '   - isWithinWorkingHours: $isWithinWorkingHoursDirect',
          );
          developer.log('   - currentWeekday: $currentWeekday'); // 🔥 debug

          // 🔥 حفظ اليوم الحالي من Backend
          if (currentWeekday != null) {
            _currentWeekdayFromBackend = currentWeekday;
          }

          // تحديث مباشر بدون طلب شبكة اعتماداً على البيانات المرسلة من خدمة polling
          // 🔥 استخدام isAvailableNow كمصدر رئيسي للحقيقة
          final effectiveIsAvailable =
              isAvailableNow ??
              ((isAvailableDirect != null)
                  ? isAvailableDirect
                  : ((canAcceptOrders ?? false) &&
                      (isWithinWorkingHoursDirect ?? false)));

          // 🔥 استخدام isWithinWorkingHoursDirect من Backend (محسوب بـ timezone صحيح)
          final effectiveIsWithinWorkingHours =
              isWithinWorkingHoursDirect ??
              _availabilityStatus?.isWithinWorkingHours ??
              true;

          final updatedStatus = RestaurantAvailabilityStatus(
            businessId: widget.store.id,
            isAvailable: effectiveIsAvailable,
            acceptingOrders:
                canAcceptOrders ??
                _availabilityStatus?.acceptingOrders ??
                false,
            isWithinWorkingHours: effectiveIsWithinWorkingHours,
            workingHours: _availabilityStatus?.workingHours ?? {},
            checkedAt: DateTime.now(),
            reasonUnavailable: _getReasonFromStatus(
              isBusy,
              canAcceptOrders,
              statusMessage,
              effectiveIsWithinWorkingHours,
            ),
          );

          developer.log('✅ StoreDetailScreen: تحديث حالة المطعم:');
          developer.log('   - isAvailable: ${updatedStatus.isAvailable}');
          developer.log(
            '   - acceptingOrders: ${updatedStatus.acceptingOrders}',
          );
          developer.log(
            '   - isWithinWorkingHours: ${updatedStatus.isWithinWorkingHours}',
          );

          setState(() {
            _availabilityStatus = updatedStatus;
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
            developer.log(
              '🔄 إعادة build إضافية للتأكد من التحديث المرئي في StoreDetailScreen',
            );
          }
        });
      }
    } catch (e) {
      developer.log(
        '❌ خطأ في معالجة تحديث حالة المطعم في StoreDetailScreen: $e',
      );
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
      final newAvailabilityStatus = await _availabilityService
          .checkRestaurantAvailability(widget.store.id);

      if (mounted && _availabilityStatus != null) {
        // التحقق من تغيير الحالة
        if (_availabilityStatus!.isAvailable !=
                newAvailabilityStatus.isAvailable ||
            _availabilityStatus!.acceptingOrders !=
                newAvailabilityStatus.acceptingOrders) {
          developer.log(
            '📊 تغييرت حالة المطعم من ${_availabilityStatus!.isAvailable ? "متاح" : "غير متاح"} إلى ${newAvailabilityStatus.isAvailable ? "متاح" : "غير متاح"}',
          );

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
      developer.log(
        '🔌 StoreDetailScreen: إعداد SubscriptionManager للمطعم: ${widget.store.id}',
      );

      // إلغاء أي اشتراك سابق
      _businessStatusSubscription?.cancel();

      // الاشتراك في تحديثات polling من SubscriptionManager
      _businessStatusSubscription = _subscriptionManager
          .subscribeToBusinessStatus(widget.store.id, _subscriberId)
          .listen(
            (updateData) async {
              developer.log(
                '📥 StoreDetail: استقبال تحديث من ${updateData['source'] ?? 'unknown'} للمطعم: ${widget.store.id}',
              );

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
              developer.log(
                '⚠️ تم إغلاق stream للمطعم ${widget.store.id} - إعادة إعداد',
              );
              if (mounted) {
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) _setupSubscriptionListener();
                });
              }
            },
          );

      developer.log(
        '✅ تم إعداد SubscriptionManager بنجاح للمطعم: ${widget.store.id}',
      );
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
      message =
          statusMessage.isNotEmpty
              ? statusMessage
              : 'المطعم متاح الآن لاستقبال الطلبات';
      backgroundColor = AppColors.primary;
      icon = Icons.check_circle;
    } else {
      message =
          statusMessage.isNotEmpty
              ? statusMessage
              : 'المطعم غير متاح حالياً لاستقبال الطلبات';
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
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// فحص إذا كان الوقت الحالي ضمن ساعات العمل
  bool _isCurrentTimeWithinWorkingHours(String opening, String closing) {
    try {
      final now = DateTime.now();
      final currentTime =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

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
        return currentMinutes >= openingMinutes &&
            currentMinutes <= closingMinutes;
      } else {
        // حالة تتجاوز منتصف الليل (مثل 22:00 - 06:00)
        return currentMinutes >= openingMinutes ||
            currentMinutes <= closingMinutes;
      }
    } catch (e) {
      developer.log('خطأ في فحص ساعات العمل: $e');
      return true; // افتراض أنه مفتوح في حالة الخطأ
    }
  }

  /// الحصول على سبب عدم الإتاحة
  String _getReasonFromStatus(
    bool? isBusy,
    bool? canAcceptOrders,
    String? statusMessage,
    bool isWithinWorkingHours,
  ) {
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
      return AppColors
          .secondary; // مشغول أو لا يستقبل طلبات - استخدام اللون الثانوي
    }

    // Priority 3: Check general availability
    if (_availabilityStatus != null && !_availabilityStatus!.isAvailable) {
      return AppColors.secondary; // غير متاح بشكل عام - استخدام اللون الثانوي
    }

    return Colors.green; // متاح ومفتوح
  }

  /// دالة لتحديد حالة إتاحة الطبق
  DishAvailability _getDishAvailability(ProductModel product) {
    // 🔥 التحقق من علم التوفر القادم من الـ API (نفدت الكمية / موقوف)
    if (!product.isAvailable) {
      return const DishAvailability(
        isAvailable: false,
        reasonText: 'نفدت الكمية',
        message: 'هذا المنتج غير متوفر حالياً',
        icon: Icons.remove_shopping_cart,
        statusColor: Colors.red,
      );
    }

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

  /// إضافة منتج إلى السلة (مع نافذة تعارض المطاعم عند الحاجة)
  Future<void> _addToCart(ProductModel product) async {
    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);

      // طباعة عنوان المطعم للتشخيص
      developer.log('🏪 _addToCart: إضافة منتج للسلة من المطعم:');
      developer.log('  اسم المطعم: ${widget.store.name}');
      developer.log('  معرف المطعم: ${widget.store.id}');

      // تحديد العنوان النهائي للمطعم
      final finalStoreAddress =
          widget.store.address.isEmpty || widget.store.address.contains('متوفر')
              ? 'عنوان المطعم غير محدد - ${widget.store.name}'
              : widget.store.address;

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

      // 🔥 فحص تعارض المطاعم: السلة لكلها عناصر من مطعم واحد فقط
      final existingStoreId = appState.cart.currentStoreId;
      if (existingStoreId != null && existingStoreId != widget.store.id) {
        if (!mounted) return;
        final otherStoreName = appState.cartStoreName ?? 'مطعم آخر';
        final clearAndAdd = await showClearCartConflictSheet(
          context,
          otherStoreName: otherStoreName,
        );
        if (clearAndAdd == true) {
          developer.log(
            '🗑️ مسح السلة وإضافة ${product.name} من ${widget.store.name}',
          );
          await appState.clearCart();
          await appState.addToCart(cartItem);
        } else {
          developer.log('⏸️ الاحتفاظ بالسلة الحالية - تم إلغاء الإضافة');
          return;
        }
      } else {
        // إضافة العنصر للسلة
        await appState.addToCart(cartItem);
      }

      // التحقق من نجاح الإضافة قبل عرض رسالة التأكيد
      if (appState.errorMessage != null) {
        if (appState.errorMessage == 'DIFFERENT_STORE') {
          appState.clearError();
        }
        developer.log('⚠️ لم تتم إضافة المنتج: ${appState.errorMessage}');
        return;
      }

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
            margin: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).padding.bottom + 100,
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
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setModalState) => Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(25),
                    ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
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
                                searchTimer
                                    ?.cancel(); // تنظيف الـ timer عند الإغلاق
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
                                searchTimer = Timer(
                                  const Duration(milliseconds: 300),
                                  () {
                                    if (mounted) {
                                      _performSearch(value, setModalState, (
                                        results,
                                      ) {
                                        searchResults = results;
                                      });
                                    }
                                  },
                                );
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
                              suffixIcon:
                                  searchController.text.isNotEmpty
                                      ? IconButton(
                                        onPressed: () {
                                          searchTimer
                                              ?.cancel(); // إلغاء البحث المُعلَّق
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
                        child:
                            isSearching
                                ? _buildSearchResults(
                                  searchResults,
                                  setModalState,
                                )
                                : _buildSearchSuggestions(),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  // تنفيذ البحث المحسن
  void _performSearch(
    String query,
    StateSetter setModalState,
    Function(List<ProductModel>) onResults,
  ) {
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
  Widget _buildSearchResults(
    List<ProductModel> results,
    StateSetter setModalState,
  ) {
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
  Widget _buildSearchResultItem(
    ProductModel product,
    StateSetter setModalState,
  ) {
    final dishAvailability = _getDishAvailability(product);
    final canOrder = dishAvailability.isAvailable;
    final canRestaurantAcceptOrders = _canRestaurantAcceptOrders();
    final isCompletelyUnavailable = !canRestaurantAcceptOrders || !canOrder;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap:
            isCompletelyUnavailable
                ? null
                : () async {
                  Navigator.pop(context); // إغلاق البحث

                  // التحقق من حالة المطعم مرة أخرى قبل الانتقال
                  bool canRestaurantAcceptOrders = _canRestaurantAcceptOrders();
                  String? restaurantStatusMessage =
                      _getRestaurantStatusMessage();

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
                                child: Icon(
                                  _getRestaurantStatusIcon(),
                                  color: AppColors.secondary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  restaurantStatusMessage ??
                                      'المطعم غير متاح حالياً',
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
                        backgroundColor: _getRestaurantStatusColor().withValues(
                          alpha: 0.9,
                        ),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          MediaQuery.of(context).padding.bottom + 100,
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
                                child: Icon(
                                  dishAvailability.icon,
                                  color: AppColors.secondary,
                                  size: 18,
                                ),
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
                        backgroundColor: dishAvailability.statusColor
                            .withValues(alpha: 0.9),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          MediaQuery.of(context).padding.bottom + 100,
                        ),
                        duration: const Duration(seconds: 3),
                        elevation: 6,
                      ),
                    );
                    return;
                  }

                  // فتح تفاصيل الطبق في لوحة سفلية مع تمرير productData
                  final dish = Dish(
                    id: product.id,
                    name: product.name,
                    description: product.description,
                    imageUrls:
                        product.imageUrl.isNotEmpty ? [product.imageUrl] : [],
                    likesPercent: 85,
                    likesCount: 120,
                    basePrice: product.price,
                    optionGroups: [],
                  );

                  try {
                    developer.log(
                      '🔄 فتح اللوحة السفلية لتفاصيل الطبق من البحث',
                    );
                    developer.log('  منتج: ${product.name}');
                    developer.log('  تمرير productData: نعم');

                    final result = await showDishDetailBottomSheet(
                      context,
                      dish: dish,
                      storeId: widget.store.id,
                      storeName: widget.store.name, // تمرير اسم المتجر
                      storeAddress:
                          widget.store.address, // تمرير عنوان المتجر للسائقين
                      productData: product, // تمرير بيانات المنتج الكاملة
                    );

                    developer.log(
                      '🔙 إغلاق اللوحة السفلية لتفاصيل الطبق (من البحث)',
                    );
                    developer.log('  النتيجة: $result');
                  } catch (e) {
                    developer.log('❌ خطأ في فتح اللوحة السفلية من البحث: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'خطأ في فتح تفاصيل الطبق: ${e.toString()}',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primary.withValues(
          alpha: 0.1,
        ), // إضافة تأثير splash
        highlightColor: AppColors.primary.withValues(
          alpha: 0.05,
        ), // إضافة تأثير highlight
        child: Opacity(
          opacity: isCompletelyUnavailable ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // صورة المنتج
                Hero(
                  // إضافة Hero animation للصورة
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
                      child:
                          product.imageUrl.isNotEmpty
                              ? Image.network(
                                product.imageUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (
                                  context,
                                  child,
                                  loadingProgress,
                                ) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value:
                                          loadingProgress.expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
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
                          color:
                              isCompletelyUnavailable
                                  ? Colors.grey
                                  : Colors.black87,
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
                            color:
                                isCompletelyUnavailable
                                    ? Colors.grey
                                    : Colors.grey[600],
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
                              color:
                                  isCompletelyUnavailable
                                      ? Colors.grey
                                      : AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          if (!isCompletelyUnavailable)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
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
            Icon(Icons.search, size: 48, color: Colors.grey),
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
              style: TextStyle(fontSize: 14, color: Colors.grey),
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
              child: Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
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
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Delegate للشريط اللاصق (بحث + تبويبات الفئات) في صفحة المطعم
class _StickyMenuHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _StickyMenuHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyMenuHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
