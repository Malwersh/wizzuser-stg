import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/platform_benefit.dart';
import 'package:foodapp_user/widgets/platform_benefits_sheet.dart';

Map<String, dynamic> record({String kind = 'FREE_DELIVERIES'}) => {
  'schemaVersion': 1,
  'id': 'benefit',
  'title': 'Platform reward',
  'description': 'Participating restaurants',
  'kind': kind,
  'startAt': '2026-01-01T00:00:00.000Z',
  'endAt': '2030-01-01T00:00:00.000Z',
  'amountIqd': kind == 'GOODS_AMOUNT' ? 7000 : 0,
  'maximumPerOrderIqd': 7000,
  'minimumGoodsIqd': 7000,
  'maximumRoadMeters': 10000,
  'granted': kind == 'GOODS_AMOUNT' ? 1 : 3,
  'reserved': 0,
  'used': 0,
  'remaining': kind == 'GOODS_AMOUNT' ? 1 : 3,
  'eligible': true,
  'reason': null,
  'branchIds': <String>[],
};
Widget app(Future<List<PlatformBenefit>> Function() loader) =>
    MaterialApp(home: Scaffold(body: PlatformBenefitsSheet(loader: loader)));
void main() {
  test('benefit balance cannot fabricate remaining uses', () {
    final data = record();
    data['remaining'] = 4;
    expect(() => PlatformBenefit.fromJson(data), throwsFormatException);
  });
  test('unknown and fractional entitlement schemas fail closed', () {
    for (final patch in [
      {'kind': 'WALLET_CREDIT'},
      {'remaining': 1.5},
      {'schemaVersion': 2},
    ])
      expect(
        () => PlatformBenefit.fromJson({...record(), ...patch}),
        throwsFormatException,
      );
  });
  testWidgets(
    'sheet displays remaining, in progress, used and free delivery terms',
    (t) async {
      await t.pumpWidget(app(() async => [PlatformBenefit.fromJson(record())]));
      await t.pumpAndSettle();
      expect(find.text('3 free deliveries remaining'), findsOneWidget);
      expect(
        find.text('Available: 3 • In progress: 0 • Used: 0'),
        findsOneWidget,
      );
      expect(find.textContaining('Support cap 7000 IQD'), findsOneWidget);
    },
  );
  testWidgets('goods amount is advertised as up to 7000, with no carry over', (
    t,
  ) async {
    await t.pumpWidget(
      app(() async => [PlatformBenefit.fromJson(record(kind: 'GOODS_AMOUNT'))]),
    );
    await t.pumpAndSettle();
    expect(find.text('Up to 7000 IQD off goods'), findsOneWidget);
    expect(
      find.text('One order only. Any unused amount does not carry over.'),
      findsOneWidget,
    );
  });
  testWidgets('unavailable feed can recover with retry', (t) async {
    var attempts = 0;
    await t.pumpWidget(
      app(() async {
        if (++attempts == 1) throw StateError('offline');
        return [PlatformBenefit.fromJson(record())];
      }),
    );
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Platform reward'), findsOneWidget);
  });
}
