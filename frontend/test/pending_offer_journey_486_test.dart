import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/pending_offer.dart';

void main() {
  tearDown(() => PendingOffer.clear(dismissAutomatic: false));
  test(
    'navigation metadata and JSON key ordering do not remove a delivery selection',
    () {
      final items = <Map<String, dynamic>>[
        {
          'id': 'pizza',
          'quantity': 1,
          'price': 12000,
          'name': 'بيتزا',
          'store_name': 'مطعم',
        },
      ];
      final scope = PendingOffer.basketScope('branch', items, 32, 44);
      final selected = PendingOffer('', 'branch', {
        'source': 'platform',
        'id': 'delivery',
        'automaticBasketScope': scope,
      }, DateTime.now().add(const Duration(minutes: 5)));
      PendingOffer.select(selected);
      final restored = <Map<String, dynamic>>[
        {
          'store_name': 'اسم محدّث',
          'name': 'بيتزا',
          'price': 12000,
          'quantity': 1.0,
          'id': 'pizza',
        },
      ];
      expect(
        PendingOffer.current!.matchesBasket('branch', restored, 32.0, 44.0),
        true,
      );
      expect(PendingOffer.current!.automaticDelivery, true);
      expect(
        PendingOffer.current!.matchesBasket(
          'branch',
          [
            {...items.first, 'quantity': 2},
          ],
          32,
          44,
        ),
        false,
      );
      expect(
        PendingOffer.current!.matchesBasket('branch', items, 32.01, 44),
        false,
      );
      expect(
        PendingOffer.current!.matchesBasket('different', items, 32, 44),
        false,
      );
    },
  );
  test('a changed customization invalidates the exact selection', () {
    final items = <Map<String, dynamic>>[
      {
        'id': 'pizza',
        'price': 12000,
        'quantity': 1,
        'selected_options': {
          'size': ['small'],
        },
      },
    ];
    final p = PendingOffer('', 'branch', {
      'automaticBasketScope': PendingOffer.basketScope('branch', items, 32, 44),
    }, DateTime.now().add(const Duration(minutes: 5)));
    expect(
      p.matchesBasket(
        'branch',
        [
          {
            ...items.first,
            'selected_options': {
              'size': ['large'],
            },
          },
        ],
        32,
        44,
      ),
      false,
    );
  });
  test('context invalidation is not an explicit user dismissal', () {
    final scope = PendingOffer.basketScope('new-branch', [], 32, 44);
    PendingOffer.select(
      PendingOffer('', 'new-branch', {
        'automaticBasketScope': scope,
      }, DateTime.now().add(const Duration(minutes: 5))),
    );
    PendingOffer.clear(dismissAutomatic: false);
    expect(PendingOffer.automaticDismissed(scope), false);
  });
  test(
    'validated coupon can preserve a server-approved companion delivery identity',
    () {
      PendingOffer.selectCode('CODE', null, deliveryBenefitId: 'delivery');
      expect(PendingOffer.current!.offer['code'], 'CODE');
      expect(PendingOffer.current!.offer['deliveryBenefitId'], 'delivery');
      expect(PendingOffer.current!.automaticDelivery, false);
    },
  );
}
