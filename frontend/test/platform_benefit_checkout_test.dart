import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/order_service.dart';
void main() {
 test('delivery preview forwards stacking identities and keeps delivery savings separate from goods',() async {
  await http.runWithClient(() async {
   final result=await OrderService().validatePromoCode(code:'',platformDiscountId:'delivery',existingPlatformDiscountId:'goods',storeId:'branch',items:[{'id':'product','quantity':3}],orderTotal:10500,deliveryFee:1500);
   expect(result['valid'],true);expect(result['discount'],0);expect(result['deliveryBenefit'],true);expect(result['deliveryBenefitSavingAmount'],1500);
  },()=>MockClient((request)async{
   final body=jsonDecode(request.body);expect(body['platformDiscountId'],'delivery');expect(body['existingPlatformDiscountId'],'goods');
   return http.Response(jsonEncode({'valid':true,'discountAmount':0,'deliveryBenefit':true,'deliveryBenefitSavingAmount':1500}),200);
  }));
 });
 test('delivery preview rejects malformed or over-tariff savings instead of exposing an invalid price',() async {
  for(final saving in [-250,0,1750,125,'1500']){
   await http.runWithClient(()async{
    final result=await OrderService().validatePromoCode(code:'',platformDiscountId:'delivery',storeId:'branch',items:[{'id':'product','quantity':1}],orderTotal:3500,deliveryFee:1500);
    expect(result['valid'],false,reason:'invalid saving $saving');
   },()=>MockClient((_)async=>http.Response(jsonEncode({'valid':true,'discountAmount':0,'deliveryBenefit':true,'deliveryBenefitSavingAmount':saving}),200)));
  }
 });
 test('manual code identity reaches the server stacking check',() async {
  await http.runWithClient(()async{
   final result=await OrderService().validatePromoCode(code:'',platformDiscountId:'delivery',existingPromoCode:'MANUAL',storeId:'branch',items:[],orderTotal:3500,deliveryFee:1500);expect(result['valid'],false);
  },()=>MockClient((r)async{expect(jsonDecode(r.body)['existingPromoCode'],'MANUAL');return http.Response('{"valid":false,"message":"BENEFIT_STACKING_DENIED"}',409);}));
 });
}
