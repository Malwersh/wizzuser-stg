import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/models/home_filters.dart';
import 'package:foodapp_user/models/home_navigation.dart';
import 'package:foodapp_user/widgets/discovery/home_filter_strip.dart';

void main() {
  final now = DateTime.parse('2026-11-02T12:00:00Z'),
      settings = HomeFilters.defaults();
  BusinessModel b({
    Map<String, dynamic> meta = const {},
    double rating = 4.5,
  }) => BusinessModel(
    id: 'b',
    businessName: 'اختبار',
    address: '',
    businessPhotoUrl: '',
    businessType: 'restaurant',
    latitude: 32,
    longitude: 44,
    rating: rating,
    metadata: {'reviewCount': 2, ...meta},
  );
  HomeFilter f(String kind, num? value) => HomeFilter.fromJson({
    'id': kind,
    'kind': kind,
    'label': kind,
    'enabled': true,
    'value': value,
  });
  bool matches(
    HomeFilter filter, {
    BusinessModel? business,
    Map<String, dynamic>? route,
    double? fee,
    Map<String, dynamic>? price,
    String? tier,
    Map<String, dynamic> facts = const {},
  }) => matchesHomeFilter(
    filter,
    business ?? b(),
    facts: facts,
    route: route,
    fee: fee,
    price: price,
    priceTier: tier,
    settings: settings,
    now: now,
  );
  test(
    'activity and topic selectors are structurally separate and topics follow selected activity',
    () {
      final nav = HomeNavigation.fromJson({
        'enabled': true,
        'items': [
          {'id': 'all', 'label': 'الكل', 'kind': 'all'},
          {
            'id': 'r',
            'label': 'مطاعم',
            'kind': 'activity',
            'value': 'restaurant',
          },
          {
            'id': 'pizza',
            'label': 'بيتزا',
            'kind': 'cuisine',
            'value': 'pizza',
            'parentActivities': ['restaurant'],
          },
          {
            'id': 'groceries',
            'label': 'احتياجات البيت',
            'kind': 'cuisine',
            'value': 'groceries',
            'parentActivities': ['grocery'],
          },
        ],
      });
      expect(nav.activities.map((r) => r.id), ['all', 'r']);
      expect(nav.topicsFor('restaurant').map((r) => r.id), ['pizza']);
      expect(nav.topicsFor('grocery').map((r) => r.id), ['groceries']);
      expect(nav.topicsFor(null).length, 2);
    },
  );
  test(
    'fast delivery uses full arrival upper bound, never preparation alone or unknown estimates',
    () {
      expect(
        matches(
          f('fastDelivery', 30),
          route: {
            'preparationMinutes': 5,
            'arrivalMinutes': {'maximum': 40},
          },
        ),
        false,
      );
      expect(
        matches(
          f('fastDelivery', 30),
          route: {
            'preparationMinutes': 20,
            'arrivalMinutes': {'maximum': 30},
          },
        ),
        true,
      );
      expect(
        matches(f('fastDelivery', 30), route: {'preparationMinutes': 5}),
        false,
      );
      expect(matches(f('freeDelivery', null), fee: null), false);
      expect(matches(f('freeDelivery', null), fee: 0), true);
    },
  );
  test(
    'open now requires fresh canonical availability and rating excludes unrated stores',
    () {
      expect(matches(f('openNow', null)), false);
      expect(
        matches(
          f('openNow', null),
          business: b(
            meta: {
              'isAvailableNow': true,
              'availabilityCheckedAt': now.toIso8601String(),
            },
          ),
        ),
        true,
      );
      expect(
        matches(
          f('openNow', null),
          business: b(
            meta: {
              'isAvailableNow': true,
              'availabilityCheckedAt':
                  now.subtract(const Duration(minutes: 3)).toIso8601String(),
            },
          ),
        ),
        false,
      );
      expect(
        matches(f('rating', 4), business: b(meta: {'reviewCount': 0})),
        false,
      );
      expect(matches(f('rating', 4)), true);
    },
  );
  test(
    'price tiers use saved menu median and sample minimum, with no delivery-fee substitution',
    () {
      final price = {
        'medianIqd': 10000,
        'sampleCount': 4,
        'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
      };
      expect(
        matches(f('menuPrice', null), price: price, tier: 'medium', fee: 0),
        true,
      );
      expect(
        matches(f('menuPrice', null), price: price, tier: 'economy', fee: 0),
        false,
      );
      expect(
        matches(
          f('menuPrice', null),
          price: {...price, 'sampleCount': 2},
          tier: 'medium',
        ),
        false,
      );
      expect(matches(f('menuPrice', null), fee: 1500, tier: 'economy'), false);
    },
  );
  testWidgets(
    'filter strip remains compact and active option uses navy rather than gold',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: HomeFilterStrip(
                items: settings.items,
                selected: (f) => f.id == 'all',
                onTap: (f) => tapped = f.id,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('عروض'));
      expect(tapped, 'offers');
      expect(tester.takeException(), isNull);
    },
  );
}
