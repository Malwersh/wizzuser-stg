import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/user_service.dart';
import 'package:foodapp_user/services/pending_offer.dart';
import 'package:foodapp_user/screens/coupons_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = UserService();
  setUp(() { service.resetData(); PendingOffer.clear(); });
  test('only backend offers populate coupons and retain their terms', () async {
    await http.runWithClient(service.syncUserData, () => MockClient((request) async {
      expect(request.url.path.endsWith('/promo-codes/active'), true);
      return http.Response(jsonEncode({'success': true, 'promos': [
        {'code': 'REAL', 'title': 'Real offer', 'type': 'percentage', 'value': 12.5, 'maxDiscountAmount': 1000}
      ]}), 200);
    }));
    expect(service.validCoupons.single['code'], 'REAL');
    expect(service.validCoupons.single['discount'], 'خصم 12.5%');
    expect(service.validCoupons.single['description'], contains('1000'));
    expect(service.couponsError, isNull);
    expect(service.currentPoints, 0);
    expect(service.availableRewards, isEmpty);
  });
  test('backend failure is distinct from an empty feed and clears stale offers', () async {
    await http.runWithClient(service.syncUserData, () => MockClient((_) async => http.Response('{}', 503)));
    expect(service.couponsError, isNotNull);
    expect(service.validCoupons, isEmpty);
    await http.runWithClient(service.syncUserData, () => MockClient((_) async => http.Response('{"success":true,"promos":[]}', 200)));
    expect(service.couponsError, isNull);
    expect(service.couponsLoading, false);
  });
  test('manual codes remain pending and cannot mint coupons or consume usage', () async {
    expect(await service.addCoupon(' save_10 '), true);
    expect(PendingOffer.current?.offer['code'], 'SAVE_10');
    expect(service.validCoupons, isEmpty);
    expect(await service.addCoupon('invalid code!'), false);
    expect(await service.useCoupon('SAVE_10'), false);
    expect(await service.addPoints(100), false);
    expect(await service.redeemReward('invented'), isNull);
    expect(service.currentPoints, 0);
    expect(service.usedCoupons, isEmpty);
  });
  testWidgets('coupon screen displays real feed terms without fabricated history', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: CouponsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Backend offer'), findsOneWidget);
      expect(find.textContaining('2500'), findsWidgets);
      expect(find.text('SAVE20'), findsNothing);
      await tester.tap(find.text('سجل الاستخدام'));
      await tester.pumpAndSettle();
      expect(find.text('سجل الاستخدام غير متاح حالياً'), findsOneWidget);
    }, () => MockClient((_) async => http.Response(jsonEncode({'success': true, 'promos': [
      {'code': 'REAL', 'title': 'Backend offer', 'type': 'percentage', 'value': 12.5, 'maxDiscountAmount': 2500}
    ]}), 200)));
  });
}
