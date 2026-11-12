import '../widgets/basket_saving_celebration.dart';
import '../widgets/cart_suggestion_card.dart';
import '../models/dish.dart';
import 'dish_detail_screen.dart';
import 'home_screen.dart';
import '../widgets/empty_basket_view.dart';
import '../services/session_service.dart';
import '../services/point_invoice_321.dart';
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
        final pointRequest = PointInvoice321.basketRequest(
          branch,
          items,
          storeName: _resolveStoreName() ?? 'المطعم',
        );
        final pointPrepared =
            pointRequest == null
                ? null
                : PointInvoice321.instance.peek(pointRequest);
        final prepared =
            invoiceRequest == null
                ? null
                : CheckoutInvoiceStore.instance.peek(invoiceRequest);
        if (scope != null &&
            prepared == null &&
            pointPrepared == null &&
            !(pointRequest != null && SessionService.instance.isLoggedIn)) {
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
        // Join the same request already started while editing the basket.
        // Never open checkout with an unchanged basket's known failed invoice.
        if (pointRequest != null && SessionService.instance.isLoggedIn) {
          await PointInvoice321.instance.ensure(pointRequest, retry: true);
          if (!mounted) return;
          final latest = PointInvoice321.basketRequest(
            _branch(state),
            state.cartItems,
            storeName: _resolveStoreName() ?? 'المطعم',
          );
          if (branch != _branch(state) ||
              fingerprint != jsonEncode(state.cartItems) ||
              latest == null ||
              PointInvoice321.instance.key(latest) !=
                  PointInvoice321.instance.key(pointRequest))
            continue;
          if (PointInvoice321.instance.peek(latest) == null) {
            setState(
              () =>
                  _continueError =
                      PointInvoice321.instance.error(latest) ??
                      'تعذر تجهيز إجمالي الطلب حاليًا. أعد المحاولة.',
            );
            return;
          }
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

  Widget _buildEmptyCart(BuildContext context) => EmptyBasketView(
    onBrowse:
        () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        ),
  );

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
                BasketSavingCelebration(
                  branch: _branch(appState),
                  items: appState.cartItems,
                ),
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

    final businessData = appState.getBusinessSuggestionData(currentStoreId);
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
            appState.cartItems
                .map(
                  (item) =>
                      item['productId'] ??
                      item['product_id'] ??
                      item['id'] ??
                      '',
                )
                .toSet();
        final availableSuggestions =
            suggestions
                .where(
                  (product) =>
                      product.businessId == currentStoreId &&
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
                      color: AppColors.secondaryDark,
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
                          businessData == null
                              ? 'من المطعم نفسه'
                              : 'من ${businessData.businessName}',
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

      // Prefer complementary categories, then other published branch products.
      // Menu names must not prevent a branch from having recommendations.
      final seenIds = suggestions.map((p) => p.id).toSet();
      for (final product in categoryProducts.values.expand((items) => items)) {
        if (seenIds.add(product.id)) suggestions.add(product);
      }

      return suggestions;
    } catch (e) {
      return [];
    }
  }

  // زر إضافة المزيد من الأطباق
  Widget _buildAddMoreDishesButton(BuildContext context) => TextButton.icon(
    onPressed: () => _navigateBackToStore(context),
    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
    label: const Text('أضف المزيد من المطعم'),
    style: TextButton.styleFrom(
      foregroundColor: AppColors.secondary,
      backgroundColor: const Color(0xffeaf0f8),
      minimumSize: const Size.fromHeight(46),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffe3eaf2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xffeaf0f8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: AppColors.secondary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'ملخص السلة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryDark,
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
                'الأصناف · $totalDishes قطعة',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.secondaryDark,
                ),
              ),
              Text(
                basketMoney(subtotal),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryDark,
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
                style: TextStyle(fontSize: 15, color: AppColors.secondaryDark),
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
                      color: AppColors.secondaryDark,
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
          const SizedBox(height: 12),
          const Text(
            'السعر يتحدّث تلقائيًا عند تعديل طلبك.',
            style: TextStyle(
              fontSize: 12,
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
                    _continuing || below
                        ? null
                        : () => _continueCheckout(appState),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondaryDark,
                  disabledBackgroundColor: const Color(0xFFE4E7EC),
                  disabledForegroundColor: const Color(0xFF667085),
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
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
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
                  const SizedBox(height: 16),
                  // أيقونة التحذير
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6DA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 24,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // عنوان التأكيد
                  const Text(
                    'حذف الطبق',
                    style: TextStyle(
                      fontSize: 18,
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
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // أزرار التأكيد والإلغاء
                  Row(
                    children: [
                      // زر الإلغاء
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            foregroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(
                              fontSize: 14,
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
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.secondaryDark,
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
                              'تم حذف ${item['name'] ?? 'الطبق'} من السلة',
                              AppColors.secondaryDark,
                            );
                          },
                          child: const Text(
                            'حذف الطبق',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
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
    return CartSuggestionCard(
      product: product,
      onOpen:
          () => showDishDetailBottomSheet(
            context,
            storeId: _branch(appState),
            storeName: _resolveStoreName(),
            productData: product,
            dish: Dish(
              id: product.id,
              name: product.name,
              imageUrls: [product.imageUrl],
              description: product.description,
              likesPercent: 0,
              likesCount: 0,
              basePrice: product.price,
              optionGroups: product.optionGroups ?? [],
            ),
          ),
    );
  }
}
