import 'platform_benefit.dart';
import 'discount_terms.dart';
import '../utils/currency_format.dart';

class StoreOfferSlot {
  final String mode, style, presentation;
  final List<String> sources, kinds;
  final List<Map<String, dynamic>> refs;
  final int maxCards;
  final bool showImage, showSource;
  StoreOfferSlot.fromJson(Map<String, dynamic> j)
    : mode = j['mode'] ?? 'automatic',
      style = j['style'] ?? 'spotlight',
      presentation = j['presentation'] ?? 'card',
      sources = List<String>.from(
        j['sources'] ?? ['merchant', 'platform', 'shared'],
      ),
      kinds = List<String>.from(j['kinds'] ?? ['items', 'order', 'delivery']),
      refs =
          (j['refs'] as List? ?? [])
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
      maxCards = j['maxCards'] ?? 4,
      showImage = j['showImage'] != false,
      showSource = j['showSource'] != false;
  List<StoreOffer> select(List<StoreOffer> offers, DateTime now) {
    final seen = <String>{};
    final result =
        offers
            .where(
              (o) =>
                  o.live(now) &&
                  sources.contains(o.origin) &&
                  kinds.contains(o.kind) &&
                  seen.add(o.key) &&
                  (mode != 'manual' ||
                      refs.any(
                        (r) => r['source'] == o.source && r['id'] == o.id,
                      )),
            )
            .toList();
    if (mode == 'manual')
      result.sort(
        (a, b) => refs
            .indexWhere((r) => r['source'] == a.source && r['id'] == a.id)
            .compareTo(
              refs.indexWhere(
                (r) => r['source'] == b.source && r['id'] == b.id,
              ),
            ),
      );
    else
      result.sort(
        (a, b) => a.key.compareTo(b.key),
      ); // stable; never claim nominal percentage is best saving
    return result.take(maxCards).toList();
  }
}

class StoreOffer {
  final String id,
      source,
      origin,
      kind,
      title,
      description,
      type,
      calculationMode,
      applicability,
      imageUrl;
  final String? code;
  final double value, minimumOrder;
  final double? maximumSavings;
  final List<String> itemIds, categoryIds;
  final DateTime? startAt, endAt;
  final DiscountTerms terms;
  final PlatformBenefit? benefit;
  StoreOffer.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      source = j['source'],
      origin = j['origin'],
      kind = j['kind'],
      title = j['title'] ?? '',
      description = j['description'] ?? '',
      type = j['type'] ?? '',
      calculationMode = j['calculationMode'] ?? 'order',
      applicability = j['applicability'] ?? 'allItems',
      imageUrl = j['imageUrl'] ?? '',
      code = j['code'],
      value = (j['value'] as num? ?? 0).toDouble(),
      minimumOrder = (j['minimumOrder'] as num? ?? 0).toDouble(),
      maximumSavings = (j['maximumSavings'] as num?)?.toDouble(),
      itemIds = List<String>.from(j['itemIds'] ?? []),
      categoryIds = List<String>.from(j['categoryIds'] ?? []),
      startAt = DateTime.tryParse(j['startAt'] ?? ''),
      endAt = DateTime.tryParse(j['endAt'] ?? ''),
      terms = DiscountTerms.fromJson({
        ...j,
        'maxDiscountAmount': j['maximumSavings'],
      }),
      benefit = null;
  StoreOffer.fromBenefit(PlatformBenefit b)
    : id = b.id,
      source = 'benefit',
      origin = 'platform',
      kind = b.isDelivery ? 'delivery' : 'order',
      title = b.title,
      description = b.description,
      type = b.kind,
      calculationMode = 'order',
      applicability = 'allItems',
      imageUrl = '',
      code = null,
      value = b.amountIqd.toDouble(),
      minimumOrder = b.minimumGoodsIqd.toDouble(),
      maximumSavings =
          b.maximumPerOrderIqd > 0 ? b.maximumPerOrderIqd.toDouble() : null,
      itemIds = const [],
      categoryIds = const [],
      startAt = b.startAt,
      endAt = b.endAt,
      terms = const DiscountTerms(),
      benefit = b;
  String get key => '$source:$id';
  bool live(DateTime now) =>
      (startAt == null || !now.isBefore(startAt!)) &&
      (endAt == null || now.isBefore(endAt!)) &&
      (benefit == null || benefit!.eligible && benefit!.remaining > 0);
  String get sourceLabel =>
      origin == 'shared'
          ? 'عرض مشترك'
          : origin == 'platform'
          ? 'من ويز'
          : 'من المطعم';
  bool get freeDelivery => type == 'FREE_DELIVERIES' || type == 'freeDelivery';
  String get displayValue =>
      freeDelivery ? 'مجاني' : formatDiscountNumber(value);
  String get displayUnit =>
      freeDelivery
          ? ''
          : type == 'percentage'
          ? '٪'
          : 'د.ع';
  String get displayCaption =>
      freeDelivery
          ? 'توصيل طلبك'
          : kind == 'delivery'
          ? 'خصم على التوصيل'
          : calculationMode == 'perItem'
          ? 'خصم لكل قطعة'
          : 'خصم على الطلب';
  String get headline =>
      type == 'FREE_DELIVERIES' || type == 'freeDelivery'
          ? 'توصيل مجاني'
          : type == 'DELIVERY_AMOUNT'
          ? 'توفير على التوصيل ${formatIqd(value)}'
          : type == 'percentage'
          ? 'خصم ${formatDiscountNumber(value)}٪${calculationMode == 'perItem' ? ' لكل قطعة' : ''}'
          : 'وفّر ${formatIqd(value)}${calculationMode == 'perItem' ? ' لكل قطعة' : ''}';
  String get brief => [
    if (kind == 'items') 'على أصناف محددة',
    if (minimumOrder > 0) 'للطلبات من ${formatIqd(minimumOrder)}',
    if (maximumSavings != null) 'حتى ${formatIqd(maximumSavings!)}',
    if (terms.firstOrderOnly) 'لأول طلب فقط',
    if (benefit != null) 'المتبقي ${benefit!.remaining} استخدام',
  ].join(' • ');
  String get fullTerms => [
    terms.summary(
      minimum: minimumOrder,
      applicability: applicability,
      end: endAt,
    ),
    if (benefit != null && benefit!.maximumRoadMeters > 0)
      'ضمن مسافة توصيل حتى ${(benefit!.maximumRoadMeters / 1000).toStringAsFixed(1)} كم',
    if (benefit != null && maximumSavings != null)
      'أقصى توفير ${formatIqd(maximumSavings!)}',
    if (benefit != null) 'المتبقي ${benefit!.remaining} استخدام',
    if (kind != 'delivery') 'يُطبق عرض بضاعة واحد لكل طلب، دون جمع الخصومات',
  ].where((s) => s.isNotEmpty).join(' • ');
  bool includes(String product, String category) =>
      applicability == 'specificItems'
          ? itemIds.contains(product)
          : applicability == 'specificCategories'
          ? categoryIds.contains(category)
          : false;
}
