import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/discount_notice_sheet.dart';
void main() {
  for (final width in [320.0,390.0]) {
    testWidgets('minimum offer notice explains 14000 threshold and dismisses safely at $width', (t) async {
      t.view.physicalSize=Size(width,850);t.view.devicePixelRatio=1;
      addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
        onPressed:()=>showDiscountNoticeSheet(context,offerTitle:'خصم مشترك ٥٠٠',message:'unavailable',minimum:14000,subtotal:12000),
        child:const Text('تطبيق'))))));
      await t.tap(find.text('تطبيق'));await t.pumpAndSettle();
      expect(find.text('لم تصل للحد الأدنى للعرض'),findsOneWidget);
      expect(find.text('14,000 د.ع'),findsOneWidget);
      expect(find.text('12,000 د.ع'),findsOneWidget);
      expect(find.text('2,000 د.ع'),findsOneWidget);
      expect(find.textContaining('ولا يشمل رسوم التوصيل'),findsOneWidget);
      expect(t.takeException(),isNull);
      await t.ensureVisible(find.text('العودة للطلب'));await t.tap(find.text('العودة للطلب'));await t.pumpAndSettle();
      expect(find.text('لم تصل للحد الأدنى للعرض'),findsNothing);
      expect(find.text('تطبيق'),findsOneWidget);
    });
  }
  testWidgets('other rejection does not invent minimum or remaining amount', (t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:DiscountNoticeSheet(message:'انتهت مدة العرض'))));
    expect(find.text('انتهت مدة العرض'),findsOneWidget);
    expect(find.text('الحد الأدنى للعرض'),findsNothing);
    expect(find.text('المبلغ المتبقي'),findsNothing);
  });
}
