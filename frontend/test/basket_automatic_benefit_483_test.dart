import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/basket_automatic_benefit.dart';
import 'package:foodapp_user/models/platform_benefit.dart';
import 'package:foodapp_user/services/pending_offer.dart';

final now = DateTime.utc(2026, 11, 9);
PlatformBenefit benefit({
  String branch = 'branch',
  DateTime? end,
  bool eligible = true,
  int remaining = 1,
  int minimum = 5000,
}) => PlatformBenefit(
  id: 'delivery',
  title: 'توصيل مجاني',
  description: '',
  kind: 'FREE_DELIVERIES',
  startAt: now.subtract(const Duration(days: 1)),
  endAt: end ?? now.add(const Duration(days: 1)),
  amountIqd: 0,
  maximumPerOrderIqd: 1500,
  minimumGoodsIqd: minimum,
  maximumRoadMeters: 10000,
  granted: 1,
  reserved: 0,
  used: 1 - remaining,
  remaining: remaining,
  eligible: eligible,
  reason: null,
  branchIds: [branch],
);
Map<String, dynamic> invoice({int fee = 1500000, int? total}) => {
  'expiresAt': now.add(const Duration(minutes: 1)).toIso8601String(),
  'goodsGross': {'minorAmount': 10000000},
  'deliveryFee': {'minorAmount': fee},
  'customerTotal': {'minorAmount': total ?? 10500000 + fee},
};
void main() {
  test(
    'expiry, audience, branch, exhausted balance and minimum are excluded before preview',
    () async {
      var calls = 0;
      final result = await selectAutomaticDeliveryBenefit(
        branch: 'branch',
        baseline: invoice(),
        benefits: [
          benefit(end: now),
          benefit(branch: 'other'),
          benefit(eligible: false),
          benefit(remaining: 0),
          benefit(minimum: 20000),
        ],
        current: () => true,
        clock: () => now,
        preview: (_) async {
          calls++;
          return invoice(fee: 0);
        },
      );
      expect(result, isNull);
      expect(calls, 0);
    },
  );
  test(
    'only actual lower server total matching delivery saving is selected',
    () async {
      final result = await selectAutomaticDeliveryBenefit(
        branch: 'branch',
        baseline: invoice(),
        benefits: [benefit()],
        current: () => true,
        clock: () => now,
        preview: (_) async => invoice(fee: 0),
      );
      expect(result!.savingMinor, 1500000);
      for (final response in [
        null,
        invoice(),
        invoice(fee: 0, total: 1),
        {...invoice(fee: 0), 'expiresAt': now.toIso8601String()},
      ]) {
        expect(
          await selectAutomaticDeliveryBenefit(
            branch: 'branch',
            baseline: invoice(),
            benefits: [benefit()],
            current: () => true,
            clock: () => now,
            preview: (_) async => response,
          ),
          isNull,
        );
      }
    },
  );
  test(
    'basket or account change while preview runs cancels selection',
    () async {
      var current = true;
      expect(
        await selectAutomaticDeliveryBenefit(
          branch: 'branch',
          baseline: invoice(),
          benefits: [benefit()],
          current: () => current,
          clock: () => now,
          preview: (_) async {
            current = false;
            return invoice(fee: 0);
          },
        ),
        isNull,
      );
    },
  );
  test(
    'automatic selection is bound to exact basket/point and removal prevents reapplying it',
    () {
      final items = <Map<String, dynamic>>[
        {'id': 'a', 'quantity': 1},
      ];
      final scope = PendingOffer.basketScope('branch', items, 31.9, 44.4);
      final selected = PendingOffer('', 'branch', {
        'automaticBasketScope': scope,
      }, DateTime.now().add(const Duration(days: 1)));
      expect(selected.matchesBasket('branch', items, 31.9, 44.4), true);
      expect(selected.matchesBasket('other', items, 31.9, 44.4), false);
      expect(selected.matchesBasket('branch', items, 32.0, 44.4), false);
      expect(
        selected.matchesBasket(
          'branch',
          [
            {'id': 'a', 'quantity': 2},
          ],
          31.9,
          44.4,
        ),
        false,
      );
      PendingOffer.select(selected);
      PendingOffer.clear();
      expect(PendingOffer.automaticDismissed(scope), true);
    },
  );
}
