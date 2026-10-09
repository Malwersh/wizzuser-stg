import 'dart:developer' as developer;
// lib/screens/dish_detail_screen.dart

import 'dart:ui' as ui;
// lib/screens/dish_detail_screen.dart
// lib/screens/dish_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/dish.dart';
import '../models/favorites_model.dart';
import '../models/product_model.dart';
import '../services/business_service.dart';
import '../services/restaurant_availability_service.dart';
import '../providers/app_state_provider.dart';
import '../widgets/modern_cart_icon.dart';
// import '../widgets/product_image.dart';  // استبدال مؤقت
import 'cart_screen.dart';

class DishDetailScreen extends StatefulWidget {
  final Dish dish;
  final String storeId;
  final String? storeName; // إضافة اسم المتجر
  final String? storeAddress; // إضافة عنوان المتجر للسائقين
  final bool isInitiallyFav;
  final ProductModel? productData; // إضافة بيانات المنتج الجاهزة

  const DishDetailScreen({
    super.key,
    required this.dish,
    required this.storeId,
    this.storeName, // إضافة اسم المتجر كمعطى اختياري
    this.storeAddress, // إضافة عنوان المتجر كمعطى اختياري
    this.isInitiallyFav = false,
    this.productData, // معطى اختياري
  });

  @override
  State<DishDetailScreen> createState() => _DishDetailScreenState();
}

