import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/storefront_pricing.dart';

Map<String, dynamic> result(String address, {int fee = 1500000}) => {
  'schemaVersion': 1,
  'kind': 'STOREFRONT_PREVIEW',
  'branchId': 'b',
  'addressId': address,
  'expiresAt': '2026-10-20T00:00:00Z',
  'customerDeliveryFee': {
    'moneySchemaVersion': 1,
    'currency': 'IQD',
    'scale': 1000,
    'minorAmount': fee,
  },
  'roadDistanceMeters': 4500,
  'deliveryDurationSeconds': 540,
  'preparationMinutes': 15,
  'arrivalMinutes': {'minimum': 24, 'maximum': 29},
};
void main() {
  test('minimum has no invented default and supports explicit branch values',(){
    for(final value in [null,0])expect(StorefrontPreview({...result('a'),'minimumOrderAmountIqd':value}).minimumOrderAmountIqd,isNull);
    expect(StorefrontPreview({...result('a'),'minimumOrderAmountIqd':1500}).minimumOrderAmountIqd,1500);
    expect(()=>StorefrontPreview({...result('a'),'minimumOrderAmountIqd':-1}).minimumOrderAmountIqd,throwsFormatException);
  });
  test(
    'shared cache coalesces requests and preserves fixed/free fees, preparation and road distance',
    () async {
      var calls = 0;
      final p = StorefrontPricing(
        account: () => 'u',
        token: () => 't',
        addressId: () => 'a',
        addressRevision: () => 'v1',
        listenToAddress: false,
        now: () => DateTime.utc(2026, 10, 19),
        client: MockClient((r) async {
          calls++;
          expect(jsonDecode(r.body)['action'], 'storefront_preview');
          return http.Response(
            jsonEncode({'success': true, 'preview': result('a')}),
            200,
          );
        }),
      );
      final all = await Future.wait([p.load('b', []), p.load('b', [])]);
      expect(calls, 1);
      expect(all.first!.feeText, '1500 د.ع');
      expect(p.peek('b', [])!.distanceText, '4.5 كم');
      expect(all.first!.preparationText, 'نحو 15 دقيقة');
      expect(StorefrontPreview(result('a', fee: 0)).feeText, 'توصيل مجاني');
      await p.load('b', []);
      expect(calls, 1);
      p.dispose();
    },
  );
  test(
    'late old-address responses and same-ID address edits cannot replace current pricing',
    () async {
      var address = 'a', revision = 'v1';
      final old = Completer<http.Response>();
      final p = StorefrontPricing(
        account: () => 'u',
        token: () => 't',
        addressId: () => address,
        addressRevision: () => revision,
        listenToAddress: false,
        now: () => DateTime.utc(2026, 10, 19),
        client: MockClient((r) async {
          final a = jsonDecode(r.body)['addressId'];
          if (a == 'a') return old.future;
          return http.Response(
            jsonEncode({'success': true, 'preview': result('b')}),
            200,
          );
        }),
      );
      final first = p.load('b', []);
      await Future<void>.delayed(Duration.zero);
      address = 'b';
      revision = 'v2';
      await p.load('b', []);
      old.complete(
        http.Response(
          jsonEncode({'success': true, 'preview': result('a')}),
          200,
        ),
      );
      expect(await first, isNull);
      expect(p.peek('b', [])!.data['addressId'], 'b');
      revision = 'edited';
      expect(p.peek('b', []), isNull);
      p.dispose();
    },
  );
  test(
    'account, basket, and server failure never reuse a different scope or invent zero fees',
    () async {
      var owner = 'u';
      final p = StorefrontPricing(
        account: () => owner,
        token: () => 't',
        addressId: () => 'a',
        addressRevision: () => 'v',
        listenToAddress: false,
        now: () => DateTime.utc(2026, 10, 19),
        client: MockClient(
          (r) async => http.Response(jsonEncode({'success': false}), 503),
        ),
      );
      expect(await p.load('b', []), isNull);
      expect(p.peek('b', []), isNull);
      expect(p.error('b', []), isNotNull);
      final key = p.key('b', []);
      expect(
        p.key('b', [
          {'id': 'i', 'quantity': 1},
        ]),
        isNot(key),
      );
      owner = 'other';
      expect(p.key('b', []), isNot(key));
      p.dispose();
    },
  );
}
