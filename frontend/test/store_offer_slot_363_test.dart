import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/store_offer_slot.dart';
import 'package:foodapp_user/widgets/store_offers_section.dart';

StoreOffer offer(
  String id, {
  String origin = 'merchant',
  String source = 'merchant',
  String kind = 'items',
  String? end,
}) => StoreOffer.fromJson({
  'id': id,
  'source': source,
  'origin': origin,
  'kind': kind,
  'title': 'خصم حقيقي',
  'type': 'percentage',
  'value': 40,
  'minimumOrder': 10000,
  'maximumSavings': 3000,
  if (end != null) 'endAt': end,
  'applicability': 'specificItems',
  'itemIds': ['p'],
});
void main() {
  test('creative separates real value, unit and scope for every offer type', () {
    StoreOffer value(Map<String, dynamic> extra) => StoreOffer.fromJson({'id':'x','source':'merchant','origin':'merchant','kind':'items','type':'percentage','value':40,...extra});
    final percentage = value({'calculationMode':'perItem'});
    expect(percentage.displayValue, '40'); expect(percentage.displayUnit, '٪');
    expect(percentage.displayCaption, 'خصم لكل قطعة');
    final fixed = value({'type':'fixed','value':1500,'kind':'order'});
    expect(fixed.displayUnit, 'د.ع'); expect(fixed.displayCaption, 'خصم على الطلب');
    final free = value({'type':'freeDelivery','kind':'delivery'});
    expect(free.displayValue, 'مجاني'); expect(free.displayUnit, '');
    expect(free.displayCaption, 'توصيل طلبك');
  });

  testWidgets(
    'image slot spotlight keeps every offer in a single horizontal rail',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StoreOffersSection(
                title: 'عروض المطعم',
                description: '',
                config: StoreOfferSlot.fromJson({
                  'presentation': 'image',
                  'style': 'spotlight',
                }),
                offers: [offer('a'), offer('b')],
                onDetails: (_) {},
                onBrowse: (_) {},
              ),
            ),
          ),
        ),
      );
      final actions = find.text('التفاصيل');
      expect(actions, findsNWidgets(2));
      expect(
        tester.getTopLeft(actions.at(0)).dy,
        tester.getTopLeft(actions.at(1)).dy,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'image-only without campaign artwork falls back to readable terms',
    (tester) async {
      expect(StoreOfferSlot.fromJson({}).presentation, 'card');
      final config = StoreOfferSlot.fromJson({'presentation': 'image'});
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StoreOffersSection(
                title: 'عروض المطعم',
                description: '',
                config: config,
                offers: [offer('a')],
                onDetails: (_) {},
                onBrowse: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('التفاصيل'), findsOneWidget);
      expect(find.text(offer('a').displayCaption), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'manual presentation cannot promote ineligible/missing/expired offers or collide by ID',
    () {
      final c = StoreOfferSlot.fromJson({
        'mode': 'manual',
        'refs': [
          {'source': 'platform', 'id': 'same'},
          {'source': 'merchant', 'id': 'same'},
          {'source': 'merchant', 'id': 'missing'},
        ],
      });
      final rows = c.select([
        offer('same'),
        offer('same', origin: 'platform', source: 'platform'),
        offer('expired', end: '2000-01-01'),
      ], DateTime(2026));
      expect(rows.map((o) => o.key), ['platform:same', 'merchant:same']);
    },
  );
  test(
    'source and benefit type filters intersect without changing campaign conditions',
    () {
      final c = StoreOfferSlot.fromJson({
        'sources': ['shared'],
        'kinds': ['order'],
      });
      final rows = c.select([
        offer('a'),
        offer('b', origin: 'shared', kind: 'order'),
        offer('c', origin: 'shared'),
      ], DateTime(2026));
      expect(rows.single.id, 'b');
      expect(rows.single.brief, contains('10,000'));
      expect(rows.single.brief, contains('3,000'));
    },
  );
  test('meal scope and one-goods-offer wording retained', () {
    final o = offer('a');
    expect(o.includes('p', 'c'), true);
    expect(o.includes('foreign', 'c'), false);
    expect(o.fullTerms, contains('عرض بضاعة واحد'));
  });
  for (final style in ['spotlight', 'carousel', 'list'])
    testWidgets(
      'offer slot $style fits narrow RTL and actions remain explicit',
      (tester) async {
        var details = 0, browse = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: StoreOffersSection(
                      title: 'عروض المطعم',
                      description: '',
                      config: StoreOfferSlot.fromJson({'style': style}),
                      offers: [offer('a'), offer('b', origin: 'shared')],
                      onDetails: (_) => details++,
                      onBrowse: (_) => browse++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(details, 0);
        expect(browse, 0);
        await tester.tap(find.text('شاهد الأصناف').first);
        expect(browse, 1);
        expect(details, 0);
        await tester.tap(find.text('التفاصيل').first);
        expect(details, 1);
        expect(tester.takeException(), isNull);
      },
    );
  testWidgets('no eligible offers means no empty promotional space', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StoreOffersSection(
          title: 'hidden',
          description: '',
          config: StoreOfferSlot.fromJson({}),
          offers: [offer('expired', end: '2000-01-01')],
          onDetails: (_) {},
          onBrowse: (_) {},
        ),
      ),
    );
    expect(find.text('hidden'), findsNothing);
  });
}
