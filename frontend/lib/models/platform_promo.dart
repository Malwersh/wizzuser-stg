// lib/models/platform_promo.dart
import 'discount_terms.dart';

/// A platform-wide promo code created in the central platform
/// (WizzCentral_Platform_Discounts), exposed via GET /promo-codes/active.
class PlatformPromo {
  final String code;
  final String title;
  final String description;
  final String type; // percentage | fixedAmount
  final double value;
  final double minOrderAmount;
  final DateTime? endDate;
  final String applicability;
  final DiscountTerms terms;
  String get termsSummary => terms.summary(minimum: minOrderAmount, applicability: applicability, end: endDate);

  const PlatformPromo({
    required this.code,
    this.title = '',
    this.description = '',
    this.type = 'percentage',
    this.value = 0,
    this.minOrderAmount = 0,
    this.endDate,
    this.applicability = 'allItems',
    this.terms = const DiscountTerms(),
  });

  factory PlatformPromo.fromJson(Map<String, dynamic> json) {
    return PlatformPromo(
      terms: DiscountTerms.fromJson(json),
      applicability: (json['applicability'] ?? 'allItems').toString(),
      code: (json['code'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      type: (json['type'] ?? 'percentage').toString(),
      value: double.tryParse(json['value']?.toString() ?? '') ?? 0,
      minOrderAmount: double.tryParse(
              (json['minOrderAmount'] ?? json['min_order_amount'])?.toString() ?? '') ??
          0,
      endDate: DateTime.tryParse((json['endDate'] ?? '').toString()),
    );
  }

  /// Short Arabic label describing the promo value.
  String get displayValue {
    switch (type) {
      case 'percentage':
        return 'خصم ${formatDiscountNumber(value)}%';
      case 'fixedAmount':
      case 'fixed':
      case 'fixed_amount':
        return 'خصم ${formatDiscountNumber(value)} د.ع';
      case 'freeDelivery':
      case 'free_delivery':
      case 'free-delivery':
        return 'توصيل مجاني';
      default:
        return title;
    }
  }
}
