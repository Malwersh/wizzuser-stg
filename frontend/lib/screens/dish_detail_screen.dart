import '../utils/currency_format.dart';
import 'dart:developer' as developer;
// lib/screens/dish_detail_screen.dart

import 'dart:ui' as ui;
// lib/screens/dish_detail_screen.dart
// lib/screens/dish_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/discovery/customer_components.dart';
import '../models/dish.dart';
import '../models/favorites_model.dart';
import '../models/product_model.dart';
import '../services/business_service.dart';
import '../services/restaurant_availability_service.dart';
import '../providers/app_state_provider.dart';
import '../widgets/clear_cart_sheet.dart';

Future<bool?> showDishDetailBottomSheet(
  BuildContext context, {
  required Dish dish,
  required String storeId,
  String? storeName,
  String? storeAddress,
  bool isInitiallyFav = false,
  ProductModel? productData,
}) {
  final mediaQuery = MediaQuery.of(context);
  final availableHeight = mediaQuery.size.height - mediaQuery.padding.top;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder:
        (sheetContext) => SizedBox(
          height: availableHeight * 0.94,
          child: MediaQuery.removePadding(
            context: sheetContext,
            removeTop: true,
            child: DishDetailScreen(
              dish: dish,
              storeId: storeId,
              storeName: storeName,
              storeAddress: storeAddress,
              isInitiallyFav: isInitiallyFav,
              productData: productData,
              isBottomSheet: true,
            ),
          ),
        ),
  );
}

class DishDetailScreen extends StatefulWidget {
  final Dish dish;
  final String storeId;
  final String? storeName; // إضافة اسم المتجر
  final String? storeAddress; // إضافة عنوان المتجر للسائقين
  final bool isInitiallyFav;
  final ProductModel? productData; // إضافة بيانات المنتج الجاهزة
  final bool isBottomSheet;

  const DishDetailScreen({
    super.key,
    required this.dish,
    required this.storeId,
    this.storeName, // إضافة اسم المتجر كمعطى اختياري
    this.storeAddress, // إضافة عنوان المتجر كمعطى اختياري
    this.isInitiallyFav = false,
    this.productData, // معطى اختياري
    this.isBottomSheet = false,
  });

  @override
  State<DishDetailScreen> createState() => _DishDetailScreenState();
}

class _DishDetailScreenState extends State<DishDetailScreen> {
  final Map<String, Set<String>> _selectedOptions = {};
  int _quantity = 1;
  String? _specialInstructions;

  // بيانات حقيقية من الباك إند
  ProductModel? _productData;
  bool _isLoadingProduct = false;
  bool _productLoadFailed = false;
  bool _addingToCart = false;

  @override
  void initState() {
    super.initState();

    // استخدام البيانات الممررة إذا كانت متوفرة، وإلا جلبها من API
    developer.log('🔍 DishDetailScreen.initState:');
    developer.log(
      '  widget.productData != null: ${widget.productData != null}',
    );
    if (widget.productData != null) {
      developer.log('  widget.productData.name: "${widget.productData!.name}"');
      developer.log(
        '  widget.productData.imageUrl: "${widget.productData!.imageUrl}"',
      );
      developer.log(
        '  widget.productData.imageUrl.isNotEmpty: ${widget.productData!.imageUrl.isNotEmpty}',
      );
    }
    developer.log('  widget.dish.imageUrls: ${widget.dish.imageUrls}');

    if (widget.productData != null) {
      developer.log('✅ استخدام بيانات المنتج الممررة مباشرة');
      _productData = widget.productData;
    } else {
      developer.log('🔄 جلب تفاصيل المنتج من API');
      _loadProductDetails();
    }

    _ensureOptionKeys();
  }

