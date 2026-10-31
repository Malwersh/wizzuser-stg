import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/store_discount.dart';
import 'package:foodapp_user/models/discount_terms.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30);
  bool matches(
    StoreDiscount o, {
    String branch = 'b',
    String category = 'pizza',
    String item = 'p',
  }) => o.includesMenuItem(
    itemId: item,
    categoryId: category,
    branchId: branch,
    now: now,
  );
  test('item scope does not leak into other products or branches', () {
    const o = StoreDiscount(
      discountId: 'd',
      businessId: 'b',
      title: '',
      type: 'percentage',
      value: 20,
      applicability: 'specificItems',
      applicableItemIds: ['p'],
    );
    expect(matches(o), isTrue);
    expect(matches(o, item: 'other'), isFalse);
    expect(matches(o, branch: 'other'), isFalse);
  });
  test('category scope only includes matching category', () {
    const o = StoreDiscount(
      discountId: 'd',
      businessId: 'b',
      title: '',
      type: 'percentage',
      value: 20,
      applicability: 'specificCategories',
      terms: DiscountTerms(applicableCategoryIds: ['pizza']),
    );
    expect(matches(o), isTrue);
    expect(matches(o, category: 'burger'), isFalse);
  });
  test('basket discount is never treated as discounted menu item', () {
    const o = StoreDiscount(
      discountId: 'd',
      businessId: 'b',
      title: '',
      type: 'fixedAmount',
      value: 500,
      minimumOrderAmount: 6000,
    );
    expect(matches(o), isFalse);
  });
  test('expired and future discounts are omitted', () {
    for (final start in [true, false]) {
      final o = StoreDiscount(
        discountId: 'd',
        businessId: 'b',
        title: '',
        type: 'percentage',
        value: 20,
        applicability: 'specificItems',
        applicableItemIds: ['p'],
        validFrom: start ? now.add(const Duration(days: 1)) : null,
        validTo: start ? null : now,
      );
      expect(matches(o), isFalse);
    }
  });
}
