import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/platform_benefit.dart';
import 'package:foodapp_user/widgets/checkout_benefits_sheet.dart';
Map<String,dynamic> row({bool eligible=true,int remaining=1})=>{'schemaVersion':1,'id':'benefit','title':'اختبار خصم أصناف ٥٠٠','description':'تمويل المنصة','kind':'GOODS_AMOUNT','startAt':'2026-01-01T00:00:00Z','endAt':'2030-01-01T00:00:00Z','amountIqd':500,'maximumPerOrderIqd':500,'minimumGoodsIqd':7000,'maximumRoadMeters':200000,'granted':1,'reserved':0,'used':1-remaining,'remaining':remaining,'eligible':eligible,'reason':eligible?null:'BENEFIT_WRONG_BRANCH','branchIds':['branch']};
Widget app(Future<List<PlatformBenefit>> Function() loader)=>MaterialApp(home:Scaffold(body:SizedBox(height:600,child:CheckoutBenefitsSheet(branchId:'branch',loader:loader))));
void main(){
 test('rejects a fabricated remaining balance',(){expect(()=>PlatformBenefit.fromJson({...row(),'remaining':2}),throwsFormatException);});
 testWidgets('shows granted benefit conditions and available use',(tester)async{await tester.pumpWidget(app(()async=>[PlatformBenefit.fromJson(row())]));await tester.pumpAndSettle();expect(find.text('اختبار خصم أصناف ٥٠٠'),findsOneWidget);expect(find.text('الحد الأدنى للأصناف: 7000 د.ع'),findsOneWidget);expect(find.text('الاستخدامات المتبقية: 1'),findsOneWidget);expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton,'اختيار الميزة')).onPressed,isNotNull);});
 testWidgets('ineligible or exhausted benefits cannot be selected',(tester)async{for(final data in [row(eligible:false),row(remaining:0)]){await tester.pumpWidget(app(()async=>[PlatformBenefit.fromJson(data)]));await tester.pumpAndSettle();expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton,'اختيار الميزة')).onPressed,isNull);await tester.pumpWidget(const SizedBox());}});
 testWidgets('load failure offers a working retry',(tester)async{var calls=0;await tester.pumpWidget(app(()async{if(calls++==0)throw StateError('offline');return [];}));await tester.pumpAndSettle();await tester.tap(find.text('إعادة المحاولة'));await tester.pumpAndSettle();expect(calls,2);expect(find.textContaining('لا توجد مزايا متاحة'),findsOneWidget);});
 testWidgets('loading waits without presenting a usable benefit',(tester)async{final pending=Completer<List<PlatformBenefit>>();await tester.pumpWidget(app(()=>pending.future));await tester.pump();expect(find.byType(CircularProgressIndicator),findsOneWidget);expect(find.text('اختيار الميزة'),findsNothing);pending.complete([]);await tester.pumpAndSettle();});
}
