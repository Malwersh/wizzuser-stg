import 'business_model.dart';

String? canonicalHomeActivity(BusinessModel business) =>
    business.businessTypeId ??
    const {
      'restaurant': 'RESTAURANT',
      'grocery': 'MARKET',
      'store': 'STORE',
    }[business.businessType.trim().toLowerCase()];

String homeActivity(BusinessModel business) {
  final type = business.businessType.trim().toLowerCase();
  if (['restaurant', 'مطعم'].contains(type)) return 'restaurant';
  if (['cafe', 'coffee', 'مقهى'].contains(type)) return 'cafe';
  if (['grocery', 'supermarket', 'بقالة', 'سوبرماركت'].contains(type))
    return 'grocery';
  if (['bakery', 'dessert', 'sweets', 'حلويات', 'مخبز'].contains(type))
    return 'sweets';
  return 'store';
}

class HomeNavigationItem {
  final String id, label, kind, icon;
  final String? value, imageUrl, imageKey;
  final List<String> parentActivities;
  HomeNavigationItem.fromJson(Map<String, dynamic> json)
    : parentActivities = List<String>.from(
        json['parentActivities'] ??
            (json['kind'] == 'cuisine' ? ['restaurant', 'cafe', 'sweets'] : []),
      ),
      id = json['id'] as String,
      label = json['label'] as String,
      kind = json['kind'] as String,
      icon = json['icon'] as String? ?? 'store',
      value = json['value'] as String?,
      imageKey = json['imageKey'] as String?,
      imageUrl = json['imageUrl'] as String? {
    if (!['all', 'activity', 'cuisine', 'brand'].contains(kind) ||
        label.isEmpty)
      throw const FormatException('Unsupported discovery category');
  }
  bool matches(BusinessModel business, Map<String, dynamic> facts) {
    final profile =
        (facts['catalog']?['profiles'] as Map?)?[business.id] as Map?;
    return switch (kind) {
      'all' => true,
      'activity' =>
        value == canonicalHomeActivity(business) ||
            (value != null && value == business.businessType) ||
            homeActivity(business) == value,
      'cuisine' =>
        (profile?['cuisineIds'] as List? ?? []).contains(value) ||
            (business.metadata?['publishedCuisineIds'] as List? ?? []).contains(
              value,
            ),
      'brand' => value != null && profile?['brandId'] == value,
      _ => false,
    };
  }

  String get asset => switch (icon) {
    'restaurant' || 'burger' => 'assets/icons/burger.png',
    'cafe' => 'assets/icons/cat_juice.png',
    'grocery' => 'assets/icons/cat_groce.png',
    'sweets' => 'assets/icons/cat_dessert.png',
    'pizza' => 'assets/icons/pizza.png',
    'chicken' => 'assets/icons/fried-chicken.png',
    'breakfast' => 'assets/icons/cat_break.png',
    'healthy' => 'assets/icons/salad.png',
    'sandwich' => 'assets/icons/cat_fast.png',
    _ => 'assets/icons/cat_supermarket.png',
  };
}

class HomeNavigation {
  final bool enabled, activitiesEnabled, topicsEnabled;
  final List<HomeNavigationItem> items;
  List<HomeNavigationItem> get activities =>
      items.where((r) => ['all', 'activity'].contains(r.kind)).toList();
  List<HomeNavigationItem> topicsFor(String? activity) =>
      items
          .where(
            (r) =>
                ['cuisine', 'brand'].contains(r.kind) &&
                (activity == null ||
                    r.parentActivities.isEmpty ||
                    r.parentActivities.contains(activity)),
          )
          .toList();
  HomeNavigation.fromJson(Map<String, dynamic> json)
    : activitiesEnabled = json['activitiesEnabled'] != false,
      topicsEnabled = json['topicsEnabled'] != false,
      enabled = json['enabled'] == true,
      items =
          (json['items'] as List? ?? [])
              .take(20)
              .map(
                (x) =>
                    HomeNavigationItem.fromJson(Map<String, dynamic>.from(x)),
              )
              .toList();
}
