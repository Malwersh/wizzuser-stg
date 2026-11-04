import 'home_navigation.dart';
import 'product_model.dart';

/// Navigation context, never a replacement for the published menu or pricing.
class MenuClassificationFocus {
  final String id, label;
  const MenuClassificationFocus({required this.id, required this.label});

  static MenuClassificationFocus? fromNavigation(
    HomeNavigation? navigation,
    String selected, {
    String? activity,
  }) {
    if (navigation == null ||
        !navigation.enabled ||
        !navigation.topicsEnabled) {
      return null;
    }
    for (final item in navigation.topicsFor(activity)) {
      if (item.id == selected && item.kind == 'cuisine' && item.value != null) {
        return MenuClassificationFocus(id: item.value!, label: item.label);
      }
    }
    return null;
  }

  List<ProductModel> productsFor(String branchId, Iterable<ProductModel> menu) {
    final seen = <String>{};
    return menu
        .where(
          (product) =>
              product.businessId == branchId &&
              product.cuisineIds.contains(id) &&
              seen.add(product.id),
        )
        .toList();
  }
}
