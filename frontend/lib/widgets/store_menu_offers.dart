import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/product_model.dart';
import '../services/menu_offer_pricing.dart';
import 'restaurant_menu_components.dart';

/// Uses the same server-priced item offers as the menu, never basket coupons.
List<ProductModel> discountedMenuProducts(
  Iterable<ProductModel> products,
  String branch,
  MenuOfferPricing pricing,
) {
  final seen = <String>{};
  return products.where((p) {
    if (p.businessId != branch || !seen.add(p.id)) return false;
    final price = pricing.price(branch, p.id, p.price);
    return price != null && price.unit.netFils < price.unit.originalFils;
  }).toList();
}

class StoreMenuOffers extends StatelessWidget {
  final List<ProductModel> products;
  final String branch;
  final String storeName;
  final Widget menuTabs;
  final bool Function(ProductModel) available;
  final String? Function(ProductModel) reason;
  final void Function(ProductModel) onOpen;
  final void Function(ProductModel) onAdd;
  const StoreMenuOffers({
    super.key,
    required this.products,
    required this.branch,
    required this.storeName,
    required this.menuTabs,
    required this.available,
    required this.reason,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: MenuOfferPricing.instance,
    builder: (context, _) {
      final offers = discountedMenuProducts(
        products,
        branch,
        MenuOfferPricing.instance,
      );
      return Row(
        children: [
          if (offers.isNotEmpty)
            TextButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder:
                          (pageContext) => Directionality(
                            textDirection: Directionality.of(context),
                            child: Scaffold(
                              backgroundColor: Colors.white,
                              appBar: AppBar(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.secondary,
                                title: Text('عروض $storeName'),
                                centerTitle: true,
                                leading: IconButton(
                                  icon: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                  ),
                                  onPressed:
                                      () => Navigator.of(pageContext).pop(),
                                ),
                              ),
                              body: ListenableBuilder(
                                listenable: MenuOfferPricing.instance,
                                builder: (context, _) {
                                  final current = discountedMenuProducts(
                                    products,
                                    branch,
                                    MenuOfferPricing.instance,
                                  );
                                  if (current.isEmpty)
                                    return const Center(
                                      child: Text('لا توجد عروض فعّالة حاليًا'),
                                    );
                                  return ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      16,
                                      20,
                                      32,
                                    ),
                                    itemCount: current.length,
                                    separatorBuilder:
                                        (_, __) => const SizedBox(height: 20),
                                    itemBuilder: (context, i) {
                                      final product = current[i];
                                      return RestaurantMenuTile(
                                        product: product,
                                        available: available(product),
                                        unavailableReason: reason(product),
                                        onDetails: () => onOpen(product),
                                        onAdd: () => onAdd(product),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                    ),
                  ),
              style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
              child: const Text(
                'عروض',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          Expanded(child: menuTabs),
        ],
      );
    },
  );
}
