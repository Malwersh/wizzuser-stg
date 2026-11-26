import 'business_model.dart';

class HomeFilter {
  final String id, label, kind;
  final bool enabled;
  final num? value;
  HomeFilter.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      label = j['label'],
      kind = j['kind'],
      enabled = j['enabled'] == true,
      value = j['value'];
}

class HomeFilters {
  final bool enabled;
  final List<HomeFilter> items;
  final Map<String, dynamic> priceBands;
  HomeFilters.fromJson(Map<String, dynamic> j)
    : enabled = j['enabled'] == true,
      items =
          (j['items'] as List? ?? [])
              .map((x) => HomeFilter.fromJson(Map<String, dynamic>.from(x)))
              .toList(),
      priceBands = Map<String, dynamic>.from(
        j['priceBands'] ??
            {'economyMaxIqd': 7000, 'mediumMaxIqd': 15000, 'minSamples': 3},
      );
  factory HomeFilters.defaults() => HomeFilters.fromJson({
    'enabled': true,
    'items': [
      {'id': 'all', 'label': 'الكل', 'kind': 'all', 'enabled': true},
      {'id': 'offers', 'label': 'عروض', 'kind': 'offers', 'enabled': true},
      {'id': 'open', 'label': 'مفتوح الآن', 'kind': 'openNow', 'enabled': true},
      {'id': 'price', 'label': 'السعر', 'kind': 'menuPrice', 'enabled': true},
      {
        'id': 'rating',
        'label': 'تقييم ٤ فأعلى',
        'kind': 'rating',
        'enabled': true,
        'value': 4,
      },
      {
        'id': 'fast',
        'label': 'توصيل سريع',
        'kind': 'fastDelivery',
        'enabled': true,
        'value': 30,
      },
      {
        'id': 'free',
        'label': 'توصيل مجاني',
        'kind': 'freeDelivery',
        'enabled': true,
      },
      {'id': 'sort', 'label': 'ترتيب', 'kind': 'sort', 'enabled': true},
    ],
  });
}

bool matchesHomeFilter(
  HomeFilter filter,
  BusinessModel b, {
  required Map<String, dynamic> facts,
  Map<String, dynamic>? route,
  double? fee,
  Map<String, dynamic>? price,
  String? priceTier,
  required HomeFilters settings,
  required DateTime now,
}) {
  switch (filter.kind) {
    case 'all':
    case 'sort':
      return true;
    case 'openNow':
      final at = DateTime.tryParse(b.metadata?['availabilityCheckedAt'] ?? '');
      return at != null &&
          !at.isAfter(now.add(const Duration(seconds: 5))) &&
          now.difference(at) < const Duration(minutes: 2) &&
          b.isActive &&
          b.metadata?['isAvailableNow'] == true;
    case 'rating':
      return (b.reviewCount ?? 0) > 0 &&
          b.rating.isFinite &&
          b.rating > 0 &&
          b.rating <= 5 &&
          b.rating >= (filter.value ?? 4);
    case 'offers':
      final offers = facts['offers'] as Map?;
      return DateTime.tryParse(offers?['expiresAt'] ?? '')?.isAfter(now) ==
              true &&
          (offers?['allMerchants'] == true ||
              (offers?['merchantIds'] as List? ?? []).contains(b.id));
    case 'freeDelivery':
      return fee != null && fee == 0;
    case 'deliveryFee':
      return fee != null && fee >= 0 && fee <= (filter.value ?? 0);
    case 'fastDelivery':
      final eta = route?['arrivalMinutes'];
      final max = eta is Map ? eta['maximum'] : null;
      return max is num &&
          max.isFinite &&
          max > 0 &&
          max <= (filter.value ?? 30);
    case 'preparation':
      final minutes = route?['preparationMinutes'];
      return minutes is num &&
          minutes.isFinite &&
          minutes > 0 &&
          minutes <= (filter.value ?? 20);
    case 'menuPrice':
      final median = price?['medianIqd'], count = price?['sampleCount'];
      if (DateTime.tryParse(price?['expiresAt'] ?? '')?.isAfter(now) != true ||
          median is! num ||
          !median.isFinite ||
          median <= 0 ||
          count is! int ||
          count < (settings.priceBands['minSamples'] as num? ?? 3))
        return false;
      final economy = settings.priceBands['economyMaxIqd'] as num? ?? 7000,
          medium = settings.priceBands['mediumMaxIqd'] as num? ?? 15000;
      return switch (priceTier) {
        'economy' => median <= economy,
        'medium' => median > economy && median <= medium,
        'premium' => median > medium,
        _ => true,
      };
    default:
      return false;
  }
}
