// lib/models/store_discount.dart
import 'discount_terms.dart';

/// A merchant-managed discount from WhizzMerchants_Discounts,
/// exposed to the customer app via GET /business/{businessId}/discounts.
/// fromJson tolerates both the snake_case table schema and the
/// camelCase normalized shape returned by the backend.
class StoreDiscount {
  final String discountId;
  final String businessId;
  final String title;
  final String description;
  final String? imageUrl;
  final String type; // percentage | fixedAmount | conditional | freeDelivery | buyXGetY
  final double value;
  final String applicability; // allItems | specificItems | specificCategories | minimumOrder
  final List<String> applicableItemIds;
  final double minimumOrderAmount;
  final DateTime? validFrom;
  final DateTime? validTo;
  final DiscountTerms terms;
  List<String> get applicableCategoryIds => terms.applicableCategoryIds;
  String get termsSummary => terms.summary(minimum: minimumOrderAmount, applicability: applicability, end: validTo);

  const StoreDiscount({
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
      terms: DiscountTerms.fromJson(json),
      discountId: (json['discountId'] ?? json['id'] ?? '').toString(),
      businessId: (json['businessId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? json['image_url'] ?? json['image'])?.toString(),
      type: (json['type'] ?? '').toString(),
      value: double.tryParse(json['value']?.toString() ?? '') ?? 0,
      applicability: (json['applicability'] ?? 'allItems').toString(),
      applicableItemIds:
          (json['applicable_item_ids'] as List?)?.map((e) => e.toString()).toList() ??
              (json['applicableItemIds'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      minimumOrderAmount: double.tryParse(
              (json['minimum_order_amount'] ?? json['minimumOrderAmount'])?.toString() ?? '') ??
          0,
      validFrom: DateTime.tryParse((json['valid_from'] ?? json['validFrom'] ?? '').toString()),
      validTo: DateTime.tryParse((json['valid_to'] ?? json['validTo'] ?? '').toString()),
    );
  }

  /// Short Arabic label describing the discount value.
  String get displayValue {
    switch (type) {
      case 'percentage':
        return 'خصم ${formatDiscountNumber(value)}%';
      case 'fixedAmount':
        return 'خصم ${formatDiscountNumber(value)} د.ع';
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
