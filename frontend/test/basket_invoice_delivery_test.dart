import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/checkout_invoice_store.dart';
import 'package:foodapp_user/widgets/basket_invoice.dart';
import 'package:foodapp_user/services/storefront_pricing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

class EmptyInvoiceStore extends CheckoutInvoiceStore {
  EmptyInvoiceStore() : super(account: () => 'test');
  @override
  Map<String,dynamic>? basketRequest(String branch,List<Map<String,dynamic>> items,
      {String storeName='المطعم',String storeAddress='العنوان غير محدد'}) => invoiceRequest(
        branch:branch,items:items,address:{'id':'a','latitude':31.9,'longitude':44.4});
  void update() => notifyListeners();
}
void main() {
  testWidgets('waiting for shared invoice never mounts a second storefront pricing request', (t) async {
    final store=EmptyInvoiceStore();var fallbackBuilds=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:BasketInvoiceDelivery(
      branch:'b',items:const [{'id':'p','price':3000,'quantity':5}],store:store,
      fallback:Builder(builder:(_){fallbackBuilds++;return const Text('parallel request');}),
    ))));
    expect(find.text('بانتظار سعر التوصيل'),findsOneWidget);
    expect(fallbackBuilds,0);
    store.update();await t.pump();
    expect(fallbackBuilds,0);
    await t.pumpWidget(const SizedBox());store.dispose();
  });
  testWidgets('cart immediately reuses restaurant tariff without a second request; different address cannot reuse it', (t) async {
    final store=EmptyInvoiceStore();var calls=0;var address='a';
    var clock=DateTime.utc(2026,10,23);var mode='CALCULATED';
    final pricing=StorefrontPricing(account:()=>'test',token:()=>'t',addressId:()=>address,
      addressRevision:()=>address,listenToAddress:false,now:()=>clock,
      client:MockClient((_) async {calls++;return http.Response(jsonEncode({'success':true,'preview':{
        'schemaVersion':1,'kind':'STOREFRONT_PREVIEW','branchId':'b','addressId':'a',
        'expiresAt':'2026-10-24T00:00:00Z','pricingMode':mode,
        'customerDeliveryFee':{'currency':'IQD','scale':1000,'moneySchemaVersion':1,'minorAmount':1500000},
        'roadDistanceMeters':3100,'deliveryDurationSeconds':300,'preparationMinutes':20,
        'arrivalMinutes':{'minimum':25,'maximum':30}}}),200);}));
    await pricing.load('b',[]);
    await t.pumpWidget(MaterialApp(home:Scaffold(body:BasketInvoiceDelivery(
      branch:'b',items:const [{'id':'p','price':3000,'quantity':5}],store:store,pricing:pricing,
      fallback:const Text('parallel request'),
    ))));
    expect(find.textContaining('1,500'),findsOneWidget);
    expect(find.textContaining('تقديري'),findsOneWidget);
    expect(calls,1);
    address='other';store.update();await t.pump();
    expect(find.textContaining('1,500'),findsNothing);
    expect(calls,1);
    address='a';clock=DateTime.utc(2026,10,24);store.update();await t.pump();
    expect(find.textContaining('1,500'),findsNothing);
    clock=DateTime.utc(2026,10,23);mode='PROMOTION';
    await pricing.load('b',[],force:true);await t.pump();
    expect(find.textContaining('1,500'),findsNothing);
    expect(pricing.cachedDisplayFeeIqd('foreign',const []),isNull);
    await t.pumpWidget(const SizedBox());store.dispose();pricing.dispose();
  });

}