  /// 🔥 مجموعات الخيارات الفعّالة: الخيارات المضمنة في Dish أولاً،
  /// وإلا تُشتق من بيانات الإضافات/المتغيرات الخام القادمة من الباك إند
  List<OptionGroup> get _optionGroups {
    if (_productData?.optionGroups != null) return _productData!.optionGroups!;
    if (widget.dish.optionGroups.isNotEmpty) return widget.dish.optionGroups;
    return OptionGroup.listFromAddons(
      _productData?.addons ?? _productData?.variations,
    );
  }

  OptionGroup? _groupById(String id) {
    for (final g in _optionGroups) {
      if (g.id == id) return g;
    }
    return null;
  }

  void _ensureOptionKeys() {
    final groups = _optionGroups;
    _selectedOptions.removeWhere((id, _) => !groups.any((g) => g.id == id));
    for (final g in groups) {
      final ids = _selectedOptions.putIfAbsent(g.id, () => <String>{});
      ids.removeWhere(
        (id) => !g.options.any((o) => o.id == id && o.isAvailable),
      );
      if (ids.length > g.maxSelections) ids.clear();
    }
  }

  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoadingProduct = true;
      _productLoadFailed = false;
    });

    try {
      developer.log('🔄 جاري جلب تفاصيل المنتج...');
      developer.log('  storeId: "${widget.storeId}"');
      developer.log('  dishId: "${widget.dish.id}"');

      final productData = await BusinessService.getProductDetails(
        widget.storeId,
        widget.dish.id,
      );

      developer.log('📦 نتيجة جلب تفاصيل المنتج:');
      developer.log('  productData: ${productData != null ? "موجود" : "null"}');
      if (productData != null) {
        developer.log('  productData.name: "${productData.name}"');
        developer.log('  productData.imageUrl: "${productData.imageUrl}"');
        developer.log(
          '  productData.imageUrl.isEmpty: ${productData.imageUrl.isEmpty}',
        );
      }

      if (mounted) {
        setState(() {
          _productData = productData;
          _productLoadFailed = productData == null;
          _isLoadingProduct = false;
        });
        // إذا وصلت مجموعات خيارات جديدة من الباك إند، تهيئة مفاتيحها
        _ensureOptionKeys();
      }
    } catch (e) {
      developer.log('❌ خطأ في جلب تفاصيل المنتج: $e');
      _productLoadFailed = true;
      if (mounted) {
        setState(() {
          _isLoadingProduct = false;
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // دالة مساعدة للحصول على اسم المنتج
  String get _productName {
    return _productData?.name ?? widget.dish.name;
  }

  // دالة مساعدة للحصول على وصف المنتج
  String get _productDescription {
    return _productData?.description ?? widget.dish.description;
  }

  // دالة مساعدة للحصول على صورة المنتج
  String get _productImageUrl {
    developer.log('🔍 Debug _productImageUrl:');
    developer.log('  _productData: ${_productData != null ? "موجود" : "null"}');

    if (_productData?.imageUrl.isNotEmpty == true) {
      developer.log(
        '  استخدام صورة من _productData: "${_productData!.imageUrl}"',
      );
      return _productData!.imageUrl;
    }

    final fallbackImage =
        widget.dish.imageUrls.isNotEmpty ? widget.dish.imageUrls.first : '';
    developer.log('  استخدام صورة احتياطية من dish: "$fallbackImage"');
    developer.log('  widget.dish.imageUrls: ${widget.dish.imageUrls}');

    return fallbackImage;
  }

  // دالة مساعدة للحصول على سعر المنتج
  double get _productPrice {
    return _productData?.price ?? widget.dish.basePrice;
  }

  double _calculateTotal() {
    var total = _productPrice;
    _selectedOptions.forEach((gid, opts) {
      final group = _groupById(gid);
      if (group == null) return;
      for (var o in group.options.where((o) => opts.contains(o.id))) {
        total += o.extraPrice;
      }
    });
    return total * _quantity;
  }

  // دالة للحصول على اسم المتجر الحقيقي
  String _getStoreName() {
    // 1. إذا تم تمرير اسم المتجر مباشرة واسمه ليس عام
    if (widget.storeName != null &&
        widget.storeName!.isNotEmpty &&
        widget.storeName != 'المطعم' &&
        widget.storeName != 'متجر') {
      return widget.storeName!;
    }

    final appState = Provider.of<AppStateProvider>(context, listen: false);

    // 2. إذا كان في السلة عناصر من نفس المتجر، استخرج اسم المتجر
    if (appState.cartItems.isNotEmpty) {
      final storeIdInCart = appState.cartItems.first['store_id'] as String?;
      if (storeIdInCart == widget.storeId) {
        final storeName = appState.cartItems.first['store_name'] as String?;
        if (storeName != null &&
            storeName.isNotEmpty &&
            storeName != 'المطعم' &&
            storeName != 'متجر') {
          return storeName;
        }
      }
    }

    // 3. محاولة تخمين اسم معقول من storeId إذا أمكن
    if (widget.storeId.isNotEmpty) {
      // إذا كان ID يحتوي على نص مفيد، استخدمه
      if (widget.storeId.length > 10) {
        return 'مطعم ${widget.storeId.substring(0, 8)}...';
      }
    }

    // الافتراضي الآمن
    return widget.storeName ?? 'المطعم';
  }

  /// بناء عنصر السلة الموحد (يُستخدم في زر الإضافة وفي نافذة تعارض المطاعم)
  Map<String, dynamic> _buildCartItemMap() {
    return {
      'id': widget.dish.id,
      'name': _productName.isNotEmpty ? _productName : 'منتج غير محدد',
      'price': _calculateTotal() / _quantity,
      'description':
          _productDescription.isNotEmpty
              ? _productDescription
              : 'وصف غير متوفر',
      'image': _productImageUrl,
      'quantity': _quantity > 0 ? _quantity : 1,
      'store_id': widget.storeId,
      'store_name': _getStoreName(),
      'store_address':
          widget.storeAddress ?? 'العنوان غير محدد', // عنوان المطعم للسائقين
      'special_instructions': _specialInstructions?.trim(),
      'base_price': _calculateTotal() / _quantity, // إضافة السعر الأساسي
      'selected_options': _selectedOptions.map(
        (k, v) => MapEntry(k, v.toList()),
      ), // الخيارات المختارة
      'added_at': DateTime.now().toIso8601String(), // وقت الإضافة
    };
  }

  /// 🔥 عرض نافذة تعارض المطاعم (سلة واحدة لكل مطعم) ومعالجة اختيار المستخدم
  Future<void> _showDifferentStoreDialog() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final otherStoreName = appState.cartStoreName ?? 'مطعم آخر';

    final clearAndAdd = await showClearCartConflictSheet(
      context,
      otherStoreName: otherStoreName,
    );

    if (clearAndAdd != true || !mounted) return;

    developer.log('🗑️ تفريغ السلة وإضافة المنتج الجديد');

    // تفريغ السلة ثم إضافة العنصر الجديد
    appState.clearCart();
    await appState.addToCart(_buildCartItemMap());

    if (!mounted) return;
    final favoritesModel = Provider.of<FavoritesModel>(context, listen: false);
    Navigator.pop(
      context,
      favoritesModel.isDishFavorite(widget.dish.id),
    ); // يغلق شاشة الطبق
  }

  bool get _choicesComplete => _optionGroups.every((g) {
    final ids = _selectedOptions[g.id] ?? <String>{};
    return (!g.required || ids.isNotEmpty) &&
        ids.length <= g.maxSelections &&
        ids.every((id) => g.options.any((o) => o.id == id && o.isAvailable));
  });
  String? get _choiceHint {
    if (_isLoadingProduct) return 'جارٍ تحميل خيارات الوجبة…';
    if (_productLoadFailed) return 'تعذر تحميل تفاصيل الوجبة؛ أعد المحاولة';
    if (_productData?.isAvailable == false)
      return 'هذا المنتج غير متوفر حاليًا';
    for (final g in _optionGroups) {
      if (g.required && (_selectedOptions[g.id]?.isEmpty ?? true))
        return 'اختر ${g.title} لإكمال وجبتك';
    }
    return null;
  }

  Future<void> _editInstructions() async {
    var draft = _specialInstructions ?? '';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder:
          (sheet) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(sheet).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ملاحظات للمطعم',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: discoveryInk,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اكتب ملاحظات التحضير؛ اختيار الأحجام والإضافات يكون من الخيارات أعلاه.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF647184)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: draft,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (value) => draft = value,
                  decoration: const InputDecoration(
                    hintText: 'مثال: بدون بصل',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: discoveryGold,
                      foregroundColor: discoveryInk,
                    ),
                    onPressed: () => Navigator.pop(sheet, draft.trim()),
                    child: const Text('حفظ الملاحظة'),
                  ),
                ),
              ],
            ),
          ),
    );
    if (mounted && result != null)
      setState(() => _specialInstructions = result);
  }

  Future<void> _submitDish() async {
    if (_addingToCart ||
        !_choicesComplete ||
        _isLoadingProduct ||
        _productLoadFailed ||
        _productData?.isAvailable == false)
      return;
    setState(() => _addingToCart = true);
    try {
      // أولاً: فحص توفر المطعم وحالة قبول الطلبات
      developer.log('🔍 فحص توفر المطعم قبل إضافة المنتج للسلة');
      developer.log('  storeId: ${widget.storeId}');

      final availabilityService = RestaurantAvailabilityService.instance;
      final availabilityStatus = await availabilityService
          .checkRestaurantAvailability(
            widget.storeId,
            skipCache: true, // فحص حالي للحصول على أحدث البيانات
          );

      if (!mounted) return;
      developer.log('📊 نتيجة فحص توفر المطعم:');
      developer.log('  isAvailable: ${availabilityStatus.isAvailable}');
      developer.log('  acceptingOrders: ${availabilityStatus.acceptingOrders}');
      developer.log(
        '  isWithinWorkingHours: ${availabilityStatus.isWithinWorkingHours}',
      );
      developer.log(
        '  reasonUnavailable: ${availabilityStatus.reasonUnavailable}',
      );

      // إذا كان المطعم غير متاح، أظهر رسالة مناسبة
      if (!availabilityStatus.isAvailable) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
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

        developer.log('⚠️ المطعم غير متاح: $errorMessage');

        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: const Color(0xFF00296B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(errorMessage)),
                ],
              ),
              backgroundColor: Colors.orange.shade600,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'حسناً',
                textColor: Colors.white,
                onPressed: () {
                  scaffoldMessenger.hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
        return; // توقف هنا ولا تضيف للسلة
      }

      // إذا كان المطعم متاحاً، تابع عملية إضافة المنتج للسلة
      developer.log('✅ المطعم متاح، المتابعة لإضافة المنتج للسلة');

      final appState = Provider.of<AppStateProvider>(context, listen: false);

      developer.log('🛒 محاولة إضافة منتج للسلة');
      developer.log('  المنتج: $_productName');
      developer.log('  الوصف: $_productDescription');
      developer.log('  الصورة: $_productImageUrl');
      developer.log('  السعر الأساسي: $_productPrice');
      developer.log('  السعر الإجمالي: ${_calculateTotal()}');
      developer.log('  الكمية: $_quantity');
      developer.log('  المطعم: ${widget.storeId}');
      developer.log(
        '  التعليمات الخاصة: "${_specialInstructions ?? 'لا توجد ملاحظات'}"',
      );
      developer.log(
        '  طول الملاحظات: ${_specialInstructions?.length ?? 0} حرف',
      );

      // إنشاء عنصر السلة مع التأكد من صحة جميع البيانات
      final cartItem = _buildCartItemMap();

      // محاولة إضافة العنصر للسلة
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final favoritesModel = Provider.of<FavoritesModel>(
        context,
        listen: false,
      );
      final navigator = Navigator.of(context);
      await appState.addToCart(cartItem);

      // التحقق من نوع الخطأ
      if (appState.errorMessage == 'DIFFERENT_STORE') {
        // إظهار dialog المطعم المختلف
        developer.log('⚠️ مطعم مختلف، إظهار dialog');
        appState.clearError(); // مسح الخطأ
        _showDifferentStoreDialog();
        return;
      } else if (appState.errorMessage != null) {
        // خطأ آخر
        developer.log('❌ خطأ في إضافة المنتج: ${appState.errorMessage}');
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(appState.errorMessage!),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // نجحت العملية - العودة للشاشة السابقة
      developer.log('✅ تم إضافة المنتج للسلة بنجاح');
      if (mounted) {
        // العودة للشاشة السابقة مع حالة المفضلة
        developer.log(
          '🔙 العودة لشاشة تفاصيل المطعم مع حالة المفضلة: ${favoritesModel.isDishFavorite(widget.dish.id)}',
        );
        navigator.pop(favoritesModel.isDishFavorite(widget.dish.id));
      }
    } finally {
      if (mounted) setState(() => _addingToCart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _productImageUrl;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: discoveryCanvas,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1.45,
                  child:
                      photo.isEmpty
                          ? const ColoredBox(
                            color: Color(0xFFE8EDF4),
                            child: Icon(
                              Icons.restaurant_rounded,
                              size: 64,
                              color: discoveryInk,
                            ),
                          )
                          : Image.network(
                            photo,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => const ColoredBox(
                                  color: Color(0xFFE8EDF4),
                                  child: Icon(
                                    Icons.restaurant_rounded,
                                    size: 64,
                                    color: discoveryInk,
                                  ),
                                ),
                          ),
                ),
                PositionedDirectional(
                  top:
                      widget.isBottomSheet
                          ? 16
                          : MediaQuery.paddingOf(context).top + 12,
                  start: 16,
                  child: IconButton(
                    tooltip: 'إغلاق',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: discoveryInk,
                      elevation: 2,
                      shadowColor: Colors.black12,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _productName,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: discoveryInk,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatIqd(_productPrice),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: discoveryInk,
                    ),
                  ),
                  if (_productDescription.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _productDescription,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF59687B),
                        height: 1.7,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoadingProduct)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(color: discoveryInk),
                      ),
                    ),
                  if (_productLoadFailed)
                    Center(
                      child: TextButton.icon(
                        onPressed: _loadProductDetails,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة تحميل التفاصيل'),
                      ),
                    ),
                  for (final group in _optionGroups)
                    MealChoiceGroup(
                      group: group,
                      selected: _selectedOptions[group.id] ?? {},
                      onChanged: (ids) {
                        if (_addingToCart) return;
                        setState(() => _selectedOptions[group.id] = ids);
                      },
                    ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: const Icon(
                        Icons.edit_note_rounded,
                        color: discoveryInk,
                      ),
                      title: const Text(
                        'ملاحظات للمطعم',
                        style: TextStyle(
                          color: discoveryInk,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        _specialInstructions?.isNotEmpty == true
                            ? _specialInstructions!
                            : 'اختياري · تعليمات التحضير فقط',
                        style: const TextStyle(
                          color: Color(0xFF647184),
                          fontSize: 13,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_left,
                        color: discoveryInk,
                      ),
                      onTap: _addingToCart ? null : _editInstructions,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: CustomerOrderActionBar(
          quantity: _quantity,
          total: _calculateTotal(),
          onQuantity: (q) => setState(() => _quantity = q),
          busy: _addingToCart,
          hint: _choiceHint,
          onAdd:
              _choicesComplete &&
                      !_isLoadingProduct &&
                      !_productLoadFailed &&
                      _productData?.isAvailable != false
                  ? _submitDish
                  : null,
        ),
      ),
    );
  }
}