class _DishDetailScreenState extends State<DishDetailScreen>
    with SingleTickerProviderStateMixin {
  static const _primaryPink = AppColors.primary;

  late TabController _tabController;
  final Map<String, Set<String>> _selectedOptions = {};
  int _quantity = 1;
  String? _specialInstructions;
  final _arabicNumber = NumberFormat.decimalPattern('ar');

  // بيانات حقيقية من الباك إند
  ProductModel? _productData;
  bool _isLoadingProduct = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    for (var g in widget.dish.optionGroups) {
      _selectedOptions[g.id] = <String>{};
    }
    
    // استخدام البيانات الممررة إذا كانت متوفرة، وإلا جلبها من API
    developer.log('🔍 DishDetailScreen.initState:');
    developer.log('  widget.productData != null: ${widget.productData != null}');
    if (widget.productData != null) {
      developer.log('  widget.productData.name: "${widget.productData!.name}"');
      developer.log('  widget.productData.imageUrl: "${widget.productData!.imageUrl}"');
      developer.log('  widget.productData.imageUrl.isNotEmpty: ${widget.productData!.imageUrl.isNotEmpty}');
    }
    developer.log('  widget.dish.imageUrls: ${widget.dish.imageUrls}');
    
    if (widget.productData != null) {
      developer.log('✅ استخدام بيانات المنتج الممررة مباشرة');
      _productData = widget.productData;
    } else {
      developer.log('🔄 جلب تفاصيل المنتج من API');
      _loadProductDetails();
    }
  }

  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoadingProduct = true;
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
        developer.log('  productData.imageUrl.isEmpty: ${productData.imageUrl.isEmpty}');
      }
      
      if (mounted) {
        setState(() {
          _productData = productData;
          _isLoadingProduct = false;
        });
      }
    } catch (e) {
      developer.log('❌ خطأ في جلب تفاصيل المنتج: $e');
      if (mounted) {
        setState(() {
          _isLoadingProduct = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      developer.log('  استخدام صورة من _productData: "${_productData!.imageUrl}"');
      return _productData!.imageUrl;
    }
    
    final fallbackImage = widget.dish.imageUrls.isNotEmpty ? widget.dish.imageUrls.first : '';
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
      final group = widget.dish.optionGroups.firstWhere((g) => g.id == gid);
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

  void _showDifferentStoreDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // أيقونة سلة مع علامة إلغاء
              Stack(alignment: Alignment.center, children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                ),
                ModernCartIcon(
                  color: AppColors.primaryDark,
                  size: 32,
                  isGlassmorphic: false,
                ),
                const Positioned(
                  right: 0, top: 0,
                  child: Icon(Icons.close, size: 20, color: Colors.redAccent),
                ),
              ]),
              const SizedBox(height: 16),
              const Text(
                'لا يمكن إضافة الطلب إلى السلة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'سلة التسوق تحتوي طلبات من متجر آخر.\n'
                'هل تريد تفريغ السلة والبدء من المتجر الحالي أم عرض السلة الحالية؟',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      developer.log('🗑️ تفريغ السلة وإضافة المنتج الجديد');
                      
                      final appState = Provider.of<AppStateProvider>(dialogContext, listen: false);
                      appState.clearCart();
                      
                      // إضافة العنصر للسلة باستخدام AppStateProvider مع تجاهل فحص المطعم
                      final cartItem = {
                        'id': widget.dish.id,
                        'name': _productName.isNotEmpty ? _productName : 'منتج غير محدد',
                        'price': _calculateTotal(),
                        'description': _productDescription.isNotEmpty ? _productDescription : 'وصف غير متوفر',
                        'image': _productImageUrl,
                        'quantity': _quantity > 0 ? _quantity : 1,
                        'store_id': widget.storeId,
                        'store_name': _getStoreName(),
                        'store_address': widget.storeAddress ?? 'العنوان غير محدد', // عنوان المطعم للسائقين
                        'special_instructions': _specialInstructions?.trim(),
                        'base_price': _productPrice, // إضافة السعر الأساسي
                        'selected_options': _selectedOptions.map((k, v) => MapEntry(k, v.toList())), // الخيارات المختارة
                        'added_at': DateTime.now().toIso8601String(), // وقت الإضافة
                      };
                      
                      developer.log('🛒 إضافة منتج للسلة (من dialog المتجر المختلف)');
                      developer.log('  التعليمات الخاصة: "${_specialInstructions ?? 'لا توجد ملاحظات'}"');
                      
                      final navigator = Navigator.of(dialogContext);
                      await appState.addToCart(cartItem);
                      navigator.pop(); // يغلق الـ Dialog فقط
                      
                      if (mounted) {
                        final favoritesModel = Provider.of<FavoritesModel>(context, listen: false);
                        Navigator.pop(context, favoritesModel.isDishFavorite(widget.dish.id)); // يغلق شاشة الطبق
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryPink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('تفريغ السلة', style: TextStyle(color: AppColors.secondary)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext); // يغلق الـ Dialog فقط
                      if (mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CartScreen(
                              storeId: widget.storeId,
                              stores: null, // لا توجد قائمة متاجر هنا، سيظهر الاسم الافتراضي إذا لم يتم تمريره
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryPink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('عرض السلة', style: TextStyle(color: AppColors.secondary)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.white,
        body: _isLoadingProduct
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('جاري تحميل تفاصيل المنتج...'),
                  ],
                ),
              )
            : ListView(
          padding: EdgeInsets.zero,
          children: [
            // صورة الغلاف مع أزرار الخروج والتفضيل
            Stack(
              children: [
                SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: Builder(
                    builder: (context) {
                      // إضافة logging مفصل
                      final imageUrl = _productImageUrl;
                      developer.log('🖼️ بناء صورة الطبق:');
                      developer.log('  imageUrl: "$imageUrl"');
                      developer.log('  imageUrl.isNotEmpty: ${imageUrl.isNotEmpty}');
                      developer.log('  imageUrl.length: ${imageUrl.length}');
                      
                      return imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              height: 240,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) {
                                  developer.log('✅ تم تحميل صورة الطبق بنجاح');
                                  return child;
                                }
                                developer.log('📥 جاري تحميل صورة الطبق...');
                                return Container(
                                  height: 240,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(_primaryPink),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                developer.log('❌ خطأ في تحميل صورة الطبق: $error');
                                developer.log('❌ Stack trace: $stackTrace');
                                return Container(
                                  height: 240,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.grey[300]!,
                                        Colors.grey[200]!,
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.fastfood,
                                      size: 60,
                                      color: Colors.grey,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              height: 240,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.grey[300]!,
                                    Colors.grey[200]!,
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.fastfood,
                                  size: 60,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                    },
                  ),
                ),
                Positioned(
                  top: 40, right: 16,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: AppColors.secondary),
                      onPressed: () {
                        developer.log('❌ إغلاق شاشة تفاصيل الطبق (زر X)');
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
                // زر القلب تم إخفاؤه
                // Positioned(
                //   top: 24, left: 16,
                //   child: Consumer<FavoritesModel>(
                //     builder: (context, favoritesModel, child) {
                //       final isFavorite = favoritesModel.isDishFavorite(widget.dish.id);
                //       return CircleAvatar(
                //         backgroundColor: Colors.white,
                //         child: IconButton(
                //           icon: Icon(
                //             isFavorite ? Icons.favorite : Icons.favorite_border, 
                //             color: _primaryPink
                //           ),
                //           onPressed: () {
                //             if (isFavorite) {
                //               favoritesModel.removeDishFavorite(widget.dish.id);
                //             } else {
                //               favoritesModel.addDishFavorite(widget.dish.id);
                //             }
                //           },
                //         ),
                //       );
                //     },
                //   ),
                // ),
              ],
            ),
            const SizedBox(height: 16),
            // اسم الطبق
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _productName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            // وصف الطبق
            if (_productDescription.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  _productDescription,
                  style: const TextStyle(fontSize: 15, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 12),
            // التحكم في الكمية
            _buildQuantitySelector(),
            const SizedBox(height: 16),
            // الخيارات (نفس منطقك القديم)
            for (var g in widget.dish.optionGroups) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  '${g.title} • ${g.required ? "مطلوب" : "اختياري"} • '
                  '${g.required ? "اختر 1" : "حتى ${_arabicNumber.format(g.maxSelections)}"}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              for (var o in g.options)
                g.required
                    ? RadioListTile<String>(
                        title: Text(
                          '${o.name}${o.extraPrice != 0 ? " (+${_arabicNumber.format(o.extraPrice)})" : ""}',
                        ),
                        value: o.id,
                        groupValue: _selectedOptions[g.id]!.isEmpty
                            ? null
                            : _selectedOptions[g.id]!.first,
                        onChanged: (id) => setState(() => _selectedOptions[g.id] = {id!}),
                      )
                    : CheckboxListTile(
                        title: Text(
                          '${o.name}${o.extraPrice != 0 ? " (+${_arabicNumber.format(o.extraPrice)})" : ""}',
                        ),
                        value: _selectedOptions[g.id]!.contains(o.id),
                        onChanged: (chk) => setState(() {
                          if (chk! && _selectedOptions[g.id]!.length < g.maxSelections) {
                            _selectedOptions[g.id]!.add(o.id);
                          } else {
                            _selectedOptions[g.id]!.remove(o.id);
                          }
                        }),
                      ),
            ],
            // تعليمات خاصة
            ListTile(
              title: Text(_specialInstructions?.isNotEmpty == true 
                  ? 'تعليمات خاصة' 
                  : 'إضافة تعليمات خاصة'),
              subtitle: _specialInstructions?.isNotEmpty == true 
                  ? Text(
                      _specialInstructions!,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final txt = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) {
                    final ctrl = TextEditingController(text: _specialInstructions);
                    return Directionality(
                      textDirection: ui.TextDirection.rtl,
                      child: Container(
                        margin: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Row(
                                children: [
                                  const Icon(Icons.note_add, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'تعليمات خاصة',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_specialInstructions?.isNotEmpty == true)
                                    TextButton(
                                      onPressed: () {
                                        ctrl.clear();
                                        Navigator.pop(context, '');
                                      },
                                      child: const Text(
                                        'مسح',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              // Text field
                              TextField(
                                controller: ctrl,
                                maxLines: 4,
                                textDirection: ui.TextDirection.rtl,
                                decoration: InputDecoration(
                                  labelText: 'اكتب ملاحظاتك هنا...',
                                  hintText: 'مثال: بدون بصل، إضافة صوص، طبخ جيد، إلخ',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              
                              // Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(context, null),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text('إلغاء'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () {
                                        developer.log('💾 حفظ الملاحظات: "${ctrl.text.trim()}"');
                                        Navigator.pop(context, ctrl.text.trim());
                                      },
                                      child: const Text(
                                        'حفظ', 
                                        style: TextStyle(color: AppColors.secondary),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
                if (txt != null) {
                  setState(() {
                    _specialInstructions = txt.isNotEmpty ? txt : null;
                  });
                  developer.log('📝 تم حفظ الملاحظات: "${_specialInstructions ?? 'فارغة'}"');
                }
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryPink,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                // أولاً: فحص توفر المطعم وحالة قبول الطلبات
                developer.log('🔍 فحص توفر المطعم قبل إضافة المنتج للسلة');
                developer.log('  storeId: ${widget.storeId}');
                
                final availabilityService = RestaurantAvailabilityService.instance;
                final availabilityStatus = await availabilityService.checkRestaurantAvailability(
                  widget.storeId,
                  skipCache: true, // فحص حالي للحصول على أحدث البيانات
                );
                
                developer.log('📊 نتيجة فحص توفر المطعم:');
                developer.log('  isAvailable: ${availabilityStatus.isAvailable}');
                developer.log('  acceptingOrders: ${availabilityStatus.acceptingOrders}');
                developer.log('  isWithinWorkingHours: ${availabilityStatus.isWithinWorkingHours}');
                developer.log('  reasonUnavailable: ${availabilityStatus.reasonUnavailable}');
                
                // إذا كان المطعم غير متاح، أظهر رسالة مناسبة
                if (!availabilityStatus.isAvailable) {
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  String errorMessage;
                  
                  if (!availabilityStatus.acceptingOrders) {
                    errorMessage = 'عذراً، هذا المطعم لا يستقبل طلبات جديدة حالياً';
                  } else if (!availabilityStatus.isWithinWorkingHours) {
                    errorMessage = 'عذراً، هذا المطعم مغلق حالياً';
                  } else {
                    errorMessage = availabilityStatus.reasonUnavailable ?? 'عذراً، هذا المطعم غير متاح حالياً';
                  }
                  
                  developer.log('⚠️ المطعم غير متاح: $errorMessage');
                  
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.white),
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
                developer.log('  التعليمات الخاصة: "${_specialInstructions ?? 'لا توجد ملاحظات'}"');
                developer.log('  طول الملاحظات: ${_specialInstructions?.length ?? 0} حرف');
                
                // إنشاء عنصر السلة مع التأكد من صحة جميع البيانات
                final cartItem = {
                  'id': widget.dish.id,
                  'name': _productName.isNotEmpty ? _productName : 'منتج غير محدد',
                  'price': _calculateTotal(),
                  'description': _productDescription.isNotEmpty ? _productDescription : 'وصف غير متوفر',
                  'image': _productImageUrl,
                  'quantity': _quantity > 0 ? _quantity : 1,
                  'store_id': widget.storeId,
                  'store_name': _getStoreName(),
                  'store_address': widget.storeAddress ?? 'العنوان غير محدد', // عنوان المطعم للسائقين
                  'special_instructions': _specialInstructions?.trim(),
                  'base_price': _productPrice, // إضافة السعر الأساسي
                  'selected_options': _selectedOptions.map((k, v) => MapEntry(k, v.toList())), // الخيارات المختارة
                  'added_at': DateTime.now().toIso8601String(), // وقت الإضافة
                };
                
                // محاولة إضافة العنصر للسلة
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final favoritesModel = Provider.of<FavoritesModel>(context, listen: false);
                final navigator = Navigator.of(context);
                await appState.addToCart(cartItem);
                
                // التحقق من نوع الخطأ
                if (appState.errorMessage == 'DIFFERENT_STORE') {
                  // إظهار dialog المطعم المختلف
                  developer.log('⚠️ مطعم مختلف، إظهار dialog');
                  appState.clearError(); // مسح الخطأ
                  _showDifferentStoreDialog();
                  return;
                } else if (appState.errorMessage != null) {                  // خطأ آخر
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
                  developer.log('🔙 العودة لشاشة تفاصيل المطعم مع حالة المفضلة: ${favoritesModel.isDishFavorite(widget.dish.id)}');
                  navigator.pop(favoritesModel.isDishFavorite(widget.dish.id));
                }
              },
              child: Text(
                'إضافة إلى الطلب • ${_calculateTotal().toStringAsFixed(2)} ر.س',
                style: const TextStyle(fontSize: 18, color: AppColors.secondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuantitySelector() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () {
              if (_quantity > 1) setState(() => _quantity--);
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
              child: const Center(child: Text('−', style: TextStyle(fontSize: 20))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_arabicNumber.format(_quantity),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          GestureDetector(
            onTap: () => setState(() => _quantity++),
            child: Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(color: _primaryPink, shape: BoxShape.circle),
              child: const Center(child: Icon(Icons.add, color: AppColors.secondary)),
            ),
          ),
        ]),
      ),
    );
  }
}
