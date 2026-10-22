import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/order_service.dart';

void main() {
  test('both offer previews forward branch option IDs without rejecting valid selections', () async {
    for (final platform in [true, false]) {
      await http.runWithClient(() async {
        final service=OrderService();
        final items=<Map<String,dynamic>>[{'id':'p','price':1,'quantity':1,'selected_options':{'sides':['salad']}}];
        final r=platform
          ? await service.validatePromoCode(code:'CODE',storeId:'b',items:items,orderTotal:1)
          : await service.validateDiscount(storeId:'b',discountId:'d',items:items,orderTotal:1);
        expect(r['valid'],true);
      },()=>MockClient((request)async{
        final body=jsonDecode(request.body);
        expect(body['items'][0]['selected_options'],{'sides':['salad']});
        return http.Response('{"valid":true,"discountAmount":250}',200);
      }));
    }
  });

  test('both promotion sources explain zero payable savings', () async {
    await http.runWithClient(() async {
      final service=OrderService();
      for(final platform in [true,false]) {
        final result=platform
          ? await service.validatePromoCode(code:'CODE',storeId:'b',items:[{'id':'p','quantity':1}],orderTotal:1000)
          : await service.validateDiscount(storeId:'b',discountId:'d',items:[{'id':'p','quantity':1}],orderTotal:1000);
        expect(result['valid'],false);
        expect(result['message'],contains('لا يحقق توفيراً'));
      }
    },()=>MockClient((_)async=>http.Response('{"valid":false,"message":"OFFER_NO_SAVINGS"}',409)));
  });

  test('catalog failures explain the basket problem for both promotion sources', () async {
    for (final platform in [true, false]) {
      await http.runWithClient(() async {
        final service = OrderService();
        final result = platform
            ? await service.validatePromoCode(code: 'CODE', storeId: 'b1', items: [{'id': 'p1', 'quantity': 1}], orderTotal: 3500)
            : await service.validateDiscount(storeId: 'b1', discountId: 'd1', items: [{'id': 'p1', 'quantity': 1}], orderTotal: 3500);
        expect(result['valid'], false);
        expect(result['message'], contains('أحد منتجات السلة'));
        expect(result['message'], isNot(contains('العرض غير متاح')));
      }, () => MockClient((_) async => http.Response(jsonEncode({'valid': false, 'message': 'GOODS_UNAVAILABLE'}), 503)));
    }
  });
  test('platform offers without codes send their platform ID for server validation', () async {
    await http.runWithClient(() async {
      final result=await OrderService().validatePromoCode(code:'',platformDiscountId:'platform-id',storeId:'b',items:[{'id':'p','quantity':1}],orderTotal:10000,addressId:'address');expect(result['valid'],true);
    },()=>MockClient((request)async{final body=jsonDecode(request.body);expect(body['platformDiscountId'],'platform-id');expect(body['addressId'],'address');expect(body['code'],'');return http.Response('{"valid":true,"discountAmount":2000,"lines":[]}',200);}));
  });
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
