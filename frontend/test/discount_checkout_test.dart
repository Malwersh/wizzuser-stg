import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/order_service.dart';

void main() {
  test(
    'promo preview sends branch, catalog selectors and actual zero delivery fee',
    () async {
      await http.runWithClient(
        () async {
          final r = await OrderService().validatePromoCode(
            code: 'CODE',
            storeId: 'b1',
            items: [
              {'id': 'p1', 'quantity': 1},
            ],
            orderTotal: 3500,
            deliveryFee: 0,
          );
          expect(r['valid'], true);
          expect(r['discount'], 0);
        },
        () => MockClient((request) async {
          final b = jsonDecode(request.body);
          expect(b['storeId'], 'b1');
          expect(b['deliveryFee'], 0);
          expect(b['items'][0]['id'], 'p1');
          return http.Response(
            jsonEncode({'valid': true, 'discountAmount': 0}),
            200,
          );
        }),
      );
    },
  );
  test('merchant preview preserves fractional IQD from server', () async {
    await http.runWithClient(
      () async {
        final r = await OrderService().validateDiscount(
          storeId: 'b1',
          discountId: 'd1',
          orderTotal: 3500,
          items: [
            {'id': 'p1', 'quantity': 1},
          ],
          deliveryFee: 1250.125,
        );
        expect(r['discount'], 0.001);
      },
      () => MockClient((request) async {
        final b = jsonDecode(request.body);
        expect(b['businessId'], 'b1');
        expect(b['deliveryFee'], 1250.125);
        return http.Response(
          jsonEncode({'valid': true, 'discountAmount': 0.001}),
          200,
        );
      }),
    );
  });
  test('missing amount never becomes successful zero discount', () async {
    await http.runWithClient(() async {
      final r = await OrderService().validatePromoCode(
        code: 'X',
        storeId: 'b1',
        items: [],
        orderTotal: 1,
      );
      expect(r['valid'], false);
    }, () => MockClient((_) async => http.Response('{"valid":true}', 200)));
  });
  test(
    'failed list request reports failure instead of successful empty offers',
    () async {
      await http.runWithClient(() async {
        await expectLater(
          OrderService().getStoreDiscounts('b1'),
          throwsStateError,
        );
      }, () => MockClient((_) async => http.Response('{}', 503)));
    },
  );
}
