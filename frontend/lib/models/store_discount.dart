// lib/models/store_discount.dart
import 'discount_terms.dart';

/// A merchant-managed discount from WhizzMerchants_Discounts,
/// exposed to the customer app via GET /business/{businessId}/discounts.
/// fromJson tolerates both the snake_case table schema and the
/// camelCase normalized shape returned by the backend.
class StoreDiscount {
  final String calculationMode;
  final String pricingRevision;
  final List<MenuUnitPrice> itemPrices;
  final DateTime? itemPricesValidUntil;
  final String discountId;
  final String businessId;
  final String title;
  final String description;
  final String? imageUrl;
  final String
  type; // percentage | fixedAmount | conditional | freeDelivery | buyXGetY
  final double value;
  final String
  applicability; // allItems | specificItems | specificCategories | minimumOrder
  final List<String> applicableItemIds;
  final double minimumOrderAmount;
  final DateTime? validFrom;
  final DateTime? validTo;
  final DiscountTerms terms;
  List<String> get applicableCategoryIds => terms.applicableCategoryIds;
  String get termsSummary => terms.summary(
    minimum: minimumOrderAmount,
    applicability: applicability,
    end: validTo,
  );

  const StoreDiscount({
    this.calculationMode = 'order',
    this.pricingRevision = '',
    this.itemPrices = const [],
    this.itemPricesValidUntil,
    required this.discountId,
    required this.businessId,
    required this.title,
    this.description = '',
    this.imageUrl,
    required this.type,
    required this.value,
    this.applicability = 'allItems',
    this.applicableItemIds = const [],
    this.minimumOrderAmount = 0,
    this.validFrom,
    this.validTo,
    this.terms = const DiscountTerms(),
  });

  factory StoreDiscount.fromJson(Map<String, dynamic> json) {
    return StoreDiscount(
      calculationMode:
          json['calculationMode'] == 'perItem' ? 'perItem' : 'order',
      itemPricesValidUntil: DateTime.tryParse(
        json['itemPricesValidUntil']?.toString() ?? '',
      ),
      itemPrices:
          (json['itemPrices'] as List? ?? const [])
              .whereType<Map>()
              .map((v) => MenuUnitPrice.fromJson(Map<String, dynamic>.from(v)))
              .whereType<MenuUnitPrice>()
              .toList(),
      terms: DiscountTerms.fromJson(json),
      discountId: (json['discountId'] ?? json['id'] ?? '').toString(),
      businessId: (json['businessId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      imageUrl:
          (json['imageUrl'] ?? json['image_url'] ?? json['image'])?.toString(),
      type: (json['type'] ?? '').toString(),
      value: double.tryParse(json['value']?.toString() ?? '') ?? 0,
      applicability: (json['applicability'] ?? 'allItems').toString(),
      applicableItemIds:
          (json['applicable_item_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['applicableItemIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      minimumOrderAmount:
          double.tryParse(
            (json['minimum_order_amount'] ?? json['minimumOrderAmount'])
                    ?.toString() ??
                '',
          ) ??
          0,
      validFrom: DateTime.tryParse(
        (json['valid_from'] ?? json['validFrom'] ?? '').toString(),
      ),
      validTo: DateTime.tryParse(
        (json['valid_to'] ?? json['validTo'] ?? '').toString(),
      ),
    );
  }

  StoreDiscount withItemPrices(
    List<MenuUnitPrice> prices, {
    DateTime? validUntil,
  }) => StoreDiscount(
    discountId: discountId,
    businessId: businessId,
    title: title,
    description: description,
    imageUrl: imageUrl,
    type: type,
    value: value,
    calculationMode: calculationMode,
    pricingRevision: pricingRevision,
    itemPrices: prices,
    itemPricesValidUntil:
        validUntil != null &&
                (itemPricesValidUntil == null ||
                    validUntil.isBefore(itemPricesValidUntil!))
            ? validUntil
            : itemPricesValidUntil,
    applicability: applicability,
    applicableItemIds: applicableItemIds,
    minimumOrderAmount: minimumOrderAmount,
    validFrom: validFrom,
    validTo: validTo,
    terms: terms,
  );

  /// Matching for discovery only. Final eligibility and price remain server-owned.
  bool includesMenuItem({
    required String itemId,
    required String categoryId,
    required String branchId,
    required DateTime now,
  }) {
    if (businessId.isNotEmpty && businessId != branchId) return false;
    if (validFrom != null && now.isBefore(validFrom!)) return false;
    if (validTo != null && !now.isBefore(validTo!)) return false;
    if (!['percentage', 'fixedAmount'].contains(type) || value <= 0)
      return false;
    if (applicability == 'specificItems')
      return applicableItemIds.contains(itemId);
    if (applicability == 'specificCategories')
      return applicableCategoryIds.contains(categoryId);
    return false; // A basket-wide promotion is not a reduced item price.
  }

  /// Short Arabic label describing the discount value.
  String get displayValue {
    switch (type) {
      case 'percentage':
        return 'خصم ${formatDiscountNumber(value)}%${calculationMode == 'perItem' ? ' لكل قطعة' : ''}';
      case 'fixedAmount':
        return 'خصم ${formatDiscountNumber(value)} د.ع${calculationMode == 'perItem' ? ' لكل قطعة' : ''}';
      case 'freeDelivery':
        return 'توصيل مجاني';
      case 'buyXGetY':
      case 'conditional':
        return 'عرض خاص';
      default:
        return title;
    }
  }
}

class MenuUnitPrice {
  final String productId;
  final int originalFils, netFils;
  const MenuUnitPrice(this.productId, this.originalFils, this.netFils);
  static MenuUnitPrice? fromJson(Map<String, dynamic> json) {
    final original = json['originalUnitFils'], net = json['netUnitFils'];
    if (json['productId'] is! String ||
        original is! int ||
        net is! int ||
        original <= 0 ||
        net < 0 ||
        net >= original)
      return null;
    return MenuUnitPrice(json['productId'], original, net);
  }
}
