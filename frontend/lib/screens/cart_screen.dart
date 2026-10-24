import '../services/checkout_invoice_store.dart';
import '../widgets/basket_invoice.dart';
import 'dart:async';
import 'dart:convert';
import '../widgets/basket_line_card.dart';
import '../services/storefront_pricing.dart';
import '../widgets/storefront_value.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/store.dart';
import '../models/product_model.dart';
import '../services/restaurant_availability_service.dart';
import '../services/business_service.dart';
import '../screens/checkout_screen.dart';
import './store_detail_screen.dart';

class CartScreen extends StatefulWidget {
  final String? storeName;
  final String? storeId;
  final List<Store>? stores; // قائمة المتاجر للبحث عن اسم المطعم

  final StorefrontPricing? pricing;
  final WidgetBuilder? checkoutBuilder;

  // إعدادات السلة

  const CartScreen({
    super.key,
    this.storeName,
    this.storeId,
    this.stores,
    this.pricing,
    this.checkoutBuilder,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final StorefrontPricing _pricing =
      widget.pricing ?? StorefrontPricing.instance;
  final _suggestedProducts = <String, Future<List<ProductModel>>>{};
  bool _continuing = false;
  String? _continueError;

  String _branch(AppStateProvider state) =>
      state.cart.currentStoreId ?? widget.storeId ?? '';

  Future<void> _continueCheckout(AppStateProvider state) async {
    if (_continuing || state.cartItems.isEmpty) return;
    setState(() {
      _continuing = true;
      _continueError = null;
    });
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final branch = _branch(state), items = state.cartItems;
        if (items.isEmpty) return;
        final fingerprint = jsonEncode(items),
            scope = _pricing.key(branch, items);
        final invoiceRequest = CheckoutInvoiceStore.instance.basketRequest(
          branch,
          items,
        );
        final prepared =
            invoiceRequest == null
                ? null
                : CheckoutInvoiceStore.instance.peek(invoiceRequest);
        if (scope != null && prepared == null) {
          final preview = await _pricing.load(branch, items);
          if (!mounted) return;
          if (branch != _branch(state) ||
              fingerprint != jsonEncode(state.cartItems) ||
              scope != _pricing.key(branch, state.cartItems))
            continue;
          if (preview == null) {
            setState(
              () =>
                  _continueError =
                      'تعذر تحديث بيانات التوصيل. تحقق من الاتصال ثم أعد المحاولة.',
            );
            return;
          }
        }
        final minimum = _pricing.minimumIqd(branch, state.cartItems);
        if (minimum != null && state.cartTotal < minimum) {
          setState(
            () =>
                _continueError =
                    'الحد الأدنى للأصناف ${basketMoney(minimum)}. أضف ${basketMoney(minimum - state.cartTotal)} للمتابعة.',
          );
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                widget.checkoutBuilder ??
                (_) => CheckoutScreen(
                  storeId: branch,
                  storeName: _resolveStoreName() ?? 'المطعم',
                ),
          ),
        );
        return;
      }
      if (mounted)
        setState(
          () =>
              _continueError =
                  'تغيّرت السلة أثناء التحقق. راجع الكمية ثم تابع.',
        );
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  String? _resolveStoreName() {
    final activeBranch = _branch(context.read<AppStateProvider>());
    // قائمة الأسماء المرفوضة (الافتراضية/الخاطئة)
    final rejectedNames = ['متجر', 'المطعم', 'عربة التسوق'];

    // 1. فحص اسم المتجر الممرر، ولكن نتجاهل الأسماء المرفوضة
    if ((widget.storeId == null || widget.storeId == activeBranch) &&
        widget.storeName != null &&
        widget.storeName!.isNotEmpty &&
        !rejectedNames.contains(widget.storeName)) {
      return widget.storeName;
    }

    // 2. محاولة البحث في قائمة المتاجر بناءً على storeId (حتى لو كان اسم المطعم في السلة غير صحيح)
    if (activeBranch.isNotEmpty && widget.stores != null) {
      final found = widget.stores!.firstWhere(
        (s) => s.id == activeBranch,
        orElse:
            () => Store(
              id: '',
              name: '',
              image: '',
              logoUrl: '',
              isOpen: true,
              fee: '',
              rating: '',
              reviews: '',
              distance: '',
              time: '',
              address: '',
              combos: const [],
              sandwiches: const [],
              drinks: const [],
              extras: const [],
              specialties: const [],
            ),
      );
      // حتى لو كان اسم المطعم في السلة غير صحيح، نأخذ الاسم من قائمة المتاجر إذا كان موجوداً
      if (found.name.isNotEmpty && !rejectedNames.contains(found.name)) {
        return found.name;
      }
    }

    // 3. استخراج اسم المتجر من بيانات السلة نفسها (قد يكون غير دقيق أحياناً)
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    if (appState.cartItems.isNotEmpty) {
      final firstItem = appState.cartItems.first;
      final storeName = firstItem['store_name'] as String?;
      if (storeName != null &&
          storeName.isNotEmpty &&
          !rejectedNames.contains(storeName)) {
        return storeName;
      }
    }

    return 'عربة التسوق';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xfff6f8fb),
        body: Consumer<AppStateProvider>(
          builder: (context, appState, child) {
            if (appState.cartItems.isEmpty) {
              return _buildEmptyCart(context);
            }
            return BasketInvoiceWarmup(
              branch: _branch(appState),
              items: appState.cartItems,
              storeName: _resolveStoreName() ?? 'المطعم',
              child: _buildCartContent(context, appState),
            );
          },
        ),
      ),
    );
  }

  // شاشة السلة الفارغة - تصميم جميل ومحسن
  Widget _buildEmptyCart(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // هيدر مبسط
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _navigateBackToStore(context),
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.black87,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                const Text(
                  'سلة التسوق',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          // محتوى السلة الفارغة
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // تأثير السلة الفارغة مع أنيميشن
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 800),
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.8 + (0.2 * value),
                        child: Opacity(
                          opacity: value,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // دائرة خلفية بلون solid بدلاً من التدرج
                              Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(80),
                                  border: Border.all(
                                    color: AppColors.secondary.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 2,
                                  ),
                                ),
                              ),
                              // أيقونة السلة الفارغة مع تأثير
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(60),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.secondary.withValues(
                                        alpha: 0.15,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 60,
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              // نقاط متحركة للديكور
                              Positioned(
                                top: 20,
                                right: 20,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withValues(
                                      alpha: 0.4,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 30,
                                left: 15,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withValues(
                                      alpha: 0.3,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 40,
                                left: 25,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.5,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ], // نهاية children للـ Stack
                          ), // نهاية Stack
                        ), // نهاية Opacity
                      ); // نهاية Transform.scale
                    },
                  ),
                  const SizedBox(height: 32),
                  // النصوص مع تأثير تدريجي
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 1000),
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - value).toDouble()),
                        child: Opacity(
                          opacity: value,
                          child: Column(
                            children: [
                              const Text(
                                'سلتك فارغة',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'أضف بعض الأطباق اللذيذة لتبدأ رحلتك',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'اكتشف مئات الأطباق من مطاعمك المفضلة',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ), // نهاية Transform.translate للنصوص
                      ); // نهاية return من builder
                    },
                  ), // نهاية TweenAnimationBuilder للنصوص
                  const SizedBox(height: 48),
                  // زر التصفح مع تصميم جديد
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 1200),
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 30 * (1 - value).toDouble()),
                        child: Opacity(
                          opacity: value,
                          child: Container(
                            width: MediaQuery.of(context).size.width,
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: AppColors.secondary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                              ),
                              onPressed: () => _navigateBackToStore(context),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.restaurant_menu, size: 22),
                                  SizedBox(width: 12),
                                  Text(
                                    'تصفح المطاعم',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ), // نهاية Transform.translate للزر
                      ); // نهاية return من builder
                    },
                  ), // نهاية TweenAnimationBuilder للزر
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // محتوى السلة مع الأطباق - تصميم DoorDash
  Widget _buildCartContent(BuildContext context, AppStateProvider appState) {
    return SafeArea(
      child: Column(
        children: [
          // هيدر مع اسم المطعم
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _navigateBackToStore(context),
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.black87,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'سلة التسوق',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (_resolveStoreName() != 'عربة التسوق')
                        Text(
                          _resolveStoreName() ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // قائمة الأطباق
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // عناصر السلة مع index
                ...appState.cartItems.asMap().entries.map(
                  (entry) =>
                      _buildCartItem(context, appState, entry.value, entry.key),
                ),
                const SizedBox(height: 24),
                // قسم الاقتراحات من نفس المطعم
                _buildSuggestionsSection(context, appState),
                const SizedBox(height: 24),
                // زر إضافة المزيد من الأطباق
                _buildAddMoreDishesButton(context),
                const SizedBox(height: 24),
                // تفاصيل السلة
                _buildCartSummary(context, appState),
                const SizedBox(height: 20),
              ],
            ),
          ),
          // زر المتابعة في الأسفل
          ListenableBuilder(
            listenable: _pricing,
            builder: (context, _) => _buildCheckoutButton(context, appState),
          ),
        ],
      ),
    );
  }

  // عنصر في السلة - تصميم DoorDash المبسط مع زر الحذف في الأعلى
  // عنصر في السلة - تصميم DoorDash المبسط مع زر الحذف في الأعلىppState, dynamic item) {
  Widget _buildCartItem(
    BuildContext context,
    AppStateProvider appState,
    dynamic item,
    int index,
  ) {
    final line = appState.cart.items[index];
    return BasketLineCard(
      key: ValueKey(line.lineKey),
      item: line,
      increase: () {
        appState.changeCartLineQuantity(line, 1);
        setState(() => _continueError = null);
      },
      decrease: () {
        appState.changeCartLineQuantity(line, -1);
        setState(() => _continueError = null);
      },
      remove: () => _showDeleteConfirmation(context, appState, index),
    );
  }

  // قسم الاقتراحات من نفس المطعم - محسن مع فلترة حسب نوع النشاط والفئات المحددة
  Widget _buildSuggestionsSection(
    BuildContext context,
    AppStateProvider appState,
  ) {
    final currentStoreId = _branch(appState);
    if (currentStoreId.isEmpty) return const SizedBox.shrink();

    // 🔥 استخدام البيانات المحفوظة بدلاً من عمل استعلام
    final businessData = appState.getBusinessSuggestionData(currentStoreId);

    if (businessData == null) return const SizedBox.shrink();

    // ✅ عرض الاقتراحات فقط للمطاعم - أو إذا كان businessType فارغ (افتراض أنه مطعم)
    final shouldShowSuggestions =
        businessData.isRestaurant ||
        businessData.businessType == null ||
        businessData.businessType!.isEmpty;

    if (!shouldShowSuggestions) return const SizedBox.shrink();

    // 🔥 استخدام الفئات المحفوظة بدلاً من جلبها من قاعدة البيانات
    final suggestionCategories = businessData.suggestionAvailableCategories;

    if (suggestionCategories.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<ProductModel>>(
      future: _suggestedProducts.putIfAbsent(
        currentStoreId,
        () => _loadSuggestedProducts(currentStoreId),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final suggestions = snapshot.data!;

        // استبعد المنتجات الموجودة بالفعل في السلة
        final cartProductIds =
            appState.cartItems.map((item) => item['id'] ?? '').toSet();
        final availableSuggestions =
            suggestions
                .where(
                  (product) =>
                      product.isAvailable &&
                      product.price.isFinite &&
                      product.price > 0 &&
                      !cartProductIds.contains(product.id),
                )
                .toList();

        if (availableSuggestions.isEmpty) {
          return const SizedBox.shrink();
        }

        // حدد العدد الأقصى للاقتراحات المعروضة
        final displaySuggestions =
            availableSuggestions.length > 6
                ? availableSuggestions.take(6).toList()
                : availableSuggestions;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.restaurant_menu,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'قد يعجبك أيضاً',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'من ${businessData.businessName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(displaySuggestions.length, (i) {
                    final suggestion = displaySuggestions[i];
                    return Padding(
                      padding: EdgeInsets.only(
                        left: i < displaySuggestions.length - 1 ? 12 : 0,
                      ),
                      child: _buildProductSuggestionItem(
                        context,
                        appState,
                        suggestion,
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🔍 تحميل المنتجات المقترحة من الفئات المحددة فقط
  Future<List<ProductModel>> _loadSuggestedProducts(String businessId) async {
    try {
      // جلب جميع فئات ومنتجات المطعم
      final categoryProducts =
          await BusinessService.getBusinessCategoriesAndProducts(businessId);

      // الفئات المطلوبة للاقتراحات - شاملة للإنجليزي والعربي وتنويعات الكتابة
      final targetCategories = {
        // المقبلات
        'appetizers', 'المقبلات', 'appetizer', 'starter', 'starters',
        // المشروبات
        'beverages', 'المشروبات', 'beverage', 'drinks', 'drink',
        // المشروبات الباردة
        'cold drinks',
        'المشروبات الباردة',
        'cold drink',
        'cold beverage',
        'cold beverages',
        // البسكويت
        'cookies', 'البسكويت', 'cookie', 'biscuit', 'biscuits',
        // الحلويات
        'desserts', 'الحلويات', 'dessert', 'sweet', 'sweets',
        // الأطباق الجانبية
        'sides', 'الأطباق الجانبية', 'side', 'side dish', 'side dishes',
      };

      final List<ProductModel> suggestions = [];

      // البحث في فئات المطعم عن الفئات المطلوبة
      for (final entry in categoryProducts.entries) {
        final categoryName = entry.key.toLowerCase().trim();
        final products = entry.value;

        // فحص محسن لمطابقة الفئات - مطابقة مرنة وشاملة
        bool isTargetCategory = false;

        // فحص المطابقة مع تجاهل الحالة والمسافات
        for (final target in targetCategories) {
          final targetLower = target.toLowerCase().trim();
          final categoryLower = categoryName.toLowerCase().trim();

          // مطابقة مباشرة تماماً
          if (categoryLower == targetLower) {
            isTargetCategory = true;
            break;
          }

          // مطابقة جزئية محسنة - البحث في كلا الاتجاهين
          if (categoryLower.contains(targetLower) ||
              targetLower.contains(categoryLower)) {
            // تأكد من أن الطول كافٍ للمطابقة الجزئية
            final minLength =
                targetLower.length >= 4 || categoryLower.length >= 4;
            if (minLength) {
              isTargetCategory = true;
              break;
            }
          }

          // مطابقة خاصة للكلمات المفتاحية الشائعة (إزالة التكرار مع الحلقة أعلاه)
          if ((categoryLower.contains('side') &&
                  targetLower.contains('side')) ||
              (categoryLower.contains('drink') &&
                  targetLower.contains('drink')) ||
              (categoryLower.contains('beverage') &&
                  targetLower.contains('beverage')) ||
              (categoryLower.contains('dessert') &&
                  targetLower.contains('dessert')) ||
              (categoryLower.contains('sweet') &&
                  targetLower.contains('sweet')) ||
              (categoryLower.contains('cookie') &&
                  targetLower.contains('cookie')) ||
              (categoryLower.contains('appetizer') &&
                  targetLower.contains('appetizer'))) {
            isTargetCategory = true;
            break;
          }
        }

        if (isTargetCategory && products.isNotEmpty) {
          // إضافة المنتجات من هذه الفئة (حد أقصى 3 منتجات لكل فئة)
          final productsToAdd = products.take(3).toList();
          suggestions.addAll(productsToAdd);
        }
      }

      // خلط الاقتراحات للحصول على تنوع أكبر
      suggestions.shuffle();

      return suggestions;
    } catch (e) {
      return [];
    }
  }

  // زر إضافة المزيد من الأطباق
  Widget _buildAddMoreDishesButton(BuildContext context) => OutlinedButton.icon(
    onPressed: () => _navigateBackToStore(context),
    icon: const Icon(Icons.add_rounded),
    label: const Text('إضافة أطباق من المطعم'),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.secondary,
      minimumSize: const Size.fromHeight(48),
      side: const BorderSide(color: Color(0xffdce5f0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  Widget _buildCartSummary(BuildContext context, AppStateProvider appState) {
    final int totalDishes = appState.cartItems.fold(
      0,
      (sum, item) => sum + (item['quantity'] as int? ?? 1),
    );
    final double subtotal = appState.cartTotal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffe3eaf2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'تفاصيل السلة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // عدد الأطباق
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مجموع الأصناف ($totalDishes قطعة)',
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
              Text(
                basketMoney(subtotal),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // رسوم التوصيل
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'رسوم التوصيل',
                style: TextStyle(fontSize: 15, color: Colors.black87),
              ),
              Flexible(
                child: BasketInvoiceDelivery(
                  pricing: _pricing,
                  branch: _branch(appState),
                  items: appState.cartItems,
                  fallback: StorefrontValue(
                    branchId: _branch(appState),
                    field: StorefrontField.fee,
                    pricing: _pricing,
                    requestDebounce: const Duration(milliseconds: 250),
                    items: appState.cartItems,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
          BasketInvoiceTotals(
            branch: _branch(appState),
            items: appState.cartItems,
            storeName: _resolveStoreName() ?? 'المطعم',
          ),
          const Divider(height: 24),
          const Text(
            'تُحدّث الفاتورة عند تغيير الأصناف أو العنوان أو إضافة خصم أو إكرامية.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton(BuildContext context, AppStateProvider appState) {
    final minimum = _pricing.minimumIqd(_branch(appState), appState.cartItems);
    final below = minimum != null && appState.cartTotal < minimum;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xffe3eaf2))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_continueError != null || below)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _continueError ??
                      'الحد الأدنى للأصناف ${basketMoney(minimum!)} · أضف ${basketMoney(minimum - appState.cartTotal)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed:
                    _continuing ? null : () => _continueCheckout(appState),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondaryDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child:
                    _continuing
                        ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.secondary,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('جارٍ التحقق…'),
                          ],
                        )
                        : const Text(
                          'متابعة الطلب',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // عرض رسالة Snackbar
  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // العودة لنفس المطعم أو الشاشة الرئيسية
  void _navigateBackToStore(BuildContext context) {
    final branch = _branch(context.read<AppStateProvider>());
    final store = widget.stores?.where((s) => s.id == branch).firstOrNull;
    if (store != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)),
      );
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // عرض رسالة تأكيد الحذف
  void _showDeleteConfirmation(
    BuildContext context,
    AppStateProvider appState,
    int index,
  ) {
    final item = appState.cartItems[index];
    final line = appState.cart.items[index];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // مؤشر السحب
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                // أيقونة التحذير
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 40,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                // عنوان التأكيد
                const Text(
                  'حذف الطبق',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                // رسالة التأكيد
                Text(
                  'هل أنت متأكد من حذف "${item['name'] ?? 'هذا الطبق'}" من السلة؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                // أزرار التأكيد والإلغاء
                Row(
                  children: [
                    // زر الإلغاء
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // زر التأكيد
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: AppColors.secondary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          appState.removeCartLine(line);
                          Navigator.pop(context);
                          _showSnackBar(
                            context,
                            'تم حذف 	${item['name'] ?? 'الطبق'} من السلة',
                            Colors.red,
                          );
                        },
                        child: const Text(
                          'حذف',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🎨 عرض عنصر اقتراح من ProductModel
  Widget _buildProductSuggestionItem(
    BuildContext context,
    AppStateProvider appState,
    ProductModel product,
  ) {
    final isInCart = appState.cartItems.any(
      (item) => (item['id'] ?? '') == product.id,
    ); // ✅ إصلاح: تغيير من 'dish_id' إلى 'id'

    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Builder(
                builder: (context) {
                  // إذا كان الرابط يبدأ بـ http أو https، استخدم Image.network
                  if (product.imageUrl.isNotEmpty &&
                      (product.imageUrl.startsWith('http://') ||
                          product.imageUrl.startsWith('https://'))) {
                    return Image.network(
                      product.imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[200],
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.grey[400]!,
                              ),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: Icon(
                            Icons.restaurant,
                            color: Colors.grey[400],
                            size: 30,
                          ),
                        );
                      },
                    );
                  }

                  // في حالة عدم وجود صورة صالحة
                  return Container(
                    color: Colors.grey[200],
                    child: Icon(
                      Icons.fastfood,
                      color: Colors.grey[400],
                      size: 30,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '${product.price.toStringAsFixed(2)} د.ع',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              if (!isInCart) {
                _addProductToCart(context, appState, product);
              }
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isInCart ? Colors.green : AppColors.primary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (isInCart ? Colors.green : AppColors.primary)
                        .withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                isInCart ? Icons.check : Icons.add,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🛒 إضافة منتج للسلة
  void _addProductToCart(
    BuildContext context,
    AppStateProvider appState,
    ProductModel product,
  ) async {
    final branch = _branch(appState);
    if (branch.isEmpty ||
        (product.businessId.isNotEmpty && product.businessId != branch))
      return;
    try {
      // Preserve merchant availability checks for optional suggestions.
      if (branch.isNotEmpty) {
        final availabilityService = RestaurantAvailabilityService.instance;
        final availabilityStatus = await availabilityService
            .checkRestaurantAvailability(branch, skipCache: true);

        if (!mounted || !context.mounted || branch != _branch(appState)) return;
        if (!availabilityStatus.isAvailable) {
          String errorMessage;

          if (!availabilityStatus.acceptingOrders) {
            errorMessage = 'عذراً، هذا المطعم لا يستقبل طلبات جديدة حالياً';
          } else if (!availabilityStatus.isWithinWorkingHours) {
            errorMessage = 'عذراً، هذا المطعم مغلق حالياً';
          } else {
            errorMessage =
                availabilityStatus.reasonUnavailable ??
                'عذراً، هذا المطعم غير متاح حالياً';
          }

          _showSnackBar(context, errorMessage, Colors.orange.shade600);
          return;
        }
      }

      // ✅ المطعم متاح، إضافة المنتج للسلة
      final cartItem = {
        'id': product.id, // ✅ إصلاح: تغيير من 'dish_id' إلى 'id'
        'name': product.name,
        'description': product.description,
        'image': product.imageUrl,
        'price': product.price,
        'quantity': 1,
        'store_id': branch,
        'store_name': _resolveStoreName() ?? 'المطعم',
      };
      final success = await appState.addToCart(
        cartItem,
      ); // ✅ إصلاح: await للدالة async
      if (!mounted || !context.mounted) return;
      if (success) {
        _showSnackBar(
          context,
          'تم إضافة ${product.name} للسلة',
          AppColors.primary,
        );
      } else {
        _showSnackBar(context, 'فشل في إضافة المنتج للسلة', Colors.red);
      }
    } catch (e) {
      if (!mounted || !context.mounted) return;
      _showSnackBar(
        context,
        'تعذر إضافة الطبق الآن. أعد المحاولة.',
        Colors.red,
      );
    }
  }
}
