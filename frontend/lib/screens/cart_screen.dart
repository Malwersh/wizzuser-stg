import '../services/storefront_pricing.dart';
import '../widgets/storefront_value.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/store.dart';
import '../models/product_model.dart';
import '../models/business_suggestion_data.dart';
import '../services/restaurant_availability_service.dart';
import '../services/business_service.dart';
import '../screens/checkout_screen.dart';
import './store_detail_screen.dart';

class CartScreen extends StatefulWidget {
  final String? storeName;
  final String? storeId;
  final List<Store>? stores; // قائمة المتاجر للبحث عن اسم المطعم

  // إعدادات السلة

  const CartScreen({super.key, this.storeName, this.storeId, this.stores});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String? _resolveStoreName() {
    // قائمة الأسماء المرفوضة (الافتراضية/الخاطئة)
    final rejectedNames = ['متجر', 'المطعم', 'عربة التسوق'];

    // 1. فحص اسم المتجر الممرر، ولكن نتجاهل الأسماء المرفوضة
    if (widget.storeName != null &&
        widget.storeName!.isNotEmpty &&
        !rejectedNames.contains(widget.storeName)) {
      return widget.storeName;
    }

    // 2. محاولة البحث في قائمة المتاجر بناءً على storeId (حتى لو كان اسم المطعم في السلة غير صحيح)
    if (widget.storeId != null && widget.stores != null) {
      final found = widget.stores!.firstWhere(
        (s) => s.id == widget.storeId,
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
        backgroundColor: const Color(0xFFFAFAFA),
        body: Consumer<AppStateProvider>(
          builder: (context, appState, child) {
            if (appState.cartItems.isEmpty) {
              return _buildEmptyCart(context);
            }
            return _buildCartContent(context, appState);
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
                const SizedBox(height: 100), // مساحة للزر السفلي
              ],
            ),
          ),
          // زر المتابعة في الأسفل
          ListenableBuilder(
            listenable: StorefrontPricing.instance,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // الصف العلوي مع اسم الطبق وزر الحذف
          Row(
            children: [
              Expanded(
                child: Text(
                  item['name']?.toString() ?? 'طبق غير محدد',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // زر حذف الطبق في الجهة اليسرى العليا
              GestureDetector(
                onTap: () => _showDeleteConfirmation(context, appState, index),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // الصف السفلي مع تفاصيل الطبق
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // صورة الطبق
              GestureDetector(
                onTap: () {
                  // TODO: إصلاح التنقل إلى DishDetailScreen لاحقاً
                },
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[100],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Builder(
                      builder: (context) {
                        final imageUrl = item['image']?.toString() ?? '';

                        // إذا كان الرابط يبدأ بـ http أو https، استخدم Image.network
                        if (imageUrl.isNotEmpty &&
                            (imageUrl.startsWith('http://') ||
                                imageUrl.startsWith('https://'))) {
                          return Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: 64,
                            height: 64,
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
                                  size: 24,
                                ),
                              );
                            },
                          );
                        }

                        // إذا كان الرابط محلي أو فارغ، استخدم placeholder
                        return Container(
                          color: Colors.grey[200],
                          child: Icon(
                            Icons.fastfood,
                            color: Colors.grey[400],
                            size: 24,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // تفاصيل الطبق
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // وصف مختصر
                    if (item['description'] != null &&
                        item['description'].toString().isNotEmpty &&
                        item['description'].toString() != 'وصف غير متوفر')
                      Text(
                        item['description'].toString(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                    // عرض السعر الأساسي إذا كان مختلفاً عن السعر الإجمالي (في حالة وجود إضافات)
                    if (item['base_price'] != null &&
                        item['base_price'] != item['price'])
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'السعر الأساسي: ${(item['base_price'] as num).toStringAsFixed(2)} د.ع',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                    // عرض التعليمات الخاصة إذا كانت موجودة
                    if (item['special_instructions'] != null &&
                        item['special_instructions']
                            .toString()
                            .trim()
                            .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.note_alt_outlined,
                              size: 14,
                              color: AppColors.primaryDark,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'ملاحظة: ${item['special_instructions']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),
                    // التحكم بالكمية والسعر
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // أدوات التحكم بالكمية
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  final currentQuantity =
                                      (item['quantity'] as num?)?.toInt() ?? 1;
                                  if (currentQuantity > 1) {
                                    final itemId = item['id']?.toString() ?? '';
                                    final storeId =
                                        item['store_id']?.toString() ?? '';
                                    appState.updateCartItemQuantity(
                                      itemId,
                                      currentQuantity - 1,
                                      storeId,
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.remove,
                                    color: Colors.grey[700],
                                    size: 18,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Text(
                                  '${(item['quantity'] as num?)?.toInt() ?? 1}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  final currentQuantity =
                                      (item['quantity'] as num?)?.toInt() ?? 1;
                                  final itemId = item['id']?.toString() ?? '';
                                  final storeId =
                                      item['store_id']?.toString() ?? '';
                                  appState.updateCartItemQuantity(
                                    itemId,
                                    currentQuantity + 1,
                                    storeId,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  child: const Icon(
                                    Icons.add,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // السعر الإجمالي للطبق
                        Text(
                          '${((item['price'] as num? ?? 0) * (item['quantity'] as num? ?? 1)).toStringAsFixed(2)} د.ع',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // قسم الاقتراحات من نفس المطعم - محسن مع فلترة حسب نوع النشاط والفئات المحددة
  Widget _buildSuggestionsSection(
    BuildContext context,
    AppStateProvider appState,
  ) {
    String? currentStoreId = widget.storeId;
    if (currentStoreId == null && appState.cartItems.isNotEmpty) {
      currentStoreId = appState.cartItems.first['store_id']?.toString();
    }
    if (currentStoreId == null) {
      print('⚠️ لا يوجد store ID للاقتراحات');
      return const SizedBox.shrink();
    }

    print('🏪 جلب اقتراحات للمطعم: $currentStoreId');

    // 🔥 استخدام البيانات المحفوظة بدلاً من عمل استعلام
    final businessData = appState.getBusinessSuggestionData(currentStoreId);

    if (businessData == null) {
      print('❌ لا توجد بيانات محفوظة للمطعم: $currentStoreId');
      print('🔍 محاولة إجبار عرض قسم الاقتراحات للاختبار...');

      // 🔥 في حالة عدم وجود بيانات محفوظة، جرب عرض الاقتراحات مباشرة
      return FutureBuilder<List<ProductModel>>(
        future: _loadSuggestedProducts(currentStoreId),
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
            print('❌ لا توجد اقتراحات متاحة حتى بدون فلترة');
            return const SizedBox.shrink();
          }

          final suggestions = snapshot.data!;
          print(
            '📦 تم العثور على ${suggestions.length} اقتراحات بدون فلترة نوع المطعم',
          );

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔧 وضع الاختبار - لا توجد بيانات محفوظة',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 8),
                Text('تم العثور على ${suggestions.length} منتجات من المطعم'),
              ],
            ),
          );
        },
      );
    }

    print('🏢 البيانات المحفوظة: $businessData');
    print('🔍 businessType: "${businessData.businessType}"');
    print('🔍 isRestaurant result: ${businessData.isRestaurant}');

    // ✅ عرض الاقتراحات فقط للمطاعم - أو إذا كان businessType فارغ (افتراض أنه مطعم)
    final shouldShowSuggestions =
        businessData.isRestaurant ||
        businessData.businessType == null ||
        businessData.businessType!.isEmpty;

    if (!shouldShowSuggestions) {
      print(
        '❌ لن يتم عرض اقتراحات - نوع النشاط ليس مطعم: ${businessData.businessType}',
      );
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '❌ ليس مطعم',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text('نوع النشاط: "${businessData.businessType}"'),
            Text('isRestaurant: ${businessData.isRestaurant}'),
          ],
        ),
      );
    }

    print('✅ سيتم عرض الاقتراحات للمطعم');

    // 🔥 استخدام الفئات المحفوظة بدلاً من جلبها من قاعدة البيانات
    final suggestionCategories = businessData.suggestionAvailableCategories;

    print(
      '📋 الفئات المتوفرة في المطعم (${businessData.availableCategories.length}): ${businessData.availableCategories.join(", ")}',
    );
    print(
      '🎯 الفئات المطلوبة للاقتراحات (${BusinessSuggestionData.suggestionCategories.length}): ${BusinessSuggestionData.suggestionCategories.join(", ")}',
    );
    print(
      '✅ الفئات المطابقة للاقتراحات (${suggestionCategories.length}): ${suggestionCategories.join(", ")}',
    );

    if (suggestionCategories.isEmpty) {
      print('❌ لا توجد فئات مطلوبة متاحة في المطعم');
      print('📋 الفئات المتوفرة: ${businessData.availableCategories}');
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ لا توجد فئات مطلوبة',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'الفئات المتوفرة (${businessData.availableCategories.length}): ${businessData.availableCategories.join(", ")}',
            ),
            const SizedBox(height: 4),
            Text(
              'الفئات المطلوبة: ${BusinessSuggestionData.suggestionCategories.join(", ")}',
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<ProductModel>>(
      future: _loadSuggestedProducts(currentStoreId),
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
          print('❌ لا توجد اقتراحات متاحة');
          return const SizedBox.shrink();
        }

        final suggestions = snapshot.data!;
        print('📦 تم تحميل ${suggestions.length} اقتراحات');

        // استبعد المنتجات الموجودة بالفعل في السلة
        final cartProductIds =
            appState.cartItems.map((item) => item['id'] ?? '').toSet();
        final availableSuggestions =
            suggestions
                .where((product) => !cartProductIds.contains(product.id))
                .toList();

        print(
          '📦 بعد استبعاد المنتجات الموجودة في السلة: ${availableSuggestions.length} اقتراحات',
        );

        if (availableSuggestions.isEmpty) {
          print(
            '❌ لا توجد اقتراحات متاحة بعد استبعاد المنتجات الموجودة في السلة',
          );
          return const SizedBox.shrink();
        }

        // حدد العدد الأقصى للاقتراحات المعروضة
        final displaySuggestions =
            availableSuggestions.length > 6
                ? availableSuggestions.take(6).toList()
                : availableSuggestions;

        print('✅ سيتم عرض ${displaySuggestions.length} اقتراحات');

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
      print('🔍 بدء تحميل الاقتراحات للمطعم: $businessId');

      // جلب جميع فئات ومنتجات المطعم
      final categoryProducts =
          await BusinessService.getBusinessCategoriesAndProducts(businessId);

      print(
        '📋 فئات المطعم المتوفرة (${categoryProducts.keys.length}): ${categoryProducts.keys.toList()}',
      );

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

      print('🎯 الفئات المستهدفة: $targetCategories');

      final List<ProductModel> suggestions = [];
      int totalMatchedCategories = 0;

      // البحث في فئات المطعم عن الفئات المطلوبة
      for (final entry in categoryProducts.entries) {
        final categoryName = entry.key.toLowerCase().trim();
        final products = entry.value;

        print('🔍 فحص فئة: "$categoryName" (عدد المنتجات: ${products.length})');

        // فحص محسن لمطابقة الفئات - مطابقة مرنة وشاملة
        bool isTargetCategory = false;
        String? matchedTarget;

        // فحص المطابقة مع تجاهل الحالة والمسافات
        for (final target in targetCategories) {
          final targetLower = target.toLowerCase().trim();
          final categoryLower = categoryName.toLowerCase().trim();

          // مطابقة مباشرة تماماً
          if (categoryLower == targetLower) {
            isTargetCategory = true;
            matchedTarget = target;
            print('✅ مطابقة مباشرة تماماً: "$categoryName" = "$target"');
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
              matchedTarget = target;
              print('✅ مطابقة جزئية محسنة: "$categoryName" ↔ "$target"');
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
            matchedTarget = target;
            print('✅ مطابقة كلمة مفتاحية: "$categoryName" ↔ "$target"');
            break;
          }
        }

        if (isTargetCategory && products.isNotEmpty) {
          totalMatchedCategories++;
          print(
            '✅ إضافة ${products.length} منتجات من فئة: "$categoryName" (مطابقة مع: $matchedTarget)',
          );
          // إضافة المنتجات من هذه الفئة (حد أقصى 3 منتجات لكل فئة)
          final productsToAdd = products.take(3).toList();
          suggestions.addAll(productsToAdd);

          // طباعة أسماء المنتجات المضافة
          for (var product in productsToAdd) {
            print('   - ${product.name} (${product.price} د.ع)');
          }
        } else if (isTargetCategory) {
          print('⚠️ فئة مطابقة لكن لا توجد منتجات: "$categoryName"');
        } else {
          print('❌ لا تطابق: "$categoryName"');
        }
      }

      // خلط الاقتراحات للحصول على تنوع أكبر
      suggestions.shuffle();

      print('📊 ملخص النتائج:');
      print('   - إجمالي الفئات المفحوصة: ${categoryProducts.keys.length}');
      print('   - الفئات المطابقة: $totalMatchedCategories');
      print('   - إجمالي الاقتراحات المحملة: ${suggestions.length}');

      return suggestions;
    } catch (e) {
      print('❌ خطأ في تحميل الاقتراحات: $e');
      return [];
    }
  }

  // زر إضافة المزيد من الأطباق
  Widget _buildAddMoreDishesButton(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
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
                  Icons.add_shopping_cart,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'تريد المزيد؟',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'استكشف المزيد من الأطباق اللذيذة من نفس المطعم',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              onPressed: () {
                _navigateBackToStore(context);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'إضافة المزيد من الأطباق',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // تفاصيل السلة
  // تفاصيل السلةrtSummary(BuildContext context, AppStateProvider appState) {
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
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
                'عدد الأطباق ($totalDishes)',
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
              Text(
                '${subtotal.toStringAsFixed(2)} د.ع',
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
              StorefrontValue(
                branchId:
                    widget.storeId ??
                    (appState.cartItems.isEmpty
                        ? ''
                        : appState.cartItems.first['store_id'] as String? ??
                            ''),
                field: StorefrontField.fee,
                items: appState.cartItems,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          // المجموع الكلي
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'مجموع الأصناف',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${subtotal.toStringAsFixed(2)} د.ع',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // زر المتابعة مع التحقق من الحد الأدنى
  // زر المتابعة مع التحقق من الحد الأدنىt context, AppStateProvider appState) {
  Widget _buildCheckoutButton(BuildContext context, AppStateProvider appState) {
    final double subtotal = appState.cartTotal;
    final branch =
        widget.storeId ??
        appState.cartItems.firstOrNull?['store_id']?.toString() ??
        '';
    final preview = StorefrontPricing.instance.peek(branch, appState.cartItems);
    final minimum = (preview?.minimumOrderAmountIqd ?? 0).toDouble();
    final bool isMinimumMet = subtotal >= minimum;
    final double remainingAmount = minimum - subtotal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preview != null && !isMinimumMet)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: Colors.amber,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الحد الأدنى للطلب',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                          Text(
                            'أضف ${remainingAmount.toStringAsFixed(2)} د.ع إضافية للوصول للحد الأدنى (${minimum.toStringAsFixed(0)} د.ع)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isMinimumMet ? AppColors.primary : Colors.grey[400],
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: isMinimumMet ? 2 : 0,
                ),
                onPressed:
                    preview == null
                        ? () {
                          StorefrontPricing.instance.load(
                            branch,
                            appState.cartItems,
                            force: true,
                          );
                          _showSnackBar(
                            context,
                            "تعذر التحقق من تفاصيل الطلب. أعد المحاولة.",
                            Colors.amber,
                          );
                        }
                        : isMinimumMet
                        ? () {
                          // Navigate to new checkout screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => CheckoutScreen(
                                    storeId:
                                        widget.storeId ??
                                        appState.cartItems.first['store_id']
                                            ?.toString(),
                                    storeName: _resolveStoreName() ?? 'المطعم',
                                  ),
                            ),
                          );
                        }
                        : () {
                          _showSnackBar(
                            context,
                            'الحد الأدنى للطلب ${minimum.toStringAsFixed(0)} د.ع. أضف ${remainingAmount.toStringAsFixed(2)} د.ع إضافية.',
                            Colors.amber,
                          );
                        },
                child: Text(
                  preview == null
                      ? 'التحقق من تفاصيل الطلب'
                      : isMinimumMet
                      ? 'متابعة الطلب'
                      : 'أضف ${remainingAmount.toStringAsFixed(2)} د.ع للمتابعة',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
    if (widget.storeId != null && widget.stores != null) {
      // البحث عن المطعم الحالي
      try {
        final store = widget.stores!.firstWhere(
          (s) => s.id == widget.storeId,
          orElse:
              () =>
                  widget.stores!.isNotEmpty
                      ? widget.stores!.first
                      : Store(
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
                        combos: [],
                        sandwiches: [],
                        drinks: [],
                        extras: [],
                        specialties: [],
                      ),
        );

        // إذا تم العثور على المطعم، الانتقال مباشرة إلى شاشة المطعم
        if (store.id.isNotEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => StoreDetailScreen(store: store),
            ),
          );
          return;
        }
      } catch (e) {
        // في حالة حدوث خطأ، العودة للشاشة السابقة فقط
        print('Error navigating back to store: $e');
      }
    }

    // العودة للشاشة السابقة إذا لم نجد معلومات المطعم أو حدث خطأ
    if (Navigator.canPop(context)) {
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
                          final itemId = item['id']?.toString() ?? '';
                          appState.removeFromCart(itemId);
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
    try {
      // 🔒 فحص توفر المطعم قبل إضافة المنتج
      if (widget.storeId != null && widget.storeId!.isNotEmpty) {
        final availabilityService = RestaurantAvailabilityService.instance;
        final availabilityStatus = await availabilityService
            .checkRestaurantAvailability(widget.storeId!, skipCache: true);

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
      print('🛒 محاولة إضافة منتج للسلة: ${product.name} (ID: ${product.id})');
      final cartItem = {
        'id': product.id, // ✅ إصلاح: تغيير من 'dish_id' إلى 'id'
        'name': product.name,
        'description': product.description,
        'image': product.imageUrl,
        'price': product.price,
        'quantity': 1,
        'store_id': widget.storeId ?? '1',
        'store_name': _resolveStoreName() ?? 'المطعم',
        'store_address': 'العنوان غير محدد', // TODO: إضافة عنوان المطعم الحقيقي
      };
      print('🛒 بيانات المنتج: $cartItem');
      final success = await appState.addToCart(
        cartItem,
      ); // ✅ إصلاح: await للدالة async
      if (success) {
        print('✅ تم إضافة المنتج للسلة بنجاح');
        _showSnackBar(
          context,
          'تم إضافة ${product.name} للسلة',
          AppColors.primary,
        );
      } else {
        print('❌ فشل في إضافة المنتج للسلة');
        _showSnackBar(context, 'فشل في إضافة المنتج للسلة', Colors.red);
      }
    } catch (e) {
      print('❌ خطأ في إضافة المنتج للسلة: $e');
      _showSnackBar(
        context,
        'حدث خطأ في إضافة المنتج: ${e.toString()}',
        Colors.red,
      );
    }
  }
}
