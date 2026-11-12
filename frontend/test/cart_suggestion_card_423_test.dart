import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/product_model.dart';
import 'package:foodapp_user/widgets/cart_suggestion_card.dart';
void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('suggested product card fits long names and opens choices $scale', (t) async {
      var opened = false;
      final product = ProductModel(id:'p',businessId:'b',categoryId:'c',name:'بيتزا عائلية مع أحجام وإضافات متنوعة',description:'',imageUrl:'',price:10000,createdAt:DateTime(2026));
      await t.pumpWidget(MaterialApp(home:MediaQuery(data:MediaQueryData(textScaler:TextScaler.linear(scale)),child:Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:SingleChildScrollView(scrollDirection:Axis.horizontal,child:CartSuggestionCard(product:product,onOpen:()=>opened=true)))))));
      expect(find.text('10,000 د.ع'),findsOneWidget);
      await t.tap(find.byTooltip('اختيار ${product.name}'));
      expect(opened,true);
      expect(t.takeException(),isNull);
    });
  }
}
