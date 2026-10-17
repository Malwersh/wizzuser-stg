// lib/models/platform_promo.dart

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

  const PlatformPromo({
    required this.code,
    this.title = '',
    this.description = '',
    this.type = 'percentage',
    this.value = 0,
    this.minOrderAmount = 0,
    this.endDate,
  });

  factory PlatformPromo.fromJson(Map<String, dynamic> json) {
    return PlatformPromo(
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
        return 'خصم ${value.toStringAsFixed(0)}%';
      case 'fixedAmount':
      case 'fixed':
      case 'fixed_amount':
        return 'خصم ${value.toStringAsFixed(0)} د.ع';
      case 'freeDelivery':
      case 'free_delivery':
      case 'free-delivery':
        return 'توصيل مجاني';
      default:
        return title;
    }
  }
}
