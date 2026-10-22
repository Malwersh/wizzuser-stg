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
  late int quoteFee;
  late bool failOrder;
  late bool activeConflict;
  String? previewError;
  late DeliveryQuoteCheckout checkout;
  late void Function(Map<String, dynamic>) mutatePreview;
  setUp(() async {
    saved = {};
    posts = [];
    owner = 'u1';
    quoteFee = 0;
    failOrder = false;
    activeConflict = false;
    previewError = null;
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
        if (request.url.path.endsWith('/delivery-quotes')) {
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
                'customerDeliveryFee': money(quoteFee),
              },
            }),
            200,
          );
        }
        posts.add(body);
        if (body['action'] == 'preview_commercial') {
          if (previewError != null) return http.Response(jsonEncode({'success':false,'code':previewError}),503);
          if (activeConflict)
            return http.Response(
              jsonEncode({
                'success': false,
                'activeOrder': {
                  'orderId': 'existing',
                  'status': 'ready_for_pickup',
                },
              }),
              409,
            );
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
          if ((body['tip'] ?? 0) > 0) {
            proposal['driverTip'] = money((body['tip'] as int) * 1000);
            proposal['discount'] = money(500000);
            proposal['customerTotal'] = money(3500000 + (body['tip'] as int) * 1000);
          }
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
    'scoped build binds the same approved attempt to preview consent and order',
    () async {
      const raw = String.fromEnvironment('FINANCE_TEST_CHECKOUT_ATTEMPT');
      final binding = jsonDecode(raw);
      await checkout.confirm(content(), approveCommercial: (_) async => true);
      expect(posts, hasLength(2));
      expect(posts.first['idempotencyKey'], binding['requestId']);
      expect(posts.last['idempotencyKey'], binding['requestId']);
      expect(posts.last['commercialConsent']['customerTotalMinor'], 4000000);
    },
    skip:
        !enabled ||
        const String.fromEnvironment('FINANCE_TEST_CHECKOUT_ATTEMPT').isEmpty,
  );
  test('goods benefit preserves fixed agreement 1500 and reviews 8500', () async {
    quoteFee=2000000;
    await checkout.load('b1','a1',renew:true);
    mutatePreview=(p){
      p['schemaVersion']=3;p['referenceDeliveryFee']=money(2000000);
      p['deliveryAgreement']={'policyId':'agreement','version':1,'termsHash':'b'*64,'kind':'FIXED_TARIFF'};
      p['goodsGross']=money(7000000);p['discount']=money(500000);p['serviceFee']=money(500000);p['deliveryFee']=money(1500000);p['customerTotal']=money(8500000);
    };
    await checkout.confirm({...content(),'platformDiscountId':'benefit-500','discount':500},approveCommercial:(p)async{
      expect(p['deliveryFee']['minorAmount'],1500000);expect(p['discount']['minorAmount'],500000);expect(p['customerTotal']['minorAmount'],8500000);return true;
    });
    expect(posts.last['platformDiscountId'],'benefit-500');expect(posts.last['commercialConsent']['customerTotalMinor'],8500000);
  },skip:!enabled);
  test('selected benefit stays bound to preview, consent and confirmation', () async {
    mutatePreview=(p){p['discount']=money(500000);p['customerTotal']=money(3500000);};
    await checkout.confirm({...content(), 'platformDiscountId':'benefit-500', 'discount':500}, approveCommercial: (_) async => true);
    expect(posts,hasLength(2));
    for(final request in posts) { expect(request['platformDiscountId'],'benefit-500'); }
    expect(posts.first['idempotencyKey'],posts.last['idempotencyKey']);
  },skip:!enabled);
  test('delivery benefit stays separate from a goods discount', () async {
    await checkout.confirm({...content(), 'deliveryBenefitId':'delivery-benefit'}, approveCommercial: (_) async => true);
    expect(posts,hasLength(2));
    for(final request in posts) { expect(request['deliveryBenefitId'],'delivery-benefit');expect(request['platformDiscountId'],isNull); }
  },skip:!enabled);
  test('cancelling review sends no order or reservation request', () async {
    await expectLater(checkout.confirm({...content(),'platformDiscountId':'benefit-500'},approveCommercial:(_)async=>false),throwsStateError);
    expect(posts,hasLength(1));expect(posts.single['action'],'preview_commercial');expect(saved,isEmpty);expect(checkout.pending,false);
  },skip:!enabled);
  test('a driver tip and goods discount both reach final consent and the persisted order', () async {
    await checkout.confirm({...content(),'tip':500},approveCommercial:(proposal) async {
      expect(proposal['discount']['minorAmount'],500000);
      expect(proposal['driverTip']['minorAmount'],500000);
      expect(proposal['customerTotal']['minorAmount'],4000000);
      return true;
    });
    expect(posts,hasLength(2));expect(posts.last['tip'],500);
    expect(posts.last['commercialConsent']['customerTotalMinor'],4000000);
  },skip:!enabled);
  test('unavailable delivery policy explains failure before consent and never creates an order', () async {
    previewError='DELIVERY_POLICY_UNAVAILABLE';var approvals=0;
    await expectLater(checkout.confirm(content(),approveCommercial:(_) async {approvals++;return true;}),
      throwsA(isA<StateError>().having((e)=>e.message,'message',contains('لم يُرسل الطلب'))));
    expect(approvals,0);expect(posts,hasLength(1));expect(saved,isEmpty);expect(checkout.pending,false);
  },skip:!enabled);
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
      activeConflict = false;
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
  test(
    'active order at preview retains its real reason and sends no new order',
    () async {
      activeConflict = true;
      await expectLater(
        checkout.confirm(content(), approveCommercial: (_) async => true),
        throwsA(isA<ActiveCheckoutOrder>()),
      );
      expect(posts, hasLength(1));
      expect(saved, isEmpty);
      expect(checkout.pending, false);
    },
    skip: !enabled,
  );

  test(
    'reduced delivery preview reaches approval and submits the same consent',
    () async {
      quoteFee = 3100000;
      await checkout.load('b1', 'a1', renew: true);
      mutatePreview = (p) {
        p['schemaVersion'] = 2;
        p['referenceDeliveryFee'] = money(3100000);
        p['deliveryFee'] = money(1500000);
        p['customerTotal'] = money(5500000);
      };
      int? displayed;
      await checkout.confirm(
        content(),
        approveCommercial: (p) async {
          displayed = p['deliveryFee']['minorAmount'];
          return true;
        },
      );
      expect(displayed, 1500000);
      expect(posts, hasLength(2));
      expect(posts.last['commercialConsent']['customerTotalMinor'], 5500000);
      expect(saved, isEmpty);
    },
    skip: !enabled,
  );
}
