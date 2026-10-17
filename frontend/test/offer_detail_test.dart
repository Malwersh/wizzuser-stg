import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/models/home_slide.dart';
import 'package:foodapp_user/screens/offer_detail_screen.dart';
import 'package:foodapp_user/services/pending_offer.dart';
void main(){
 test('expired selections cannot carry an offer into checkout',(){PendingOffer.select(PendingOffer('slide','merchant',{'id':'offer'},DateTime(2000)));expect(PendingOffer.current,isNull);});
 testWidgets('offer journey shows terms and eligible products then carries selected merchant to shopping',(tester)async{
  String? opened;
  await http.runWithClient(()async{
   await tester.pumpWidget(MaterialApp(home:OfferDetailScreen(slide:HomeSlide(id:'s',title:'Offer',imageUrl:'https://example.test/image',imageVersion:'1',actionType:'campaign',targetId:'o',endAt:DateTime(2100)),openMerchant:(id)async{opened=id;})));
   await tester.pumpAndSettle();expect(find.text('Central offer'),findsOneWidget);expect(find.text('المتجر'),findsOneWidget);
   await tester.tap(find.text('المتجر'));await tester.pumpAndSettle();expect(find.text('Burger'),findsOneWidget);
   await tester.tap(find.text('استخدم العرض وتسوق'));await tester.pumpAndSettle();expect(opened,'m');expect(PendingOffer.current?.offer['id'],'o');expect(PendingOffer.current?.merchantId,'m');PendingOffer.clear();
  },()=>MockClient((request)async=>http.Response(jsonEncode({'offer':{'id':'o','source':'platform','title':'Central offer','description':'Terms','type':'percentage','value':20,'minimumOrder':10000,'endAt':'2100-01-01T00:00:00Z','applicability':'specificItems'},'merchants':[{'id':'m','name':'المتجر'}],'products':request.url.queryParameters['merchantId']==null?[]:[{'id':'p','name':'Burger','price':10000}]}),200,headers:{'content-type':'application/json; charset=utf-8'})));
 });
}
