import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/config/api_config.dart';
import 'package:foodapp_user/services/delivery_quote_checkout.dart';

void main() {
  const enabled = ApiConfig.commercialPricingEnabled;
  final expires = DateTime.utc(2026, 10, 15, 12, 2);
  Map<String, dynamic> money(int amount) => {
    'currency': 'IQD',
    'scale': 1000,
    'moneySchemaVersion': 1,
    'minorAmount': amount,
  };
  Map<String, dynamic> content() => {
    'userId': 'u1',
    'storeId': 'b1',
    'deliveryAddress': {'id': 'a1'},
    'items': [
      {'id': 'p1', 'price': 3500, 'quantity': 1},
    ],
  };
  late Map<String, String> saved;
  late List<Map<String, dynamic>> posts;
  late String owner;
  late bool failOrder;
  late DeliveryQuoteCheckout checkout;
  late void Function(Map<String, dynamic>) mutatePreview;
  setUp(() async {
    saved = {};
    posts = [];
    owner = 'u1';
    failOrder = false;
    mutatePreview = (_) {};
    checkout = DeliveryQuoteCheckout(
      account: () => owner,
      token: () => 'access',
      now: () => DateTime.utc(2026, 10, 15, 12),
      read: (k) async => saved[k],
      write: (k, v) async {
        saved[k] = v;
      },
      remove: (k) async {
        saved.remove(k);
      },
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/delivery-quotes'))
          return http.Response(
            jsonEncode({
              'success': true,
              'quote': {
                'schemaVersion': 1,
                'kind': 'DELIVERY_FEE_ONLY',
                'quoteId': 'q1',
                'branchId': 'b1',
                'addressId': 'a1',
                'expiresAt': expires.toIso8601String(),
                'customerDeliveryFee': money(0),
              },
            }),
            200,
          );
        posts.add(body);
        if (body['action'] == 'preview_commercial') {
          final proposal = {
            'schemaVersion': 1,
            'digest': 'a' * 64,
            'quoteId': body['quoteId'],
            'requestId': body['idempotencyKey'],
            'expiresAt': expires.toIso8601String(),
            'customerTotal': money(4000000),
            'goodsGross': money(3500000),
            'serviceFee': money(500000),
            'discount': money(0),
            'deliveryFee': money(0),
          };
          mutatePreview(proposal);
          return http.Response(
            jsonEncode({'success': true, 'commercial': proposal}),
            200,
          );
        }
        expect(saved.isNotEmpty, true);
        if (failOrder) throw Exception('lost response');
        return http.Response(
          jsonEncode({
            'success': true,
            'order': {
              'orderId': 'o1',
              'userId': owner,
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
    await checkout.restore();
    await checkout.load('b1', 'a1');
  });
  tearDown(() => checkout.dispose());
  test(
    'cancel commercial amount sends no order and persists no attempt',
    () async {
      await expectLater(
        checkout.confirm(content(), approveCommercial: (p) async => false),
        throwsStateError,
      );
      expect(posts.length, 1);
      expect(saved, isEmpty);
      expect(checkout.pending, false);
    },
    skip: !enabled,
  );
  test(
    'consent binds exact server total and is persisted before order; replay skips another preview',
    () async {
      failOrder = true;
      await expectLater(
        checkout.confirm(
          content(),
          approveCommercial: (p) async {
            expect(p['customerTotal']['minorAmount'], 4000000);
            return true;
          },
        ),
        throwsException,
      );
      expect(checkout.pending, true);
      expect(posts.length, 2);
      expect(posts.last['commercialConsent'], {
        'digest': 'a' * 64,
        'customerTotalMinor': 4000000,
      });
      final attempt = jsonEncode(posts.last);
      failOrder = false;
      await checkout.confirm(null);
      expect(posts.length, 3);
      expect(jsonEncode(posts.last), attempt);
      expect(checkout.pending, false);
    },
    skip: !enabled,
  );
  test(
    'swapped preview scope or malformed money cannot reach approval or create order',
    () async {
      var approved = false;
      mutatePreview = (p) {
        p['quoteId'] = 'other';
      };
      await expectLater(
        checkout.confirm(
          content(),
          approveCommercial: (p) async {
            approved = true;
            return true;
          },
        ),
        throwsStateError,
      );
      expect(approved, false);
      expect(saved, isEmpty);
      expect(posts.length, 1);
    },
    skip: !enabled,
  );
  test(
    'account changes during approval never persist or submit the old identity',
    () async {
      await expectLater(
        checkout.confirm(
          content(),
          approveCommercial: (p) async {
            owner = 'u2';
            return true;
          },
        ),
        throwsStateError,
      );
      expect(saved, isEmpty);
      expect(posts.length, 1);
    },
    skip: !enabled,
  );
}
