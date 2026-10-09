import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';
import '../models/dish_model.dart';
import '../providers/app_state_provider.dart';
import '../widgets/robust_network_image.dart';
import '../services/restaurant_availability_service.dart';

class PaginatedDishList extends StatelessWidget {
  final List<DishModel> dishes;
  final String? categoryId;
  final VoidCallback? onLoadMore;
  final bool isLoading;
  final String? storeAddress; // إضافة عنوان المطعم

  const PaginatedDishList({
    super.key,
    required this.dishes,
    this.categoryId,
    this.onLoadMore,
    this.isLoading = false,
    this.storeAddress, // إضافة عنوان المطعم كمعامل اختياري
  });

  @override
  Widget build(BuildContext context) {
    if (dishes.isEmpty && !isLoading) {
      return const Center(
        child: Text(
          'لا توجد أطباق متاحة',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: dishes.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == dishes.length && isLoading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final dish = dishes[index];
        return _buildDishCard(context, dish);
      },
    );
  }

  Widget _buildDishCard(BuildContext context, DishModel dish) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صورة الطبق
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 80,
                height: 80,
                color: Colors.grey[200],
                child: dish.image != null && dish.image!.isNotEmpty
                    ? RobustNetworkImage(
                        imageUrl: dish.image!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[100],
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                        ),
                        errorWidget: Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(Icons.fastfood, color: Colors.grey, size: 25),
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.restaurant,
                        size: 40,
                        color: Colors.grey,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // تفاصيل الطبق
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dish.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black, // نص أسود واضح لاسم الطبق
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dish.description ?? 'وصف غير متوفر',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${dish.price.toStringAsFixed(2)} ر.س',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const Spacer(),
                      if (dish.storeName != null && dish.storeName!.isNotEmpty)
                        Text(
                          dish.storeName!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // زر الإضافة للسلة
            IconButton(
              onPressed: () => _addToCart(context, dish),
              icon: const Icon(
                Icons.add_shopping_cart,
                color: AppColors.primary,
              ),
              tooltip: 'إضافة للسلة',
            ),
          ],
        ),
      ),
    );
  }

  void _addToCart(BuildContext context, DishModel dish) async {
    try {
      // 🔒 أولاً: فحص توفر المطعم وحالة قبول الطلبات
      if (dish.storeId != null && dish.storeId!.isNotEmpty) {
        final availabilityService = RestaurantAvailabilityService.instance;
        final availabilityStatus = await availabilityService.checkRestaurantAvailability(
          dish.storeId!,
          skipCache: true, // فحص حالي للحصول على أحدث البيانات
        );
        
        // إذا كان المطعم غير متاح، أظهر رسالة مناسبة ولا تضيف للسلة
        if (!availabilityStatus.isAvailable) {
          String errorMessage;
          
          if (!availabilityStatus.acceptingOrders) {
            errorMessage = 'عذراً، هذا المطعم لا يستقبل طلبات جديدة حالياً';
          } else if (!availabilityStatus.isWithinWorkingHours) {
            errorMessage = 'عذراً، هذا المطعم مغلق حالياً';
          } else {
            errorMessage = availabilityStatus.reasonUnavailable ?? 'عذراً، هذا المطعم غير متاح حالياً';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
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
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
          return; // توقف هنا ولا تضيف للسلة
        }
      }
      
      // ✅ المطعم متاح، تابع عملية الإضافة للسلة
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      
      // تحضير بيانات الطبق للسلة مع حماية من null values
      final cartItem = {
        'id': dish.id,
        'name': dish.name,
        'price': dish.price,
        'description': dish.description ?? 'وصف غير متوفر',
        'image': dish.image ?? '',
        'store_id': dish.storeId ?? '',
        'store_name': dish.storeName ?? 'متجر غير محدد',
        'store_address': storeAddress ?? 'العنوان غير محدد', // استخدام عنوان المطعم المُمرر
        'quantity': 1,
        'category_id': categoryId ?? '',
      };

      appState.addToCart(cartItem);

      // إظهار رسالة تأكيد
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إضافة ${dish.name} إلى السلة'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      // إظهار رسالة خطأ
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء إضافة الطبق للسلة'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.primaryDark,
        ),
      );
    }
  }
}