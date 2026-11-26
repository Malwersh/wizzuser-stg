import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/discovery/customer_components.dart';
void main() {
 for(final scale in [1.0,1.6]) {
  testWidgets('add label right, amount badge left, safe large text $scale',(t) async {
   t.view.physicalSize=const Size(390,844);t.view.devicePixelRatio=1;
   addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
   var added=false;
   await t.pumpWidget(MaterialApp(home:MediaQuery(data:MediaQueryData(textScaler:TextScaler.linear(scale)),child:Directionality(textDirection:TextDirection.rtl,child:Scaffold(bottomNavigationBar:CustomerOrderActionBar(quantity:1,total:9500,onQuantity:(_){},onAdd:()=>added=true))))));
   expect(t.getCenter(find.text('أضف إلى السلة')).dx,greaterThan(t.getCenter(find.byKey(const ValueKey('meal-total-label'))).dx));
   await t.tap(find.byKey(const ValueKey('add-meal-to-cart')));expect(added,true);
   expect(t.takeException(),isNull);
  });
 }
}
