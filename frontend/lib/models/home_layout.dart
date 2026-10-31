import 'business_model.dart';
import 'browsing_location.dart';

class HomeSection {
  final String id, title, source, ranking, layout;
  final List<String> merchantIds, cuisineIds, brandIds;
  final int limit, windowDays;
  final bool openNow, offersOnly;
  final double? maxDistanceKm, minimumRating;
  final DateTime? startAt, endAt;
  HomeSection.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      source = json['source'] as String,
      ranking =
          json['ranking'] as String? ??
          ({
                'rating': 'rating',
                'new': 'new',
                'curated': 'manual',
              }[json['source']] ??
              'default'),
      layout = json['layout'] as String? ?? 'carousel',
      merchantIds = List<String>.from(json['merchantIds'] ?? []),
      cuisineIds = List<String>.from(json['filters']?['cuisineIds'] ?? []),
      brandIds = List<String>.from(json['filters']?['brandIds'] ?? []),
      openNow = json['filters']?['openNow'] == true,
      offersOnly = json['filters']?['offersOnly'] == true,
      maxDistanceKm = (json['filters']?['maxDistanceKm'] as num?)?.toDouble(),
      minimumRating = (json['filters']?['minimumRating'] as num?)?.toDouble(),
      limit = json['limit'] as int,
      windowDays = json['windowDays'] as int? ?? 30,
      startAt = DateTime.tryParse(json['startAt'] ?? ''),
      endAt = DateTime.tryParse(json['endAt'] ?? '') {
    if (!['region', 'rating', 'new', 'curated', 'favorites'].contains(source) ||
        ![
          'default',
          'manual',
          'rating',
          'new',
          'distance',
          'orders',
        ].contains(ranking) ||
        !['carousel', 'compactList'].contains(layout) ||
        ![7, 30].contains(windowDays) ||
        limit < 1 ||
        limit > 12 ||
        title.isEmpty)
      throw const FormatException('Unsupported home section');
  }
  bool activeAt(DateTime now) =>
      (startAt == null || !now.isBefore(startAt!)) &&
      (endAt == null || now.isBefore(endAt!));
}

class HomeLayout {
  final bool configured;
  final List<HomeSection> sections;
  final Map<String, dynamic> discovery;
  HomeLayout.fromJson(Map<String, dynamic> json)
    : configured = json['configured'] == true,
      discovery = Map<String, dynamic>.from(json['discovery'] ?? {}),
      sections =
          (json['sections'] as List? ?? [])
              .map((x) => HomeSection.fromJson(Map<String, dynamic>.from(x)))
              .toList();
}

/// Operates only on the already region-authorized merchant set; no network or order scans.
List<BusinessModel> selectHomeBusinesses(
  HomeSection section,
  List<BusinessModel> available, {
  required Map<String, dynamic> facts,
  required bool Function(String) isFavorite,
  required BrowsingLocation? point,
  required DateTime now,
}) {
  final profiles = facts['catalog']?['profiles'] as Map? ?? {};
  final stats = facts['stats'] as Map?;
  final freshStats =
      DateTime.tryParse(stats?['expiresAt'] ?? '')?.isAfter(now) == true;
  final offers = facts['offers'] as Map?;
  final freshOffers =
      DateTime.tryParse(offers?['expiresAt'] ?? '')?.isAfter(now) == true;
  double? distance(BusinessModel b) =>
      point?.hasPoint == true
          ? b.calculateDistanceFrom(point!.latitude!, point.longitude!)
          : null;
  int count(BusinessModel b) {
    final v = stats?['counts']?[b.id]?['days${section.windowDays}'];
    return freshStats && v is int && v > 0 ? v : 0;
  }

  DateTime? created(BusinessModel b) =>
      DateTime.tryParse(b.metadata?['created_at']?.toString() ?? '');
  final result =
      available.where((b) {
        if (!b.isActive) return false;
        if (section.source == 'curated' && !section.merchantIds.contains(b.id))
          return false;
        if (section.source == 'favorites' && !isFavorite(b.id)) return false;
        if (section.source == 'new' &&
            (created(b) == null ||
                created(b)!.isBefore(now.subtract(const Duration(days: 30)))))
          return false;
        final profile = profiles[b.id] as Map? ?? {};
        if (section.cuisineIds.isNotEmpty &&
            !section.cuisineIds.any(
              (id) => (profile['cuisineIds'] as List? ?? []).contains(id),
            ))
          return false;
        if (section.brandIds.isNotEmpty &&
            !section.brandIds.contains(profile['brandId']))
          return false;
        if (section.openNow &&
            (b.metadata?['isClosed'] == true ||
                b.metadata?['isOnline'] == false ||
                b.metadata?['acceptingOrders'] == false ||
                b.metadata?['isBusy'] == true))
          return false;
        if (section.offersOnly &&
            (!freshOffers ||
                !(offers?['allMerchants'] == true ||
                    (offers?['merchantIds'] as List? ?? []).contains(b.id))))
          return false;
        if (section.minimumRating != null &&
            ((b.reviewCount ?? 0) <= 0 || b.rating < section.minimumRating!))
          return false;
        if (section.ranking == 'rating' &&
            ((b.reviewCount ?? 0) <= 0 || b.rating <= 0 || b.rating > 5 || !b.rating.isFinite))
          return false;
        if ((section.ranking == 'distance' || section.maxDistanceKm != null) &&
            distance(b) == null)
          return false;
        if (section.maxDistanceKm != null &&
            distance(b)! > section.maxDistanceKm!)
          return false;
        if (section.ranking == 'orders' && count(b) == 0) return false;
        return true;
      }).toList();
  int compare(BusinessModel a, BusinessModel b) {
    final primary = switch (section.ranking) {
      'rating' => b.rating.compareTo(a.rating),
      'distance' => distance(a)!.compareTo(distance(b)!),
      'orders' => count(b).compareTo(count(a)),
      'new' => (created(b)?.millisecondsSinceEpoch ?? 0).compareTo(
        created(a)?.millisecondsSinceEpoch ?? 0,
      ),
      'manual' => section.merchantIds
          .indexOf(a.id)
          .compareTo(section.merchantIds.indexOf(b.id)),
      _ => 0,
    };
    return primary != 0 ? primary : a.id.compareTo(b.id);
  }

  if (section.ranking != 'default') result.sort(compare);
  return result.take(section.limit).toList();
}
