// Standalone model regression check: dart frontend/test/discount_terms_model_test.dart
import '../lib/models/discount_terms.dart';
import '../lib/models/store_discount.dart';
import '../lib/models/platform_promo.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  for (final entry in {0.0: '0', 10.0: '10', 12.5: '12.5', 33.333: '33.333', 1000.001: '1000.001'}.entries) {
    check(formatDiscountNumber(entry.key) == entry.value, 'Numeric precision: ${entry.key}');
  }
  final json = <String, dynamic>{
    'discountId': 'd', 'businessId': 'b', 'code': 'SAVE', 'type': 'percentage', 'value': 12.5,
    'minimumOrderAmount': 1000.5, 'minOrderAmount': 1000.5,
    'applicability': 'specificCategories', 'applicable_category_ids': ['category'],
    'maxDiscountAmount': 2500.75, 'firstOrderOnly': true, 'perCustomerLimit': 2,
    'customerSegments': ['new', 'vip'], 'validTo': '2030-01-01T22:30:00Z', 'endDate': '2030-01-01T22:30:00Z',
  };
  final store = StoreDiscount.fromJson(json), platform = PlatformPromo.fromJson(json);
  check(store.displayValue == 'خصم 12.5%', 'Store fractional percentage');
  check(platform.displayValue == store.displayValue, 'Platform label parity');
  check(platform.termsSummary == store.termsSummary, 'Shared terms parity');
  check(store.applicableCategoryIds.single == 'category', 'Category IDs');
  for (final term in ['فئات محددة', '1000.5', '2500.75', 'لأول طلب فقط', '2 مرات', 'أو', '2030/01/02 01:30', 'بغداد']) {
    check(store.termsSummary.contains(term), 'Missing term: $term');
  }
  check(DiscountTerms.fromJson({'singleUse': true, 'perCustomerLimit': 5})
      .summary(minimum: 0).contains('مرة واحدة'), 'Single-use precedence');
  check(DiscountTerms.fromJson({'maxDiscount': 0}).maxDiscountAmount == 0, 'Zero cap');
  check(DiscountTerms.fromJson({'campaignType': 'first_order'}).firstOrderOnly, 'Legacy first-order alias');
  check(StoreDiscount.fromJson({'type': 'fixedAmount', 'value': 1250.875}).displayValue
      == 'خصم 1250.875 د.ع', 'Fixed value precision');
  check(StoreDiscount.fromJson({}).termsSummary.isEmpty, 'Legacy missing terms');
  print('Discount model regression checks passed');
}
