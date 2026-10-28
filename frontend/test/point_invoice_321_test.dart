import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/point_invoice_321.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27);
  Map<String, dynamic> money(int n) => {
    'moneySchemaVersion': 1,
    'currency': 'IQD',
    'scale': 1000,
    'minorAmount': n * 1000,
  };
  Map<String, dynamic> request() => {
    'storeId': 'b',
    'items': [
      {'id': 'p', 'quantity': 4},
    ],
    'pricingPoint': {'latitude': 31.9, 'longitude': 44.4},
    'tip': 0,
  };
  http.Response result(Map r) => http.Response(
    jsonEncode({
      'success': true,
      'pointInvoice': {
        'kind': 'POINT_INVOICE',
        'schemaVersion': 1,
        'branchId': 'b',
        'point': r['pricingPoint'],
        'informationalOnly': true,
        'requiresFinalConfirmation': true,
        'expiresAt': now.add(const Duration(seconds: 100)).toIso8601String(),
        'goodsGross': money(12000),
        'discount': money(0),
        'serviceFee': money(500),
        'deliveryFee': money(1500),
        'driverTip': money(0),
        'customerTotal': money(14000),
      },
    }),
    200,
  );
  test(
    'complete amounts load using point and basket without address text; cache changes only with pricing inputs',
    () async {
      var calls = 0;
      final api = PointInvoice321(
        owner: () => 'owner',
        token: () async => 't',
        now: () => now,
        client: MockClient((r) async {
          calls++;
          final body = jsonDecode(r.body);
          expect(body.containsKey('deliveryAddress'), false);
          expect(body.containsKey('neighborhood'), false);
          expect(body['action'], 'preview_commercial_point');
          return result(body);
        }),
      );
      final r = request();
      await api.ensure(r);
      expect(api.peek(r)!['serviceFee']['minorAmount'], 500000);
      expect(api.peek(r)!['customerTotal']['minorAmount'], 14000000);
      await api.ensure(r);
      expect(calls, 1);
      final changed = request();
      changed['pricingPoint'] = {'latitude': 32.0, 'longitude': 44.4};
      expect(api.peek(changed), isNull);
      expect(api.peek({...r, 'tip': 500}), isNull);
      expect(api.peek({...r, 'discountId': 'new'}), isNull);
      api.dispose();
    },
  );
  test('late response after account change cannot leak invoice', () async {
    var owner = 'a';
    final gate = Completer<http.Response>();
    final api = PointInvoice321(
      owner: () => owner,
      token: () async => 't',
      now: () => now,
      client: MockClient((r) => gate.future),
    );
    final r = request(), task = api.ensure(request());
    await Future<void>.delayed(Duration.zero);
    owner = 'b';
    expect(api.peek(r), isNull);
    gate.complete(result(r));
    await task;
    expect(api.peek(r), isNull);
    api.dispose();
  });
  test('unbalanced server amounts never become an invoice', () async {
    final api = PointInvoice321(
      owner: () => 'owner',
      token: () async => 't',
      now: () => now,
      client: MockClient((r) async {
        final p = jsonDecode(result(request()).body);
        p['pointInvoice']['customerTotal'] = money(1);
        return http.Response(jsonEncode(p), 200);
      }),
    );
    await api.ensure(request());
    expect(api.peek(request()), isNull);
    expect(api.error(request()), isNotNull);
    api.dispose();
  });
  test(
    'cart and checkout share one priced scope despite different screen metadata',
    () async {
      var calls = 0;
      final api = PointInvoice321(
        owner: () => 'owner',
        token: () async => 't',
        now: () => now,
        client: MockClient((r) async {
          calls++;
          return result(jsonDecode(r.body));
        }),
      );
      final cart = {
        ...request(),
        'storeName': 'المطعم',
        'storeAddress': 'العنوان غير محدد',
      };
      final checkout = {
        ...request(),
        'storeName': 'اسم المطعم الحقيقي',
        'storeAddress': 'شارع المطعم',
      };
      await api.ensure(cart);
      expect(api.peek(checkout), isNotNull);
      await api.ensure(checkout);
      expect(calls, 1);
      api.dispose();
    },
  );
  test(
    'refresh near expiry retains the current valid invoice while one shared refresh is in flight',
    () async {
      var clock = now, calls = 0;
      final gate = Completer<http.Response>();
      final api = PointInvoice321(
        owner: () => 'owner',
        token: () async => 't',
        now: () => clock,
        client: MockClient((r) async {
          calls++;
          if (calls == 1) return result(jsonDecode(r.body));
          return gate.future;
        }),
      );
      final r = request();
      await api.ensure(r);
      clock = now.add(const Duration(seconds: 80));
      final a = api.warmRequest(r), b = api.warmRequest(r);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(api.peek(r), isNotNull);
      final reply = jsonDecode(result(r).body);
      reply['pointInvoice']['expiresAt'] =
          clock.add(const Duration(seconds: 100)).toIso8601String();
      gate.complete(http.Response(jsonEncode(reply), 200));
      await Future.wait([a, b]);
      expect(api.peek(r), isNotNull);
      api.dispose();
    },
  );
}
