import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/product_model.dart';
import 'package:foodapp_user/models/store_discount.dart';
import 'package:foodapp_user/services/menu_offer_pricing.dart';
import 'package:foodapp_user/widgets/store_menu_offers.dart';

void main() {
  test(
    'offers menu uses reduced item prices only and excludes stale, foreign and duplicate products',
    () {
      var now = DateTime.utc(2026, 11, 12);
      final pricing = MenuOfferPricing(
        now: () => now,
        account: () => 'customer',
      );
      addTearDown(pricing.dispose);
      ProductModel product(
        String id, {
        String branch = 'b',
        double price = 5000,
      }) => ProductModel(
        id: id,
        businessId: branch,
        categoryId: 'c',
        name: id,
        description: '',
        imageUrl: '',
        price: price,
        createdAt: now,
      );
      pricing.absorb('b', [
        StoreDiscount(
          discountId: 'd',
          businessId: 'b',
          title: '',
          type: 'percentage',
          value: 20,
          calculationMode: 'perItem',
          itemPrices: [const MenuUnitPrice('p', 5000000, 4000000)],
          itemPricesValidUntil: now.add(const Duration(seconds: 60)),
        ),
      ]);
      final products = [
        product('p'),
        product('p'),
        product('q'),
        product('p', branch: 'other'),
      ];
      expect(discountedMenuProducts(products, 'b', pricing).map((p) => p.id), [
        'p',
      ]);
      expect(
        discountedMenuProducts([product('p', price: 6000)], 'b', pricing),
        isEmpty,
      );
      now = now.add(const Duration(seconds: 60));
      expect(discountedMenuProducts(products, 'b', pricing), isEmpty);
    },
  );
}
