import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/widgets/storefront_value.dart';
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
  testWidgets('list metadata shows agreement fee on the first frame while routing is pending', (t) async {
    final response=Completer<http.Response>();
    final p=StorefrontPricing(account:()=>'u',token:()=>'t',addressId:()=>'a',addressRevision:()=>'v',regionId:()=>'zone',listenToAddress:false,now:()=>DateTime.utc(2026,10,19),client:MockClient((_)=>response.future));
    final business=BusinessModel.fromJson({'businessId':'b','minimum_order':4000,'orderReceptionSettings':{'defaultPreparationMinutes':20},'storefrontDeliveryAgreements':[{'id':'contract','version':1,'effectiveFrom':'2026-10-19T00:00:00Z','effectiveTo':'2026-11-19T00:00:00Z','regionIds':['zone'],'deliveryFeeIqd':1500,'minimumOrderAmountIqd':7000}]});
    p.seedBusiness(business.id,business.metadata!);
    expect(p.minimumIqd('b',[]),7000);expect(business.averagePreparationMinutes,20);
    await t.pumpWidget(MaterialApp(home:StorefrontValue(branchId:'b',field:StorefrontField.fee,items:const[],pricing:p)));
    expect(find.text('1500 د.ع'),findsOneWidget);
    response.complete(http.Response(jsonEncode({'success':true,'preview':result('a')}),200));
    await t.pumpAndSettle();await t.pumpWidget(const SizedBox());p.dispose();
  });
  test('basket changes reuse only valid route information, never a different basket fee',()async{
    var address='a',revision='v1',owner='u',region='zone',clock=DateTime.utc(2026,10,19);
    var calls=0;
    final p=StorefrontPricing(account:()=>owner,token:()=>'t',addressId:()=>address,addressRevision:()=>revision,regionId:()=>region,listenToAddress:false,now:()=>clock,client:MockClient((_)async{calls++;return http.Response(jsonEncode({'success':true,'preview':result('a')}),200);}));
    await p.load('b',[]);
    final basket=[{'id':'item','quantity':2}];
    expect(p.peek('b',basket),isNull);expect(p.feeIqd('b',basket),isNull);
    expect(p.peekRoute('b')!.arrivalText,'24–29 دقيقة');expect(calls,1);
    region='outside';expect(p.peekRoute('b'),isNull);
    region='zone';revision='edited';expect(p.peekRoute('b'),isNull);
    revision='v1';address='other';expect(p.peekRoute('b'),isNull);
    address='a';owner='other';expect(p.peekRoute('b'),isNull);
    owner='u';clock=DateTime.utc(2026,10,20);expect(p.peekRoute('b'),isNull);p.dispose();
  });
  test('commercial terms show before route loading, follow region and dates, and restore original minimum',() {
    var address='a',region='zone',clock=DateTime.utc(2026,10,19);
    final p=StorefrontPricing(account:()=>'u',token:()=>'t',addressId:()=>address,addressRevision:()=>address,regionId:()=>region,listenToAddress:false,now:()=>clock);
    p.seedBusiness('b',{'minimumOrderAmountIqd':4000,'storefrontDeliveryAgreements':[{'id':'contract','version':1,'effectiveFrom':'2026-10-19T00:00:00.000Z','effectiveTo':'2026-11-19T00:00:00.000Z','regionIds':['zone'],'deliveryFeeIqd':1500,'minimumOrderAmountIqd':7000}]});
    expect(p.feeIqd('b',[]),1500);expect(p.minimumIqd('b',[]),7000);
    address='different';expect(p.feeIqd('b',[]),1500);
    region='outside';expect(p.feeIqd('b',[]),isNull);expect(p.minimumIqd('b',[]),4000);
    region='zone';clock=DateTime.utc(2026,11,19);expect(p.feeIqd('b',[]),isNull);expect(p.minimumIqd('b',[]),4000);p.dispose();
  });

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
