import 'menu_item_price.dart';
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F5F8),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child:
                    store.logoUrl.isEmpty
                        ? Icon(Icons.restaurant_rounded, color: ink)
                        : Image.network(
                          store.logoUrl,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) =>
                                  Icon(Icons.restaurant_rounded, color: ink),
                        ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: ink,
                      ),
                    ),
                    if (store.category?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        store.category == 'restaurant'
                            ? 'مطعم'
                            : store.category!,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onDetails,
                tooltip: 'معلومات المطعم',
                icon: Icon(Icons.info_outline_rounded, color: ink, size: 23),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.star_rounded, color: ink, size: 18),
              Text(
                rating,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              if (int.tryParse(reviews) != null && int.parse(reviews) > 0)
                Text(
                  '($reviews تقييم)',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
            ],
          ),
          if (store.address.isNotEmpty)
            InkWell(
              onTap: onDetails,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: muted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        store.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.route_outlined, size: 16, color: muted),
                const SizedBox(width: 5),
                Flexible(
                  child: StorefrontValue(
                    branchId: store.id,
                    field: StorefrontField.distance,
                    items: const [],
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
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
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE6E9EE)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth / 3).clamp(126.0, 190.0).toDouble();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: IntrinsicHeight(
            child: Row(
              children: [
                SizedBox(
                  width: width,
                  child: _metric(
                    'رسوم التوصيل',
                    StorefrontField.fee,
                    Icons.delivery_dining_rounded,
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Color(0xFFE6E9EE),
                ),
                SizedBox(
                  width: width,
                  child: StorefrontMinimum(
                    branchId: store.id,
                    metricLayout: true,
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Color(0xFFE6E9EE),
                ),
                SizedBox(
                  width: width,
                  child: _metric(
                    'وقت التحضير',
                    StorefrontField.preparation,
                    Icons.restaurant_outlined,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _metric(String title, StorefrontField field, IconData icon) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      StorefrontValue(
        branchId: store.id,
        field: field,
        initialPreparationMinutes: store.averagePreparationMinutes,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF00296B),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF647184)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF647184)),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Photo-first menu card. All actions use the same availability gates as the list.
class RestaurantProductCard extends StatelessWidget {
  final ProductModel product;
  final bool available;
  final VoidCallback onDetails;
  final VoidCallback onAdd;
  final String? unavailableReason;
  const RestaurantProductCard({
    super.key,
    required this.product,
    required this.available,
    required this.onDetails,
    required this.onAdd,
    this.unavailableReason,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: available ? onDetails : null,
    borderRadius: BorderRadius.circular(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.12,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: const Color(0xFFF1F3F6),
                  child:
                      product.imageUrl.isEmpty
                          ? const Icon(
                            Icons.restaurant_outlined,
                            color: Color(0xFF8B97A8),
                            size: 32,
                          )
                          : Image.network(
                            product.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => const Icon(
                                  Icons.restaurant_outlined,
                                  color: Color(0xFF8B97A8),
                                  size: 32,
                                ),
                          ),
                ),
              ),
              if (!available) const ColoredBox(color: Color(0x88FFFFFF)),
              PositionedDirectional(
                end: 8,
                bottom: 8,
                child: Material(
                  color: Colors.white,
                  elevation: 2,
                  shadowColor: const Color(0x3000296B),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'إضافة إلى السلة',
                    onPressed: available ? onAdd : null,
                    icon: const Icon(Icons.add_rounded),
                    color: AppColors.secondary,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.4,
            color: Color(0xFF172338),
          ),
        ),
        const SizedBox(height: 4),
        MenuItemPrice(
          branch: product.businessId,
          product: product.id,
          original: product.price,
        ),
        if (!available)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              unavailableReason ?? 'غير متاح حالياً',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF697587)),
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
