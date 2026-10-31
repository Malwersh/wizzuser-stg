import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/checkout_invoice_store.dart';
import 'package:foodapp_user/services/delivery_quote_checkout.dart';

void main() {
  late String owner;
  late DateTime clock;
  late CheckoutInvoiceStore store;
  late int quotes, previews, orders, writes;
  Completer<void>? gate;
  bool fail = false;
  Map<String, dynamic> money(int v) => {
    'currency': 'IQD',
    'scale': 1000,
    'moneySchemaVersion': 1,
    'minorAmount': v,
  };
  Map<String, dynamic> request({
    int quantity = 4,
    int tip = 0,
    String address = 'a1',
    double latitude = 31.9,
    String? discount,
  }) => invoiceRequest(
    branch: 'b1',
    items: [
      {'id': 'p1', 'name': 'برجر', 'price': 3000, 'quantity': quantity},
    ],
    address: {
      'id': address,
      'latitude': latitude,
      'longitude': 44.4,
      'fullAddress': 'address',
    },
    tip: tip,
    discountId: discount,
  );
  DeliveryQuoteCheckout controller() => DeliveryQuoteCheckout(
    account: () => owner,
    token: () => 'test',
    now: () => clock,
    read: (_) async => null,
    write: (_, __) async {
      writes++;
    },
    remove: (_) async {},
    client: MockClient((r) async {
      final b = jsonDecode(r.body);
      if (r.url.path.endsWith('/delivery-quotes')) {
        quotes++;
        return http.Response(
          jsonEncode({
            'success': true,
            'quote': {
              'schemaVersion': 1,
              'kind': 'DELIVERY_FEE_ONLY',
              'quoteId': 'q$quotes',
              'branchId': 'b1',
              'addressId': b['addressId'],
              'expiresAt':
                  clock.add(const Duration(seconds: 120)).toIso8601String(),
              'customerDeliveryFee': money(2250000),
            },
          }),
          200,
        );
      }
      if (b['action'] == 'preview_commercial') {
        previews++;
        if (gate != null) await gate!.future;
        if (fail) return http.Response('{}', 503);
        final goods = (b['items'][0]['quantity'] as int) * 3000000,
            tip = (b['tip'] as int) * 1000;
        return http.Response(
          jsonEncode({
            'success': true,
            'commercial': {
              'schemaVersion': 1,
              'digest': 'a' * 64,
              'quoteId': b['quoteId'],
              'requestId': b['idempotencyKey'],
              'expiresAt':
                  clock.add(const Duration(seconds: 100)).toIso8601String(),
              'goodsGross': money(goods),
              'serviceFee': money(500000),
              'discount': money(0),
              'driverTip': money(tip),
              'deliveryFee': money(2250000),
              'customerTotal': money(goods + 2750000 + tip),
            },
          }),
          200,
        );
      }
      orders++;
      return http.Response('{}', 500);
    }),
  );
  setUp(() {
    owner = 'u1';
    clock = DateTime.utc(2026, 10, 23);
    quotes = 0;
    previews = 0;
    orders = 0;
    writes = 0;
    gate = null;
    fail = false;
    store = CheckoutInvoiceStore(
      account: () => owner,
      freshToken: () async => 'test',
      createCheckout: controller,
      now: () => clock,
    );
  });
  tearDown(() => store.dispose());
  test(
    'screens join one quote and invoice, repeated reads do no work',
    () async {
      final r = request();
      final results = await Future.wait([
        store.ensure(r),
        store.ensure(r),
        store.ensure(r),
      ]);
      expect(results.every((x) => x != null), true);
      expect(quotes, 1);
      expect(previews, 1);
      expect(
        (await store.ensure(r))!.proposal['serviceFee']['minorAmount'],
        500000,
      );
      expect(quotes, 1);
      expect(previews, 1);
      expect(orders, 0);
      expect(writes, 0);
    },
  );
  test(
    'quantity tip and discount changes reuse the scoped road quote',
    () async {
      await store.ensure(request());
      await store.ensure(request(quantity: 5));
      await store.ensure(request(tip: 100));
      await store.ensure(request(discount: 'd1'));
      expect(previews, 4);
      expect(quotes, 1);
      expect(
        store.peek(request())!.proposal['customerTotal']['minorAmount'],
        14750000,
      );
    },
  );
  test('address identity and coordinates invalidate road quote', () async {
    await store.ensure(request());
    await store.ensure(request(address: 'a2'));
    await store.ensure(request(latitude: 32));
    expect(quotes, 3);
    expect(previews, 3);
  });
  test(
    'account switch drops cache and ignores old in-flight response',
    () async {
      gate = Completer<void>();
      final first = store.ensure(request());
      while (previews == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      owner = 'u2';
      expect(store.peek(request()), null);
      gate!.complete();
      expect(await first, null);
      expect(store.peek(request()), null);
    },
  );
  test(
    'background failure retains valid invoice without extending expiry',
    () async {
      final r = request();
      final first = (await store.ensure(r))!;
      clock = clock.add(const Duration(seconds: 75));
      fail = true;
      expect(await store.ensure(r, refresh: true), null);
      expect(store.peek(r)!.proposal, first.proposal);
      expect(store.error(r), null);
      clock = clock.add(const Duration(seconds: 26));
      expect(store.peek(r), null);
    },
  );
  test(
    'closing review retains invoice without order pending storage or another preview',
    () async {
      final r = request(), prepared = (await store.ensure(request()))!;
      final c = controller();
      await c.restore();
      expect(c.adoptCachedQuote(prepared.quote, owner), true);
      for (var n = 0; n < 2; n++) {
        await expectLater(
          c.confirm(
            {...r, 'userId': owner},
            initialCommercialPreview: prepared.proposal,
            approveCommercial: (_) async => false,
          ),
          throwsA(isA<CommercialReviewCancelled>()),
        );
        expect(previews, 1);
        expect(quotes, 1);
        expect(orders, 0);
        expect(writes, 0);
        expect(c.pending, false);
        expect(c.busy, false);
        expect(
          store.peek(r)!.proposal['customerTotal']['minorAmount'],
          14750000,
        );
      }
      c.dispose();
    },
  );
  test('another account cannot adopt a cached quote', () async {
    final p = (await store.ensure(request()))!;
    final c = controller();
    await c.restore();
    owner = 'u2';
    expect(c.adoptCachedQuote(p.quote, 'u1'), false);
    c.dispose();
  });
  test(
    'prepared review sends only the final order and preserves unknown-outcome recovery',
    () async {
      final r = request(), prepared = (await store.ensure(request()))!;
      final c = controller();
      await c.restore();
      c.adoptCachedQuote(prepared.quote, owner);
      final response = await c.confirm(
        {...r, 'userId': owner},
        initialCommercialPreview: prepared.proposal,
        approveCommercial: (_) async => true,
      );
      expect(response.statusCode, 500);
      expect(previews, 1);
      expect(quotes, 1);
      expect(orders, 1);
      expect(writes, 1);
      expect(c.pending, true);
      c.dispose();
    },
  );
  test(
    'expired prepared review gets a fresh quote and preview before approval',
    () async {
      final r = request(), prepared = (await store.ensure(request()))!;
      clock = clock.add(const Duration(seconds: 101));
      final c = controller();
      await c.restore();
      c.adoptCachedQuote(prepared.quote, owner);
      await expectLater(
        c.confirm(
          {...r, 'userId': owner},
          initialCommercialPreview: prepared.proposal,
          approveCommercial: (_) async => false,
        ),
        throwsA(isA<CommercialReviewCancelled>()),
      );
      expect(previews, 2);
      expect(quotes, 2);
      expect(orders, 0);
      expect(writes, 0);
      c.dispose();
    },
  );
  test('different basket requests in flight share one route lookup', () async {
    await Future.wait([
      store.ensure(request(quantity: 3)),
      store.ensure(request(quantity: 4)),
    ]);
    expect(quotes, 1);
    expect(previews, 2);
    expect(orders, 0);
  });
  test(
    'address display formatting does not force another financial request',
    () async {
      final r = request();
      await store.ensure(r);
      final updated = {
        ...r,
        'deliveryAddress': {
          ...r['deliveryAddress'],
          'fullAddress': 'another display format',
        },
      };
      expect(await store.ensure(updated), isNotNull);
      expect(quotes, 1);
      expect(previews, 1);
    },
  );
  test(
    'repeated failed warmups wait for retry cooldown instead of request loops',
    () async {
      fail = true;
      final r = request();
      expect(await store.ensure(r), null);
      await Future.wait(List.generate(5, (_) => store.ensure(r)));
      expect(previews, 1);
      expect(quotes, 1);
      expect(store.error(r), isNotNull);
    },
  );
  test('automatic warmups do not retry a failed unchanged basket after cooldown', () async {
    fail = true;
    final r = request();
    await store.warmRequest(r);
    clock = clock.add(const Duration(seconds: 130));
    await store.warmRequest(r);
    await store.warmRequest(r);
    expect(previews, 1);
    fail = false;
    expect(await store.ensure(r, retry: true), isNotNull);
    expect(previews, 2);
  });
  test('changing quantity after failure gets one fresh invoice using cached route', () async {
    fail = true;
    await store.warmRequest(request());
    fail = false;
    await Future.wait([store.warmRequest(request(quantity: 5)),store.warmRequest(request(quantity: 5))]);
    expect(quotes, 1);
    expect(previews, 2);
    expect(store.peek(request(quantity: 5)), isNotNull);
    expect(orders, 0);
  });
  test('reopening a valid basket reuses invoice without additional requests', () async {
    await store.warmRequest(request());
    for (var i=0;i<5;i++) { await store.warmRequest(request()); }
    expect(quotes,1);
    expect(previews,1);
    expect(orders,0);
  });

}
