import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/platform_benefit.dart';
import 'package:foodapp_user/services/basket_preparation.dart';
import 'package:foodapp_user/services/pending_offer.dart';

void main() {
  final items = <Map<String, dynamic>>[
    {'id': 'p', 'price': 12000, 'quantity': 1},
  ];
  late Map<String, Map<String, dynamic>> cache;
  late BasketPreparation service;
  late String owner;
  late bool eligible;
  late int previews;
  Completer<void>? gate;
  PlatformBenefit benefit() => PlatformBenefit(
    id: 'delivery',
    title: 'توصيل',
    description: '',
    kind: 'FREE_DELIVERIES',
    startAt: DateTime.now().subtract(const Duration(days: 1)),
    endAt: DateTime.now().add(const Duration(days: 1)),
    amountIqd: 0,
    maximumPerOrderIqd: 500,
    minimumGoodsIqd: 0,
    maximumRoadMeters: 10000,
    granted: 1,
    reserved: 0,
    used: 0,
    remaining: 1,
    eligible: eligible,
    reason: null,
    branchIds: ['branch'],
  );
  setUp(() {
    PendingOffer.clear(dismissAutomatic: false);
    cache = {};
    owner = 'a';
    eligible = true;
    previews = 0;
    gate = null;
    service = BasketPreparation(
      owner: () => owner,
      signedIn: () => true,
      request:
          (branch, items) => {
            'storeId': branch,
            'items': items,
            'pricingPoint': {'latitude': 32, 'longitude': 44},
            if (PendingOffer.current?.offer['source'] == 'merchant')
              'discountId': 'merchant',
          },
      loadBenefits: (_) async => [benefit()],
      ensure: (r) async {
        previews++;
        if (gate != null) await gate!.future;
        final fee = r['deliveryBenefitId'] == null ? 1500000 : 1000000;
        cache[jsonEncode(r)] = {
          'expiresAt':
              DateTime.now().add(const Duration(minutes: 2)).toIso8601String(),
          'goodsGross': {'minorAmount': 12000000},
          'deliveryFee': {'minorAmount': fee},
          'customerTotal': {'minorAmount': 12500000 + fee},
        };
      },
      peek: (r) => cache[jsonEncode(r)],
    );
  });
  tearDown(() => PendingOffer.clear(dismissAutomatic: false));
  test(
    'automatic -> merchant -> remove -> restore -> return keeps selection',
    () async {
      await service.prepare('branch', items, current: () => true);
      expect(PendingOffer.current!.offer['id'], 'delivery');
      PendingOffer.select(
        PendingOffer('', 'branch', {
          'source': 'merchant',
          'id': 'merchant',
        }, DateTime.now().add(const Duration(minutes: 5))),
      );
      await service.prepare('branch', items, current: () => true);
      expect(PendingOffer.current!.offer['id'], 'merchant');
      PendingOffer.clear(dismissAutomatic: false);
      await service.prepare('branch', items, current: () => true);
      expect(PendingOffer.current!.offer['id'], 'delivery');
      final restored = PendingOffer.current;
      await service.prepare('branch', items, current: () => true);
      expect(identical(PendingOffer.current, restored), true);
      expect(restored!.offer['savingMinor'], 500000);
    },
  );
  test(
    'removal does not restore a benefit that is no longer eligible',
    () async {
      eligible = false;
      await service.prepare('branch', items, current: () => true);
      expect(PendingOffer.current, isNull);
    },
  );
  test(
    'account or basket change during recovery cannot apply the old benefit',
    () async {
      gate = Completer<void>();
      final task = service.prepare('branch', items, current: () => true);
      owner = 'other';
      gate!.complete();
      await task;
      expect(PendingOffer.current, isNull);
      owner = 'a';
      var current = true;
      gate = Completer<void>();
      final second = service.prepare('branch', items, current: () => current);
      current = false;
      gate!.complete();
      await second;
      expect(PendingOffer.current, isNull);
    },
  );
  test(
    'concurrent cart and checkout recovery shares one preview sequence',
    () async {
      gate = Completer<void>();
      final a = service.prepare('branch', items, current: () => true);
      final b = service.prepare('branch', items, current: () => true);
      gate!.complete();
      await Future.wait([a, b]);
      expect(previews, 2);
      expect(PendingOffer.current!.offer['id'], 'delivery');
    },
  );
  test('a manual selection made during recovery is preserved', () async {
    gate = Completer<void>();
    final task = service.prepare('branch', items, current: () => true);
    PendingOffer.selectCode('MANUAL', null);
    gate!.complete();
    await task;
    expect(PendingOffer.current!.offer['code'], 'MANUAL');
  });
}
