import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/account_overview.dart';
void main(){
 for(final width in [320.0,390.0]){
  testWidgets('account identity and three working shortcuts fit Arabic $width',(t)async{
   t.view.physicalSize=Size(width,844);t.view.devicePixelRatio=1;
   addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
   var opened='';
   await t.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(1.5)),child:Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(16),child:AccountOverview(name:'محمد علي الاسم الكامل',phone:'+9647800868280',onFavorites:()=>opened='favorites',onWallet:()=>opened='wallet',onOrders:()=>opened='orders'))))))));
   for(final item in [('المفضلة','favorites'),('المحفظة','wallet'),('الطلبات','orders')]){await t.tap(find.text(item.$1));expect(opened,item.$2);}
   expect(find.textContaining('Manage'),findsNothing);
   expect(t.takeException(),isNull);
  });
 }
}
