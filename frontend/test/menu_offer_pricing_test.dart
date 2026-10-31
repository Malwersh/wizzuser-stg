import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/store_discount.dart';
import 'package:foodapp_user/services/menu_offer_pricing.dart';

void main() {
  test('projections are scoped by product branch price account and expiry', () {
    var now = DateTime.utc(2026, 10, 30);
    var user = 'a';
    final cache = MenuOfferPricing(now: () => now, account: () => user);
    addTearDown(cache.dispose);
    final offer = StoreDiscount(
      discountId: 'd',
      businessId: 'b',
      title: '',
      type: 'percentage',
      value: 20,
      calculationMode: 'perItem',
      itemPrices: [const MenuUnitPrice('p', 5000000, 4000000)],
      itemPricesValidUntil: now.add(const Duration(seconds: 60)),
    );
    cache.absorb('b', [offer]);
    expect(cache.price('b', 'p', 5000)?.unit.netFils, 4000000);
    expect(cache.price('other', 'p', 5000), isNull);
    expect(cache.price('b', 'q', 5000), isNull);
    expect(cache.price('b', 'p', 6000), isNull);
    user = 'other';
    expect(cache.price('b', 'p', 5000), isNull);
    cache.absorb('b', [offer]);
    now = now.add(const Duration(seconds: 60));
    expect(cache.price('b', 'p', 5000), isNull);
  });
  test('legacy basket discounts cannot supply unit projections', () {
    final cache = MenuOfferPricing();
    addTearDown(cache.dispose);
    cache.absorb('b', [
      StoreDiscount(
        discountId: 'd',
        businessId: 'b',
        title: '',
        type: 'fixedAmount',
        value: 500,
        itemPrices: [const MenuUnitPrice('p', 5000000, 4000000)],
        itemPricesValidUntil: DateTime.now().add(const Duration(seconds: 60)),
      ),
    ]);
    expect(cache.price('b', 'p', 5000), isNull);
  });
  test('malformed server prices never show a false saving', () {
    for (final net in [-1, 5000000, 6000000, 4.5])
      expect(
        MenuUnitPrice.fromJson({
          'productId': 'p',
          'originalUnitFils': 5000000,
          'netUnitFils': net,
        }),
        isNull,
      );
  });
}
