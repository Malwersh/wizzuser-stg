import '../utils/readable_colors.dart';
import 'storefront_value.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/store.dart';
import '../models/product_model.dart';
import '../models/store_discount.dart';

class RestaurantHeroDetails extends StatelessWidget {
  final Store store;
  final bool overImage;
  final VoidCallback onDetails;
  final String? ratingOverride;
  final String? reviewsOverride;
  const RestaurantHeroDetails({
    super.key,
    required this.store,
    required this.onDetails,
    this.overImage = false,
    this.ratingOverride,
    this.reviewsOverride,
  });
  @override
  Widget build(BuildContext context) {
    final ink = overImage ? Colors.white : const Color(0xFF00296B);
    final muted = overImage ? Colors.white70 : const Color(0xFF647184);
    final rating = ratingOverride ?? store.ratingLabel;
    final reviews = reviewsOverride ?? store.reviews;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
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
                      store.name,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (store.category?.isNotEmpty == true)
                      Text(
                        [
                          store.category == 'restaurant'
                              ? 'مطعم'
                              : store.category!,
                          if (store.address.isNotEmpty) store.address,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE8ECF2)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child:
                      store.logoUrl.isEmpty
                          ? const Icon(
                            Icons.restaurant_rounded,
                            color: Color(0xFF00296B),
                          )
                          : Image.network(
                            store.logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => const Icon(
                                  Icons.restaurant_rounded,
                                  color: Color(0xFF00296B),
                                ),
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Icon(Icons.star_rounded, color: ink, size: 18),
              const SizedBox(width: 4),
              Text(
                rating,
                style: TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
              if (int.tryParse(reviews) != null && int.parse(reviews) > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '($reviews تقييم)',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],

              TextButton(
                onPressed: onDetails,
                style: TextButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size(0, 36),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('معلومات المطعم'),
                    SizedBox(width: 5),
                    Icon(Icons.info_outline_rounded, size: 17),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
    margin: const EdgeInsets.only(top: 16, bottom: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE5E8ED)),
    ),
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFFF3F5F8),
            borderRadius: BorderRadius.vertical(top: Radius.circular(21)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.delivery_dining_rounded,
                size: 23,
                color: Color(0xFF00296B),
              ),
              const SizedBox(width: 9),
              const Text(
                'يصلك خلال',
                style: TextStyle(fontSize: 14, color: Color(0xFF647184)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StorefrontValue(
                  branchId: store.id,
                  field: StorefrontField.arrival,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00296B),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'رسوم التوصيل ',
                        style: TextStyle(
                          color: Color(0xFF647184),
                          fontSize: 13,
                        ),
                      ),
                      Flexible(
                        child: StorefrontValue(
                          branchId: store.id,
                          field: StorefrontField.fee,
                          style: const TextStyle(
                            color: Color(0xFF00296B),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.route_outlined,
                        size: 16,
                        color: Color(0xFF647184),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: StorefrontValue(
                          branchId: store.id,
                          field: StorefrontField.distance,
                          style: const TextStyle(
                            color: Color(0xFF647184),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: Color(0xFFEDF0F4)),
              ),
              StorefrontMinimum(branchId: store.id),
            ],
          ),
        ),
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
                        color: const Color(0xFF00296B),
                        size: 10,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'مميز',
                        style: TextStyle(
                          color: const Color(0xFF00296B),
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
                          foregroundColor: readableForeground(
                            available
                                ? AppColors.primary
                                : Colors.grey.shade300,
                          ),
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
