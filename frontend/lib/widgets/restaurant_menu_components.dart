import 'storefront_value.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/store.dart';
import '../models/product_model.dart';
import '../models/store_discount.dart';

class RestaurantHeroDetails extends StatelessWidget {
  final Store store;
  final VoidCallback onDetails;
  final String? ratingOverride;
  final String? reviewsOverride;
  const RestaurantHeroDetails({
    super.key,
    required this.store,
    required this.onDetails,
    this.ratingOverride,
    this.reviewsOverride,
  });
  @override
  Widget build(BuildContext context) {
    final rating = ratingOverride ?? store.ratingLabel;
    final reviews = reviewsOverride ?? store.reviews;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: SizedBox(
                width: 46,
                height: 46,
                child:
                    store.logoUrl.isEmpty
                        ? const ColoredBox(
                          color: Colors.white24,
                          child: Icon(Icons.restaurant, color: Colors.white),
                        )
                        : Image.network(
                          store.logoUrl,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => const Icon(
                                Icons.restaurant,
                                color: Colors.white,
                              ),
                        ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                store.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          [
            if (store.category?.isNotEmpty == true)
              store.category == 'restaurant' ? 'مطعم' : store.category!,
            if (store.address.isNotEmpty) store.address,
          ].join('  •  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _badge(
                Icons.star_rounded,
                rating,
                int.tryParse(reviews) != null
                    ? '$reviews تقييم • التفاصيل'
                    : 'معلومات المطعم',
              ),
              const SizedBox(width: 9),
              _badge(
                Icons.restaurant_menu_rounded,
                'قائمة الطعام',
                'تعرّف على المطعم',
              ),
              const SizedBox(width: 9),
              _badge(
                Icons.info_outline_rounded,
                'معلومات المطعم',
                'العنوان وساعات العمل',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _badge(IconData icon, String title, String subtitle) => Material(
    color: Colors.white.withValues(alpha: .17),
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onDetails,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class RestaurantSummaryCard extends StatelessWidget {
  final Store store;
  final VoidCallback onDetails;
  final String? ratingOverride;
  final String? reviewsOverride;
  const RestaurantSummaryCard({
    super.key,
    required this.store,
    required this.onDetails,
    this.ratingOverride,
    this.reviewsOverride,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 18, bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffe5e5e5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xff191919),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'توصيل',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextButton(
              onPressed: onDetails,
              child: const Text(
                'معلومات المطعم',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth < 300
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2;
          Widget fact(IconData icon, String label, StorefrontField field) =>
              SizedBox(width: width, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(icon, size: 17, color: Colors.black54),
                    const SizedBox(width: 6),
                    Expanded(child: Text(label, style: const TextStyle(
                      color: Colors.black54, fontSize: 12))),
                  ]),
                  const SizedBox(height: 6),
                  StorefrontValue(branchId: store.id, field: field,
                    initialPreparationMinutes: store.averagePreparationMinutes,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ));
          return Wrap(spacing: 12, runSpacing: 18, children: [
            fact(Icons.delivery_dining, 'الوصول المتوقع إلى عنوانك', StorefrontField.arrival),
            fact(Icons.route_outlined, 'مسافة الطريق إلى عنوانك', StorefrontField.distance),
            fact(Icons.payments_outlined, 'رسوم التوصيل', StorefrontField.fee),
            fact(Icons.restaurant_outlined, 'تحضير المطعم فقط', StorefrontField.preparation),
          ]);
        }),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
        StorefrontMinimum(branchId: store.id),
        const SizedBox(height: 8),
        const Text('وقت الوصول تقديري ويشمل التحضير والطريق؛ قد يتغير حسب توفر السائق.',
          style: TextStyle(color: Colors.black54, fontSize: 11, height: 1.5)),
      ],
    ),
  );
}

class RestaurantMenuTile extends StatelessWidget {
  final ProductModel product;
  final bool available;
  final bool isBestseller;
  final String? unavailableReason;
  final VoidCallback onDetails;
  final String? ratingOverride;
  final String? reviewsOverride;
  final VoidCallback onAdd;

  const RestaurantMenuTile({
    super.key,
    required this.product,
    required this.available,
    required this.onDetails,
    this.ratingOverride,
    this.reviewsOverride,
    required this.onAdd,
    this.unavailableReason,
    this.isBestseller = false,
  });

  @override
  Widget build(BuildContext context) {
    final imageWidget = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        height: 84,
        color: const Color(0xffedf1f5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: available ? onDetails : null,
              child:
                  product.imageUrl.isNotEmpty
                      ? Image.network(
                        product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => const Center(
                              child: Icon(
                                Icons.restaurant_outlined,
                                color: Colors.black26,
                                size: 32,
                              ),
                            ),
                      )
                      : const Center(
                        child: Icon(
                          Icons.restaurant_outlined,
                          color: Colors.black26,
                          size: 32,
                        ),
                      ),
            ),
            if (!available)
              Container(color: Colors.white.withValues(alpha: 0.55)),
            if (isBestseller && available)
              PositionedDirectional(
                start: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffff7043),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        color: Colors.white,
                        size: 10,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'مميز',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return InkWell(
      onTap: available ? onDetails : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageWidget,
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff1a1a1a),
                    ),
                  ),
                  if (product.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        product.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          height: 1.3,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '${product.price % 1 == 0 ? product.price.toInt() : product.price} د.ع',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color:
                                available
                                    ? const Color(0xff1a1a1a)
                                    : Colors.grey.shade500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'إضافة إلى السلة',
                        onPressed: available ? onAdd : null,
                        icon: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              available
                                  ? AppColors.primary
                                  : Colors.grey.shade300,
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(30, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                      ),
                    ],
                  ),
                  if (!available)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        unavailableReason ?? 'غير متاح حالياً',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
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
}

/// بطاقة كوبون / عرض بنمط تذكرة مطابق لتصميم طلبات
class RestaurantCouponCard extends StatelessWidget {
  final StoreDiscount offer;
  final VoidCallback onTap;

  const RestaurantCouponCard({
    super.key,
    required this.offer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPercentage =
        offer.type == 'percentage' || offer.title.contains('%');

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe8eaed)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon badge
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color:
                          isPercentage
                              ? const Color(0xffe8f5e9)
                              : const Color(0xfffff3e0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isPercentage
                          ? Icons.percent_rounded
                          : Icons.confirmation_number_outlined,
                      color:
                          isPercentage
                              ? const Color(0xff2e7d32)
                              : const Color(0xffe65100),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.title.isNotEmpty
                              ? offer.title
                              : offer.displayValue,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xff1a1a1a),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          offer.termsSummary.isNotEmpty
                              ? offer.termsSummary
                              : (offer.description.isNotEmpty
                                  ? offer.description
                                  : offer.displayValue),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Divider(height: 1, color: Color(0xfff0f0f0)),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  isPercentage ? 'المزيد من التفاصيل' : 'تطبيق العرض',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isPercentage ? Colors.black87 : AppColors.primary,
                    decoration: isPercentage ? TextDecoration.underline : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
