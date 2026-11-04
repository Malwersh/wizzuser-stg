import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/product_model.dart';
import 'package:foodapp_user/models/dish.dart';
import 'package:foodapp_user/screens/dish_detail_screen.dart';
import 'package:foodapp_user/widgets/discovery/customer_components.dart';
import 'package:foodapp_user/utils/currency_format.dart';

Map<String,dynamic> productJson()=>{'productId':'pizza','businessId':'store','categoryId':'pizza','name':'بيتزا ويز','description':'بيتزا محضّرة حسب اختيارك','price':10000,'imageUrl':'','isAvailable':true,'optionGroups':[
 {'id':'size','title':'حجم البيتزا','required':true,'maxSelections':1,'options':[{'id':'small','name':'صغيرة','extraPrice':0,'isAvailable':true},{'id':'large','name':'كبيرة','extraPrice':3000,'isAvailable':true}]},
 {'id':'sides','title':'الإضافات','required':true,'maxSelections':2,'options':[{'id':'cheese','name':'جبن إضافي','extraPrice':1000,'isAvailable':true},{'id':'olives','name':'زيتون','extraPrice':500,'isAvailable':true},{'id':'corn','name':'ذرة','extraPrice':250,'isAvailable':true},{'id':'sauce','name':'صوص','extraPrice':200,'isAvailable':false}]},
]};
Dish dish()=>Dish(id:'pizza',name:'بيتزا ويز',imageUrls:[],description:'',likesPercent:0,likesCount:0,basePrice:10000,optionGroups:[]);
void main(){
 test('canonical product groups preserve max selections, price deltas and unavailable choices through serialization',(){final p=ProductModel.fromJson(productJson());expect(p.optionGroups!.length,2);expect(p.optionGroups!.last.maxSelections,2);expect(p.optionGroups!.last.options.last.isAvailable,false);expect(p.optionGroups!.first.options.last.extraPrice,3000);expect(ProductModel.fromJson(p.toJson()).optionGroups!.last.options.last.isAvailable,false);});
 test('authoritative empty optionGroups cannot resurrect legacy add-ons',(){final raw=productJson()..['optionGroups']=[]..['addons']=[{'name':'stale addon','price':999}];expect(ProductModel.fromJson(raw).effectiveOptionGroups,isEmpty);});
 testWidgets('required single and multiple choices gate add and update configured price and quantity', (t)async{
  await t.binding.setSurfaceSize(const Size(390,844));addTearDown(()=>t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home:DishDetailScreen(dish:dish(),storeId:'store',productData:ProductModel.fromJson(productJson()))));
  final add=find.byKey(const ValueKey('add-meal-to-cart'));
  expect(t.widget<FilledButton>(add).onPressed,isNull);
  await t.ensureVisible(find.byKey(const ValueKey('choice-size-large')));await t.tap(find.byKey(const ValueKey('choice-size-large')));await t.pump();expect(t.widget<FilledButton>(add).onPressed,isNull);
  await t.ensureVisible(find.byKey(const ValueKey('choice-sides-cheese')));await t.tap(find.byKey(const ValueKey('choice-sides-cheese')));await t.pump();expect(t.widget<FilledButton>(add).onPressed,isNotNull);expect(find.text(formatIqd(14000)),findsOneWidget);
  await t.ensureVisible(find.byKey(const ValueKey('choice-sides-olives')));await t.tap(find.byKey(const ValueKey('choice-sides-olives')));await t.pump();
  await t.ensureVisible(find.byKey(const ValueKey('choice-sides-corn')));await t.tap(find.byKey(const ValueKey('choice-sides-corn')));await t.pump();expect(find.text(formatIqd(14500)),findsOneWidget);
  await t.ensureVisible(find.byKey(const ValueKey('choice-sides-sauce')));await t.tap(find.byKey(const ValueKey('choice-sides-sauce')));await t.pump();expect(find.text(formatIqd(14500)),findsOneWidget);
  await t.tap(find.byTooltip('زيادة الكمية'));await t.pump();expect(find.text(formatIqd(29000)),findsOneWidget);expect(t.takeException(),isNull);
 });
 testWidgets('small RTL large text action bar and choice labels do not overflow', (t)async{
  await t.binding.setSurfaceSize(const Size(320,700));addTearDown(()=>t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(size:Size(320,700),textScaler:TextScaler.linear(1.6)),child:Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:SingleChildScrollView(child:MealChoiceGroup(group:ProductModel.fromJson(productJson()).optionGroups!.last,selected:{'cheese'},onChanged:(_){})),bottomNavigationBar:CustomerOrderActionBar(quantity:2,total:29000,onQuantity:(_){},onAdd:(){},hint:'اختر تفاصيل وجبتك'))))));
  await t.pump();expect(t.takeException(),isNull);expect(find.text('أضف إلى السلة'),findsOneWidget);
 });
}
