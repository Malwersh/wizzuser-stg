import 'home_slide.dart';
import 'platform_benefit.dart';

class HomePromotionSettings {
  final bool enabled;
  final String? itemBackgroundColor;
  final String source, title, subtitle, backgroundColor;
  final List<Map<String, dynamic>> scenes;
  final int intervalSeconds;
  final Map<String, dynamic>? selection;
  final DateTime? startAt, endAt;
  HomePromotionSettings.fromJson(Map<String, dynamic> json)
    : itemBackgroundColor = json['itemBackgroundColor'] as String?,
      enabled = json['enabled'] == true,
      source = json['source'] as String? ?? 'both',
      subtitle = json['subtitle'] as String? ?? 'عروض وخصومات',
      scenes =
          (json['scenes'] as List? ?? [])
              .map((x) => Map<String, dynamic>.from(x))
              .toList(),
      title = json['title'] as String? ?? 'مزايا ويز',
      backgroundColor = json['backgroundColor'] as String? ?? '#00296B',
      intervalSeconds = ((json['intervalSeconds'] as num?)?.toInt() ?? 6).clamp(
        5,
        15,
      ),
      selection =
          json['selection'] is Map
              ? Map<String, dynamic>.from(json['selection'])
              : null,
      startAt = DateTime.tryParse(json['startAt'] ?? ''),
      endAt = DateTime.tryParse(json['endAt'] ?? '');
  bool active(DateTime now) =>
      enabled &&
      (startAt == null || !now.isBefore(startAt!)) &&
      (endAt == null || now.isBefore(endAt!));
  bool accepts(String kind, String id) =>
      (source == 'both' ||
          (source == 'merchant' ? kind == 'merchant' : kind != 'merchant')) &&
      (selection == null ||
          (selection!['source'] == kind && selection!['id'] == id));
}

class HomePromotion {
  final HomeSlide? slide;
  final PlatformBenefit? benefit;
  HomePromotion.offer(HomeSlide value) : slide = value, benefit = null;
  HomePromotion.benefit(PlatformBenefit value) : benefit = value, slide = null;
  String get id => '$source:${slide?.targetId ?? benefit!.id}';
  String get source => benefit != null ? 'benefit' : slide!.offerSource;
  bool get platform => source != 'merchant';
  String get title => benefit?.title ?? slide!.title;
  DateTime get endAt => benefit?.endAt ?? slide!.endAt;
  bool get delivery =>
      benefit?.isDelivery ?? slide?.offerType == 'freeDelivery';
  String get headline {
    if (benefit != null)
      return benefit!.kind == 'FREE_DELIVERIES'
          ? 'توصيل مجاني'
          : 'خصم ${benefit!.amountIqd} د.ع';
    if (slide!.offerType == 'freeDelivery') return 'توصيل مجاني';
    final value = slide!.offerValue;
    if (value != null && value > 0) {
      final label =
          value == value.roundToDouble()
              ? value.toInt().toString()
              : value.toString();
      if (slide!.offerType == 'percentage') return 'خصم $label٪';
      if (slide!.offerType == 'fixed') return 'خصم $label د.ع';
    }
    return title;
  }

  String get subtitle =>
      benefit == null
          ? '${slide!.merchants.length == 1 ? slide!.merchants.first['name']! + ' · ' : ''}$title'
          : benefit!.isDelivery
          ? 'على التوصيل · ${benefit!.remaining} متبقية'
          : 'على طلبك · ${benefit!.remaining} متبقية';
}

class HomePromotionScene {
  final String id, title, subtitle, logoUrl;
  final List<HomePromotion> offers;
  final List<Map<String, dynamic>> products;
  const HomePromotionScene({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.logoUrl,
    required this.offers,
    this.products = const [],
  });
  bool get platform => id == 'platform';
  static List<HomePromotionScene> build(
    List<HomePromotion> offers,
    HomePromotionSettings settings,
  ) {
    final groups = <String, List<HomePromotion>>{};
    for (final offer in offers) {
      final id =
          offer.platform
              ? 'platform'
              : offer.slide?.scene?['id'] as String? ??
                  (offer.slide!.merchants.length == 1
                      ? offer.slide!.merchants.first['id']!
                      : offer.id);
      groups.putIfAbsent(id, () => []).add(offer);
    }
    final ids =
        groups.keys.toList()..sort((a, b) {
          if (a == 'platform') return -1;
          if (b == 'platform') return 1;
          int rank(String x) {
            final n = settings.scenes.indexWhere((s) => s['id'] == x);
            return n < 0 ? 1000 : n;
          }

          return rank(a).compareTo(rank(b));
        });
    return ids
        .where(
          (id) =>
              !settings.scenes.any(
                (s) => s['id'] == id && s['enabled'] == false,
              ),
        )
        .map((id) {
          final config =
                  settings.scenes.where((s) => s['id'] == id).firstOrNull ?? {},
              rows = groups[id]!,
              scene = rows.first.slide?.scene;
          String text(String key, String fallback) =>
              config[key] is String && (config[key] as String).trim().isNotEmpty
                  ? config[key]
                  : fallback;
          final products = <Map<String, dynamic>>[], seen = <String>{};
          for (final offer in rows)
            for (final product
                in (offer.slide?.scene?['products'] as List? ?? [])) {
              final p = Map<String, dynamic>.from(product);
              if (seen.add(p['id'] as String)) products.add(p);
            }
          final merchantName =
              scene?['name'] as String? ??
              rows.first.slide?.merchants.firstOrNull?['name'] ??
              'عروض المطعم';
          return HomePromotionScene(
            id: id,
            title: text(
              'title',
              id == 'platform' ? settings.title : merchantName,
            ),
            subtitle: text(
              'subtitle',
              id == 'platform' ? settings.subtitle : 'اكتشف عروض المطعم',
            ),
            logoUrl: scene?['logoUrl'] as String? ?? '',
            offers: rows,
            products: products.take(6).toList(),
          );
        })
        .toList();
  }
}
