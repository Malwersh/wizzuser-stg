import 'dart:convert';
import 'package:foodapp_user/services/scoped_checkout_attempt.dart';
import 'package:foodapp_user/services/order_service.dart';
import 'package:foodapp_user/models/address_model.dart';
import 'package:foodapp_user/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/delivery_quote_checkout.dart';

void main() {
  late Map<String, String> storage;
  late String? account;
  late DateTime clock;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) orders;
  late DeliveryQuoteCheckout checkout;
  Map<String, dynamic> quote({int fee = 0}) => {
    'schemaVersion': 1,
    'kind': 'DELIVERY_FEE_ONLY',
    'quoteId': 'q1',
    'branchId': 'b1',
    'addressId': 'a1',
    'expiresAt': clock.add(const Duration(minutes: 2)).toIso8601String(),
    'customerDeliveryFee': {
      'currency': 'IQD',
      'scale': 1000,
      'moneySchemaVersion': 1,
      'minorAmount': fee,
    },
  };
  http.Response success(http.Request r, [int status = 201]) {
    final body = jsonDecode(r.body);
    return http.Response(
      jsonEncode({
        'success': true,
        'order': {
          'orderId': 'o1',
          'userId': body['userId'],
          'deliveryQuote': {
            'quoteId': body['quoteId'],
            'requestId': body['idempotencyKey'],
          },
        },
      }),
      status,
    );
  }

  final content = {
    'userId': 'u1',
    'storeId': 'b1',
    'deliveryAddress': {'id': 'a1'},
    'items': [
      {'id': 'p1', 'price': 3500},
    ],
  };
  DeliveryQuoteCheckout make() => DeliveryQuoteCheckout(
    account: () => account,
    token: () => 'access',
    now: () => clock,
    read: (key) async => storage[key],
    write: (key, value) async {
      storage[key] = value;
    },
    remove: (key) async {
      storage.remove(key);
    },
    client: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/delivery-quotes')) {
        return http.Response(
          jsonEncode({'success': true, 'quote': quote()}),
          200,
        );
      }
      return orders(request);
    }),
  );
  setUp(() async {
    storage = {};
    account = 'u1';
    clock = DateTime.utc(2026, 10, 15);
    requests = [];
    orders = (r) async => success(r);
    checkout = make();
    await checkout.restore();
  });
  tearDown(() => checkout.dispose());
  test(
    'scoped test uses approved confirmation and restores it after lost reply',
    () async {
      final attempt = ScopedCheckoutAttempt.parse(
        jsonEncode({
          'schemaVersion': 1,
          'userId': 'u1',
          'branchId': 'b1',
          'requestId': '11111111-1111-4111-8111-111111111111',
        }),
        environment: 'staging',
        quotesEnabled: true,
        commercialEnabled: true,
        apiUrl:
            'https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging',
      );
      final scoped = DeliveryQuoteCheckout(
        account: () => account,
        token: () => 'access',
        now: () => clock,
        scopedAttempt: attempt,
        read: (key) async => storage[key],
        write: (key, value) async {
          storage[key] = value;
        },
        remove: (key) async {
          storage.remove(key);
        },
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/delivery-quotes')) {
            return http.Response(
              jsonEncode({'success': true, 'quote': quote()}),
              200,
            );
          }
          expect(jsonDecode(r.body)['idempotencyKey'], attempt!.requestId);
          throw http.ClientException('lost');
        }),
      );
      addTearDown(scoped.dispose);
      await scoped.restore();
      await scoped.load('foreign', 'a1');
      expect(scoped.error, contains('خارج عينة الاختبار'));
      expect(requests, isEmpty);
      await scoped.load('b1', 'a1');
      await expectLater(scoped.confirm(content), throwsException);
      final saved = storage.values.single;
      expect(jsonDecode(saved)['idempotencyKey'], attempt!.requestId);
      final restored = make();
      addTearDown(restored.dispose);
      await restored.restore();
      orders = (r) async {
        expect(r.body, saved);
        return success(r, 200);
      };
      await restored.confirm(null);
      expect(storage, isEmpty);
    },
  );
  test(
    'test build binding rejects production missing gates malformed IDs and extra keys',
    () {
      final row = {
        'schemaVersion': 1,
        'userId': 'u1',
        'branchId': 'b1',
        'requestId': '11111111-1111-4111-8111-111111111111',
      };
      ScopedCheckoutAttempt? parse(
        Map value, {
        String env = 'staging',
        bool enabled = true,
      }) => ScopedCheckoutAttempt.parse(
        jsonEncode(value),
        environment: env,
        quotesEnabled: enabled,
        commercialEnabled: true,
        apiUrl:
            'https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging',
      );
      expect(() => parse(row, env: 'production'), throwsFormatException);
      expect(() => parse(row, enabled: false), throwsFormatException);
      expect(() => parse({...row, 'requestId': '*'}), throwsFormatException);
      expect(() => parse({...row, 'extra': true}), throwsFormatException);
      expect(() => parse(row)!.check('u2', 'b1'), throwsStateError);
    },
  );
  test(
    'rate limit explains cooldown, makes no fallback order, and keeps attempt on retry',
    () async {
      final sent = <http.Request>[];
      final limited = DeliveryQuoteCheckout(
        account: () => account,
        token: () => 'access',
        now: () => clock,
        read: (key) async => storage[key],
        write: (key, value) async {
          storage[key] = value;
        },
        remove: (key) async {
          storage.remove(key);
        },
        client: MockClient((request) async {
          sent.add(request);
          if (sent.length == 1) {
            return http.Response(
              jsonEncode({
                'success': false,
                'code': 'QUOTE_RATE_LIMITED',
                'retryAfterSeconds': 30,
              }),
              429,
            );
          }
          return http.Response(
            jsonEncode({'success': true, 'quote': quote(fee: 2500000)}),
            200,
          );
        }),
      );
      addTearDown(limited.dispose);
      await limited.restore();
      await limited.load('b1', 'a1');
      expect(limited.error, contains('30 ثانية'));
      expect(limited.valid, false);
      await limited.load('b1', 'a1');
      limited.invalidate();
      await limited.load('b1', 'a2');
      expect(sent, hasLength(1));
      expect(storage, isEmpty);
      clock = clock.add(const Duration(seconds: 30));
      await limited.load('b1', 'a1');
      expect(sent, hasLength(2));
      expect(limited.quote!.fee, 2500);
      expect(limited.error, isNull);
    },
  );
  test(
    'retry after throttle reuses request ID and a new account clears cooldown',
    () async {
      final sent = <http.Request>[];
      final limited = DeliveryQuoteCheckout(
        account: () => account,
        token: () => 'access',
        now: () => clock,
        read: (key) async => null,
        write: (key, value) async {},
        remove: (key) async {},
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(
            jsonEncode({
              'success': false,
              'code': 'QUOTE_RATE_LIMITED',
              'retryAfterSeconds': 1,
            }),
            429,
          );
        }),
      );
      addTearDown(limited.dispose);
      await limited.restore();
      await limited.load('b1', 'a1');
      clock = clock.add(const Duration(seconds: 1));
      await limited.load('b1', 'a1');
      expect(
        jsonDecode(sent[0].body)['requestId'],
        jsonDecode(sent[1].body)['requestId'],
      );
      account = 'u2';
      await limited.restore();
      await limited.load('b1', 'a1');
      expect(sent, hasLength(3));
      expect(sent.last.headers['X-Customer-Id'], 'u2');
    },
  );
  test(
    'quote requests only branch address attempt with live account selector; zero fee retained',
    () async {
      await checkout.load('b1', 'a1');
      final request = requests.single, body = jsonDecode(request.body) as Map;
      expect(body.keys.toSet(), {'branchId', 'addressId', 'requestId'});
      expect(request.headers['Authorization'], 'Bearer access');
      expect(request.headers['X-Customer-Id'], 'u1');
      expect(checkout.valid, true);
      expect(checkout.quote!.fee, 0);
    },
  );
  test('persist before send; success removes attempt and price', () async {
    await checkout.load('b1', 'a1');
    orders = (r) async {
      expect(storage.values.single, r.body);
      return success(r);
    };
    await checkout.confirm(content);
    expect(storage, isEmpty);
    expect(checkout.pending, false);
    expect(checkout.valid, false);
  });
  test(
    'lost response and cold restart retry exact body even after quote expiry',
    () async {
      await checkout.load('b1', 'a1');
      orders = (_) async => throw http.ClientException('lost response');
      await expectLater(checkout.confirm(content), throwsException);
      final first = requests.last.body;
      expect(checkout.pending, true);
      clock = clock.add(const Duration(hours: 1));
      final restored = make();
      await restored.restore();
      expect(restored.pending, true);
      orders = (r) async {
        expect(r.body, first);
        return success(r, 200);
      };
      await restored.confirm(null);
      expect(storage, isEmpty);
      restored.dispose();
    },
  );
  test('expiry blocks a fresh confirmation without sending order', () async {
    await checkout.load('b1', 'a1');
    clock = clock.add(const Duration(minutes: 3));
    await expectLater(checkout.confirm(content), throwsStateError);
    expect(requests.length, 1);
    expect(storage, isEmpty);
  });
  test(
    'server invalidation releases attempt and requires a new displayed quote',
    () async {
      await checkout.load('b1', 'a1');
      orders =
          (_) async => http.Response(
            '{"success":false,"code":"QUOTE_INVALIDATED"}',
            409,
          );
      await checkout.confirm(content);
      expect(checkout.pending, false);
      expect(checkout.valid, false);
      await checkout.load('b1', 'a1');
      expect(
        jsonDecode(requests.first.body)['requestId'],
        isNot(jsonDecode(requests.last.body)['requestId']),
      );
    },
  );
  test(
    'unknown server failure keeps attempt; renewal cannot silently replace it',
    () async {
      await checkout.load('b1', 'a1');
      orders = (_) async => http.Response('{"error":"failed"}', 503);
      await checkout.confirm(content);
      final saved = storage.values.single;
      await checkout.load('b1', 'a2', renew: true);
      expect(checkout.pending, true);
      expect(storage.values.single, saved);
      expect(requests.length, 2);
    },
  );
  test(
    'scope denial preserves unresolved confirmation for reconciliation',
    () async {
      await checkout.load('b1', 'a1');
      orders = (_) async => throw http.ClientException('reply lost');
      await expectLater(checkout.confirm(content), throwsException);
      final pending = storage.values.single;
      orders =
          (_) async => http.Response(
            '{"success":false,"code":"FINANCE_ROLLOUT_OUT_OF_SCOPE"}',
            403,
          );
      await checkout.confirm(null);
      expect(checkout.pending, true);
      expect(storage.values.single, pending);
    },
  );
  test(
    'account change blocks saved attempt and another account cannot restore it',
    () async {
      await checkout.load('b1', 'a1');
      orders = (_) async => throw http.ClientException('lost');
      await expectLater(checkout.confirm(content), throwsException);
      account = 'u2';
      await expectLater(checkout.confirm(null), throwsStateError);
      final other = make();
      await other.restore();
      expect(other.pending, false);
      other.dispose();
      expect(storage.length, 1);
    },
  );
  test(
    'changed destination prevents confirm; stale price is cleared',
    () async {
      await checkout.load('b1', 'a1');
      await expectLater(
        checkout.confirm({
          ...content,
          'deliveryAddress': {'id': 'a2'},
        }),
        throwsStateError,
      );
      checkout.invalidate();
      expect(checkout.valid, false);
      expect(checkout.quote, isNull);
      expect(requests.length, 1);
    },
  );
  test('failed durable write prevents sending an order', () async {
    final service = DeliveryQuoteCheckout(
      account: () => account,
      token: () => 'access',
      now: () => clock,
      read: (_) async => null,
      write: (_, _) async => throw StateError('storage unavailable'),
      remove: (_) async {},
      client: MockClient((request) async {
        expect(request.url.path.endsWith('/delivery-quotes'), true);
        return http.Response(
          jsonEncode({'success': true, 'quote': quote()}),
          200,
        );
      }),
    );
    await service.restore();
    await service.load('b1', 'a1');
    await expectLater(service.confirm(content), throwsStateError);
    expect(service.pending, false);
    service.dispose();
  });
  test('malformed success keeps the attempt for server replay', () async {
    await checkout.load('b1', 'a1');
    orders =
        (_) async => http.Response(
          '{"success":true,"order":{"id":"foreign","userId":"u2"}}',
          200,
        );
    await expectLater(checkout.confirm(content), throwsFormatException);
    expect(checkout.pending, true);
    expect(storage.length, 1);
  });
  test(
    'another checkout discovers a pending attempt before it can send a new one',
    () async {
      final second = make();
      await second.restore();
      await second.load('b1', 'a1');
      await checkout.load('b1', 'a1');
      orders = (_) async => throw http.ClientException('lost');
      await expectLater(checkout.confirm(content), throwsException);
      final count = requests.length;
      await expectLater(second.confirm(content), throwsStateError);
      expect(requests.length, count);
      expect(second.pending, true);
      second.dispose();
    },
  );
  test(
    'known active-order rejection releases the uncommitted attempt',
    () async {
      await checkout.load('b1', 'a1');
      orders =
          (_) async => http.Response(
            '{"success":false,"activeOrder":{"orderId":"other"}}',
            409,
          );
      await checkout.confirm(content);
      expect(checkout.pending, false);
      expect(storage, isEmpty);
    },
  );
  test(
    'existing OrderService uses saved quoted attempt and minor-unit server totals',
    () async {
      await checkout.load('b1', 'a1');
      orders = (r) async {
        final body = jsonDecode(r.body);
        expect(body['deliveryFee'], 0);
        expect(body['quoteId'], 'q1');
        expect(body['idempotencyKey'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'success': true,
            'order': {
              'orderId': 'o1',
              'userId': 'u1',
              'storeId': 'b1',
              'storeName': 'Test',
              'items': [],
              'pricing': {
                'goodsSubtotal': 3500000,
                'deliveryFee': 0,
                'total': 3500125,
              },
              'total': 3500,
              'deliveryAddress': body['deliveryAddress'],
              'deliveryQuote': {
                'quoteId': body['quoteId'],
                'requestId': body['idempotencyKey'],
              },
            },
          }),
          201,
        );
      };
      final address = DetailedAddress(
        id: 'a1',
        userId: 'u1',
        name: 'Test',
        province: 'Test',
        district: 'Test',
        neighborhood: 'Test',
        landmark: '',
        fullAddress: 'Test address',
        latitude: 31.925,
        longitude: 44.457,
        addressType: 'home',
        createdAt: clock,
        updatedAt: clock,
      );
      final result = await OrderService().createOrder(
        storeId: 'b1',
        storeName: 'Test',
        cartItems: [
          {'id': 'p1', 'price': 1, 'quantity': 1},
        ],
        deliveryAddress: address,
        paymentMethod: PaymentMethod.cash,
        userId: 'u1',
        customerName: 'Test',
        customerPhone: 'synthetic',
        deliveryFee: 0,
        quoteCheckout: checkout,
      );
      expect(result['success'], true);
      final order = result['order'] as OrderModel;
      expect(order.total, 3500.125);
      expect(order.deliveryFee, 0);
      expect(order.subtotal, 3500);
    },
  );
  test('invalid money currency and precision are rejected', () {
    final row = quote(fee: -1);
    expect(() => DeliveryQuote.fromJson(row), throwsFormatException);
    row['customerDeliveryFee']['minorAmount'] = 1;
    row['customerDeliveryFee']['currency'] = 'SAR';
    expect(() => DeliveryQuote.fromJson(row), throwsFormatException);
  });
}
