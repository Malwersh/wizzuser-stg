import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/config/api_config.dart';
import 'package:foodapp_user/services/delivery_quote_checkout.dart';

void main() {
  test('address change queues a fresh quote and discards the old in-flight result',()async{
    final gate=Completer<void>();final addresses=<String>[];
    final service=DeliveryQuoteCheckout(account:()=>'u1',token:()=>'t',now:()=>DateTime.utc(2026,10,19),read:(_)async=>null,write:(_,__)async{},remove:(_)async{},client:MockClient((r)async{
      final input=jsonDecode(r.body);final address=input['addressId'] as String;addresses.add(address);if(address=='a1')await gate.future;
      return http.Response(jsonEncode({'success':true,'quote':{'schemaVersion':1,'kind':'DELIVERY_FEE_ONLY','quoteId':input['requestId'],'branchId':'b1','addressId':address,'expiresAt':'2026-10-20T00:00:00Z','customerDeliveryFee':{'moneySchemaVersion':1,'currency':'IQD','scale':1000,'minorAmount':address=='a1'?1000000:2000000}}}),200);
    }));
    await service.restore();final old=service.load('b1','a1');await Future<void>.delayed(Duration.zero);service.invalidate();final fresh=service.load('b1','a2');gate.complete();await Future.wait([old,fresh]);expect(addresses,['a1','a2']);expect(service.quote!.addressId,'a2');expect(service.quote!.fee,2000);service.dispose();
  });

  test(
    'refresh retains displayed fee and review joins the same in-flight request',
    () async {
      var clock = DateTime.utc(2026, 10, 18);
      final gate = Completer<void>();
      var requests = 0;
      final service = DeliveryQuoteCheckout(
        account: () => 'u1',
        token: () => 't',
        now: () => clock,
        read: (_) async => null,
        write: (_, __) async {},
        remove: (_) async {},
        client: MockClient((r) async {
          requests++;
          if (requests == 2) await gate.future;
          return http.Response(
            jsonEncode({
              'success': true,
              'quote': {
                'schemaVersion': 1,
                'kind': 'DELIVERY_FEE_ONLY',
                'quoteId': 'q$requests',
                'branchId': 'b1',
                'addressId': 'a1',
                'expiresAt':
                    clock.add(const Duration(minutes: 2)).toIso8601String(),
                'customerDeliveryFee': money(2000000),
              },
            }),
            200,
          );
        }),
      );
      await service.restore();
      await service.load('b1', 'a1');
      clock = clock.add(const Duration(seconds: 101));
      final refresh = service.refreshIfNeeded('b1', 'a1');
      expect(service.busy, true);
      expect(service.quote!.fee, 2000);
      expect(service.valid, true);
      var reviewed = false;
      final review = service
          .ensureFresh('b1', 'a1')
          .then((_) => reviewed = true);
      await Future<void>.delayed(Duration.zero);
      expect(reviewed, false);
      expect(requests, 2);
      gate.complete();
      await refresh;
      await review;
      expect(requests, 2);
      expect(service.valid, true);
      service.dispose();
    },
  );

  for (final priceChanges in [false, true]) {
    test(
      'expiry while customer reviews renews internally; priceChanges=$priceChanges',
      () async {
        var clock = DateTime.utc(2026, 10, 18);
        var quotes = 0, reviews = 0, orders = 0;
        final storage = <String, String>{};
        final ids = <String>[];
        final service = DeliveryQuoteCheckout(
          account: () => 'u1',
          token: () => 't',
          now: () => clock,
          read: (k) async => storage[k],
          write: (k, v) async {
            storage[k] = v;
          },
          remove: (k) async {
            storage.remove(k);
          },
          client: MockClient((r) async {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            final fee = priceChanges && quotes > 1 ? 2500000 : 2000000;
            if (r.url.path.endsWith('/delivery-quotes')) {
              quotes++;
              final newFee = priceChanges && quotes > 1 ? 2500000 : 2000000;
              return http.Response(
                jsonEncode({
                  'success': true,
                  'quote': {
                    'schemaVersion': 1,
                    'kind': 'DELIVERY_FEE_ONLY',
                    'quoteId': 'q$quotes',
                    'branchId': 'b1',
                    'addressId': 'a1',
                    'expiresAt':
                        clock.add(const Duration(minutes: 2)).toIso8601String(),
                    'customerDeliveryFee': money(newFee),
                  },
                }),
                200,
              );
            }
            ids.add(body['idempotencyKey']);
            if (body['action'] == 'preview_commercial')
              return http.Response(
                jsonEncode({
                  'success': true,
                  'commercial': {
                    'schemaVersion': 1,
                    'digest': (quotes == 1 ? 'a' : 'b') * 64,
                    'quoteId': body['quoteId'],
                    'requestId': body['idempotencyKey'],
                    'expiresAt':
                        clock.add(const Duration(minutes: 2)).toIso8601String(),
                    'goodsGross': money(7000000),
                    'discount': money(0),
                    'serviceFee': money(500000),
                    'deliveryFee': money(fee),
                    'customerTotal': money(7500000 + fee),
                  },
                }),
                200,
              );
            orders++;
            expect(storage, isNotEmpty);
            expect(body['quoteId'], 'q2');
            expect(body['commercialConsent']['digest'], 'b' * 64);
            return http.Response(
              jsonEncode({
                'success': true,
                'order': {
                  'orderId': 'o1',
                  'userId': 'u1',
                  'deliveryQuote': {
                    'quoteId': body['quoteId'],
                    'requestId': body['idempotencyKey'],
                  },
                },
              }),
              201,
            );
          }),
        );
        await service.restore();
        await service.load('b1', 'a1');
        final response = await service.confirm(
          {
            'userId': 'u1',
            'storeId': 'b1',
            'deliveryAddress': {'id': 'a1'},
            'items': [],
          },
          approveCommercial: (p) async {
            reviews++;
            if (reviews == 1) clock = clock.add(const Duration(minutes: 3));
            return true;
          },
        );
        expect(response.statusCode, 201);
        expect(quotes, 2);
        expect(orders, 1);
        expect(reviews, priceChanges ? 2 : 1);
        expect(ids.toSet().length, 1);
        expect(storage, isEmpty);
        service.dispose();
      },
      skip: !ApiConfig.commercialPricingEnabled,
    );
  }
}

Map<String, dynamic> money(int n) => {
  'currency': 'IQD',
  'scale': 1000,
  'moneySchemaVersion': 1,
  'minorAmount': n,
};
