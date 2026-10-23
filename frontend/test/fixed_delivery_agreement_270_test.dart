import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/delivery_quote_checkout.dart';

Map<String,dynamic> money(int n)=>{'moneySchemaVersion':1,'currency':'IQD','scale':1000,'minorAmount':n};
Map<String,dynamic> proposal(int reference)=>{
  'schemaVersion':3,'referenceDeliveryFee':money(reference),
  'deliveryAgreement':{'policyId':'DLV-TEST','version':1,'termsHash':'b'*64,'kind':'FIXED_TARIFF'},
  'goodsGross':money(7000000),'discount':money(500000),'serviceFee':money(500000),
  'deliveryFee':money(1500000),'driverTip':money(500000),'customerTotal':money(9000000),
};
void main(){
  for(final reference in [1000000,1500000,2500000]){
    test('fixed 1500 agreement survives reference $reference, discount, tip and final confirmation',()async{
      final saved=<String,String>{};var previews=0,orders=0,approvals=0;
      final clock=DateTime.utc(2026,10,21,12);
      final service=DeliveryQuoteCheckout(account:()=> 'u1',token:()=> 'access',now:()=>clock,
        read:(k)async=>saved[k],write:(k,v)async{saved[k]=v;},remove:(k)async{saved.remove(k);},
        client:MockClient((request)async{
          final body=jsonDecode(request.body);
          if(request.url.path.endsWith('/delivery-quotes'))return http.Response(jsonEncode({'success':true,'quote':{
            'schemaVersion':1,'kind':'DELIVERY_FEE_ONLY','quoteId':'q1','branchId':'b1','addressId':'a1',
            'expiresAt':clock.add(const Duration(minutes:2)).toIso8601String(),'customerDeliveryFee':money(reference)}}),200);
          if(body['action']=='preview_commercial'){
            previews++;return http.Response(jsonEncode({'success':true,'commercial':{...proposal(reference),
              'quoteId':body['quoteId'],'requestId':body['idempotencyKey'],'digest':'a'*64,
              'expiresAt':clock.add(const Duration(minutes:2)).toIso8601String()}}),200);
          }
          orders++;expect(saved,isNotEmpty);expect(approvals,1);expect(body['tip'],500);
          expect(body['commercialConsent']['customerTotalMinor'],9000000);
          return http.Response(jsonEncode({'success':true,'order':{'orderId':'o1','userId':'u1',
            'deliveryQuote':{'quoteId':body['quoteId'],'requestId':body['idempotencyKey']}}}),201);
        }));
      await service.restore();await service.load('b1','a1');
      await service.confirm({'userId':'u1','storeId':'b1','deliveryAddress':{'id':'a1'},'tip':500,'discountId':'d1','items':[{'id':'p1','quantity':2}]},
        approveCommercial:(p)async{approvals++;expect(p['deliveryFee']['minorAmount'],1500000);expect(p['discount']['minorAmount'],500000);expect(p['driverTip']['minorAmount'],500000);return true;});
      expect(previews,1);expect(orders,1);expect(saved,isEmpty);service.dispose();
    });
  }
  test('fixed delivery requires explicit valid agreement and exact totals; malformed proof cannot bypass tariff checks',(){
    final p=proposal(1500000);validateCommercialCheckoutAmounts(p,1500000);
    for(final patch in [
      {'deliveryAgreement':null},
      {'deliveryAgreement':{...(p['deliveryAgreement'] as Map),'kind':'NORMAL'}},
      {'deliveryAgreement':{...(p['deliveryAgreement'] as Map),'termsHash':'changed'}},
      {'deliveryAgreement':{...(p['deliveryAgreement'] as Map),'version':0}},
      {'referenceDeliveryFee':money(2500000)},
      {'customerTotal':money(8500000)},
      {'driverTip':money(1000000)},
      {'deliveryAgreement':{...(p['deliveryAgreement'] as Map),'kind':'FREE'}},
    ]){expect(()=>validateCommercialCheckoutAmounts({...p,...patch},1500000),throwsFormatException);}
    expect(()=>validateCommercialCheckoutAmounts({...p,'schemaVersion':2},1500000),throwsFormatException);
    validateCommercialCheckoutAmounts({...p,'schemaVersion':1},1500000);
  });
}
