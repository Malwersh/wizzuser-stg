import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/models/cart_item.dart';
import 'package:foodapp_user/models/cart_model.dart';
import 'package:foodapp_user/models/dish.dart';
import 'package:foodapp_user/providers/app_state_provider.dart';
import 'package:foodapp_user/screens/cart_screen.dart';
import 'package:foodapp_user/services/storefront_pricing.dart';
import 'package:foodapp_user/widgets/basket_line_card.dart';

CartItem line({String note = '', Set<String> choices = const {}, String name = 'كباب يلعب النفس'}) => CartItem(
  storeId: 'b1', dish: Dish(id: 'p1', name: name, imageUrls: [], description: '', likesPercent: 0, likesCount: 0,
    basePrice: 3500, optionGroups: []), quantity: 1, unitPrice: 3500, totalPrice: 3500,
    selectedOptions: {'إضافات': choices}, specialInstructions: note);
Map<String, dynamic> preview({int minimum = 0}) => {
  'kind': 'STOREFRONT_PREVIEW', 'schemaVersion': 1, 'branchId': 'b1', 'addressId': 'a1',
  'expiresAt': '2026-10-21T00:00:00Z', 'roadDistanceMeters': 6500, 'deliveryDurationSeconds': 600,
  'minimumOrderAmountIqd': minimum,
  'customerDeliveryFee': {'moneySchemaVersion': 1, 'currency': 'IQD', 'scale': 1000, 'minorAmount': 1500000},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('rapid deltas use current quantity and affect exactly the configured line; latest storage wins', () async {
    final cart = CartModel(), first = line(note: 'بدون بصل'), other = line(note: 'بصل إضافي');
    cart.addItem(first); cart.addItem(other);
    for (var i = 0; i < 15; i++) { cart.changeItemQuantity(first, 1); }
    expect(cart.items.length, 2); expect(cart.items[0].quantity, 16); expect(cart.items[1].quantity, 1);
    expect(cart.totalAmount, 59500);
    await cart.saveToStorage();
    final restored = CartModel(); await restored.loadFromStorage(); expect(restored.items[0].quantity, 16);
    cart.removeItem(first); expect(cart.items.length, 1); expect(cart.items.single.specialInstructions, 'بصل إضافي');
    cart.clear(); await cart.saveToStorage();
    await restored.loadFromStorage(); expect(restored.items, isEmpty);
    cart.dispose(); restored.dispose();
  });
  test('clearing and immediately adding another basket preserves the new basket in storage', () async {
    final cart=CartModel();cart.addItem(line());cart.clear();cart.addItem(line(note:'طلب جديد'));await cart.saveToStorage();
    final restored=CartModel();await restored.loadFromStorage();expect(restored.items.single.specialInstructions,'طلب جديد');
  });
  testWidgets('delivery fee has explicit loading and the same label as the restaurant', (t) async {
    final pending=Completer<http.Response>();var calls=0;
    final pricing=StorefrontPricing(account:()=> 'u1',token:()=> 'token',addressId:()=> 'a1',addressRevision:()=> 'v1',listenToAddress:false,
      now:()=>DateTime.utc(2026,10,20),client:MockClient((_) {calls++;return pending.future;}));
    final state=AppStateProvider();state.cart.addItem(line());
    await t.pumpWidget(ChangeNotifierProvider.value(value:state,child:MaterialApp(home:CartScreen(pricing:pricing))));
    expect(find.text('رسوم التوصيل'),findsOneWidget);
    expect(find.text('التوصيل التقديري'),findsNothing);
    expect(find.text('جارٍ حساب الرسوم…'),findsOneWidget);
    expect(find.byType(CircularProgressIndicator),findsOneWidget);
    await t.pump(const Duration(milliseconds:300));await t.pump();expect(calls,1);
    pending.complete(http.Response(jsonEncode({'success':true,'preview':preview()}),200));
    await t.pumpAndSettle();expect(find.text('1500 د.ع'),findsOneWidget);
    expect(find.text('جارٍ حساب الرسوم…'),findsNothing);
    await t.pumpWidget(const SizedBox());pricing.dispose();state.dispose();
  });
  testWidgets('opening cart with a fresh matching server fee is immediate and sends no new request', (t) async {
    var calls=0;
    final pricing=StorefrontPricing(account:()=> 'u1',token:()=> 'token',addressId:()=> 'a1',addressRevision:()=> 'v1',listenToAddress:false,
      now:()=>DateTime.utc(2026,10,20),client:MockClient((_)async{calls++;return http.Response(jsonEncode({'success':true,'preview':preview()}),200);}));
    final state=AppStateProvider();state.cart.addItem(line());
    await pricing.load('b1',state.cartItems);
    await t.pumpWidget(ChangeNotifierProvider.value(value:state,child:MaterialApp(home:CartScreen(pricing:pricing))));
    expect(find.text('1500 د.ع'),findsOneWidget);expect(find.text('جارٍ حساب الرسوم…'),findsNothing);
    await t.pumpAndSettle();expect(calls,1);
    await t.pumpWidget(const SizedBox());pricing.dispose();state.dispose();
  });
  testWidgets('rapid quantity edits debounce informational pricing instead of requesting every intermediate basket', (t) async {
    var calls=0;final pricing=StorefrontPricing(account:()=> 'u1',token:()=> 'token',addressId:()=> 'a1',addressRevision:()=> 'v1',listenToAddress:false,
      now:()=>DateTime.utc(2026,10,20),client:MockClient((_) async {calls++;return http.Response(jsonEncode({'success':true,'preview':preview()}),200);}));
    final state=AppStateProvider();state.cart.addItem(line());
    await t.pumpWidget(ChangeNotifierProvider.value(value:state,child:MaterialApp(home:CartScreen(pricing:pricing))));
    final add=find.byTooltip('زيادة كمية كباب يلعب النفس');for(var i=0;i<6;i++){await t.tap(add);await t.pump(const Duration(milliseconds:20));}
    expect(calls,0);await t.pump(const Duration(milliseconds:300));await t.pumpAndSettle();expect(calls,1);expect(state.cart.itemCount,7);
    await t.pumpWidget(const SizedBox());pricing.dispose();state.dispose();
  });
  test('equivalent option sets share identity regardless of insertion order; notes remain distinct', () {
    final cart = CartModel();cart.addItem(line(choices: {'بصل', 'خبز'}));cart.addItem(line(choices: {'خبز', 'بصل'}));
    expect(cart.items.length, 1); expect(cart.items.single.quantity, 2);cart.addItem(line(note:'بدون ملح', choices:{'بصل','خبز'}));expect(cart.items.length,2);
  });
  testWidgets('one continue tap waits for price then opens checkout; duplicates blocked and no diagnostic banner', (t) async {
    final gate = Completer<http.Response>(); var calls = 0;
    final pricing = StorefrontPricing(account:()=> 'u1', token:()=> 'token', addressId:()=> 'a1',
      addressRevision:()=> 'v1', listenToAddress:false, now:()=>DateTime.utc(2026,10,20),
      client:MockClient((_) { calls++; return gate.future; }));
    final state = AppStateProvider(); state.cart.addItem(line());
    await t.pumpWidget(ChangeNotifierProvider.value(value:state, child:MaterialApp(home:CartScreen(
      storeId:'b1',storeName:'مطعم فتوش',pricing:pricing,checkoutBuilder:(_)=>const Scaffold(body:Text('مراجعة الطلب'))))));
    await t.pump();
    expect(find.textContaining('الفئات المطلوبة'), findsNothing);expect(find.textContaining('وضع الاختبار'), findsNothing);
    await t.tap(find.text('متابعة الطلب'));await t.pump();
    expect(find.text('جارٍ التحقق…'),findsOneWidget);expect(find.text('مراجعة الطلب'),findsNothing);
    await t.tap(find.text('جارٍ التحقق…'));await t.pump();expect(calls,1);
    gate.complete(http.Response(jsonEncode({'success':true,'preview':preview()}),200));
    await t.pumpAndSettle(); expect(find.text('مراجعة الطلب'),findsOneWidget);expect(calls,1);expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());pricing.dispose();state.dispose();
  });
  testWidgets('continue reuses a fresh basket price without a second network request', (t) async {
    var calls=0;
    final pricing=StorefrontPricing(account:()=> 'u1',token:()=> 'token',addressId:()=> 'a1',addressRevision:()=> 'v1',listenToAddress:false,
      now:()=>DateTime.utc(2026,10,20),client:MockClient((_) async {calls++;return http.Response(jsonEncode({'success':true,'preview':preview()}),200);}));
    final state=AppStateProvider();state.cart.addItem(line());
    await pricing.load('b1',state.cartItems);expect(calls,1);
    await t.pumpWidget(ChangeNotifierProvider.value(value:state,child:MaterialApp(home:CartScreen(pricing:pricing,
      checkoutBuilder:(_)=>const Scaffold(body:Text('مراجعة الطلب'))))));
    await t.pumpAndSettle();await t.tap(find.text('متابعة الطلب'));await t.pumpAndSettle();
    expect(find.text('مراجعة الطلب'),findsOneWidget);expect(calls,1);
    await t.pumpWidget(const SizedBox());pricing.dispose();state.dispose();
  });
  testWidgets('repeated taps before repaint each increment the selected variant', (t) async {
    final pricing=StorefrontPricing(account:()=>null,listenToAddress:false);
    final state=AppStateProvider();state.cart.addItem(line(note:'بدون بصل'));state.cart.addItem(line(note:'بصل إضافي'));
    await t.pumpWidget(ChangeNotifierProvider.value(value:state,child:MaterialApp(home:CartScreen(pricing:pricing))));
    final add=find.byTooltip('زيادة كمية كباب يلعب النفس').first;
    for(var i=0;i<5;i++){await t.tap(add);}
    await t.pump();expect(state.cart.items[0].quantity,6);expect(state.cart.items[1].quantity,1);
    expect(find.text('21,000 د.ع'),findsOneWidget);expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());pricing.dispose();state.dispose();
  });
  testWidgets('failed preview retains basket and shows inline retry; a zero minimum is not invented', (t) async {
    final pricing=StorefrontPricing(account:()=> 'u1',token:()=> 'token',addressId:()=> 'a1',addressRevision:()=> 'v1',
      listenToAddress:false,client:MockClient((_) async =>http.Response('{}',503)));
    final state=AppStateProvider();state.cart.addItem(line());
    await t.pumpWidget(ChangeNotifierProvider.value(value:state,child:MaterialApp(home:CartScreen(pricing:pricing))));
    await t.pumpAndSettle();await t.tap(find.text('متابعة الطلب'));await t.pumpAndSettle();
    expect(find.text('تعذر تحديث بيانات التوصيل. تحقق من الاتصال ثم أعد المحاولة.'),findsOneWidget);
    expect(state.cart.itemCount,1);expect(find.byType(SnackBar),findsNothing);expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());pricing.dispose();state.dispose();
  });
  testWidgets('large Arabic line and notes fit a narrow phone with accessible quantity controls', (t) async {
    t.view.physicalSize=const Size(320,900);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(1.5)),child:Scaffold(body:SingleChildScrollView(child:Directionality(textDirection:TextDirection.rtl,child:BasketLineCard(
      item:line(name:'كباب يلعب النفس مع الخبز والسلطة والأطباق الجانبية',note:'بدون ملح وبصل مع تغليف منفصل'),increase:(){},decrease:(){},remove:(){})))))));
    await t.pump();expect(t.takeException(),isNull);expect(find.byTooltip('زيادة كمية كباب يلعب النفس مع الخبز والسلطة والأطباق الجانبية'),findsOneWidget);
  });
}
