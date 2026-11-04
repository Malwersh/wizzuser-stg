import 'store_offer_slot.dart';
import 'product_model.dart';

class InterfaceSection {
  final String id, title, description, source, layout, ranking, audience;
  final StoreOfferSlot offerSlot;
  final int limit;
  final bool enabled, deduplicate;
  final List<String> productIds, categoryIds;
  final Map<String, dynamic> filters;
  final DateTime? startAt, endAt;
  InterfaceSection.fromJson(Map<String, dynamic> j)
    : offerSlot = StoreOfferSlot.fromJson(
        Map<String, dynamic>.from(j['offerSlot'] ?? {}),
      ),
      id = j['id'],
      title = j['title'],
      description = j['description'] ?? '',
      source = j['source'],
      layout = j['layout'] ?? 'horizontal',
      ranking = j['ranking'] ?? 'default',
      audience = j['audience'] ?? 'all',
      limit = j['limit'] ?? 12,
      enabled = j['enabled'] != false,
      deduplicate = j['deduplicate'] == true,
      productIds = List<String>.from(j['productIds'] ?? []),
      categoryIds = List<String>.from(j['categoryIds'] ?? []),
      filters = Map<String, dynamic>.from(j['filters'] ?? {}),
      startAt = DateTime.tryParse(j['startAt'] ?? ''),
      endAt = DateTime.tryParse(j['endAt'] ?? '') {
    if (!['horizontal', 'vertical', 'grid'].contains(layout) ||
        limit < 1 ||
        limit > 30)
      throw const FormatException('Invalid interface section');
  }
  bool visible(bool signedIn, DateTime now) =>
      enabled &&
      (audience == 'all' || audience == (signedIn ? 'signedIn' : 'guest')) &&
      (startAt == null || !now.isBefore(startAt!)) &&
      (endAt == null || now.isBefore(endAt!));
}

class InterfaceLayout {
  final List<StoreOffer> offers;
  final bool configured;
  final List<InterfaceSection> sections;
  final DateTime? validUntil;
  final Map<String, int> counts;
  InterfaceLayout.fromJson(Map<String, dynamic> j)
    : offers =
          (j['offers'] as List? ?? [])
              .map((o) => StoreOffer.fromJson(Map<String, dynamic>.from(o)))
              .toList(),
      configured = j['configured'] == true,
      sections =
          (j['sections'] as List? ?? [])
              .map(
                (s) => InterfaceSection.fromJson(Map<String, dynamic>.from(s)),
              )
              .toList(),
      validUntil = DateTime.tryParse(j['validUntil'] ?? ''),
      counts = Map<String, dynamic>.from(
        j['itemCounts'] ?? {},
      ).map((k, v) => MapEntry(k, v is int ? v : 0));
  bool get fresh => validUntil?.isAfter(DateTime.now()) == true;
}

/// Screen-owned presentation snapshot. Cache expiry and background prefetch cannot
/// replace the screen a customer is already browsing. Pricing is not stored here.
class InterfaceScreenSession {
  String? _scope;
  InterfaceLayout? _layout;
  InterfaceLayout? current(String scope) => _scope == scope ? _layout : null;
  bool accept(String scope, InterfaceLayout layout, {required bool apply}) {
    if (!apply && current(scope) != null) return false;
    _scope = scope;
    _layout = layout;
    return true;
  }
}

List<ProductModel> selectInterfaceProducts(
  InterfaceSection s,
  List<ProductModel> products, {
  required Set<String> discounted,
  List<String> previous = const [],
  List<String> last = const [],
  List<String> recent = const [],
  ProductModel? current,
  Map<String, int> counts = const {},
  Set<String> seen = const {},
}) {
  final order =
      s.source == 'lastOrder'
          ? last
          : s.source == 'previousOrders'
          ? previous
          : s.source == 'recent'
          ? recent
          : s.productIds;
  final list =
      products.where((p) {
        if (p.id == current?.id || s.deduplicate && seen.contains(p.id))
          return false;
        switch (s.source) {
          case 'discounted':
            if (!discounted.contains(p.id)) return false;
          case 'featured':
            if (!p.isFeatured) return false;
          case 'lastOrder':
          case 'previousOrders':
          case 'recent':
          case 'curated':
            if (!order.contains(p.id)) return false;
          case 'category':
            if (!s.categoryIds.contains(p.categoryId)) return false;
          case 'similar':
            if (current == null || current.categoryId != p.categoryId)
              return false;
          case 'complementary':
            if (!s.productIds.contains(p.id) &&
                !s.categoryIds.contains(p.categoryId))
              return false;
          case 'bestsellers':
            if ((counts[p.id] ?? 0) <= 0) return false;
        }
        final f = s.filters;
        return !(f['availableOnly'] == true && !p.isAvailable) &&
            !(f['vegetarian'] == true && !p.isVegetarian) &&
            !(f['vegan'] == true && !p.isVegan) &&
            !(f['glutenFree'] == true && !p.isGlutenFree) &&
            !(f['minPrice'] is num && p.price < (f['minPrice'] as num)) &&
            !(f['maxPrice'] is num && p.price > (f['maxPrice'] as num));
      }).toList();
  if (s.source == 'bestsellers')
    list.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
  else if ([
    'lastOrder',
    'previousOrders',
    'recent',
    'curated',
  ].contains(s.source))
    list.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
  else if (s.ranking == 'priceAsc')
    list.sort((a, b) => a.price.compareTo(b.price));
  else if (s.ranking == 'priceDesc')
    list.sort((a, b) => b.price.compareTo(a.price));
  else if (s.ranking == 'newest')
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list.take(s.limit).toList();
}
