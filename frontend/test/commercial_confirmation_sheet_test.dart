import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/commercial_confirmation_sheet.dart';

void main() {
  testWidgets('review sheet shows context and exact IQD totals; expiry never approves', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var clock = DateTime.utc(2026, 10, 17, 21);
    final expires = clock.add(const Duration(minutes: 2));
    Map<String, dynamic> money(int iqd) => {'minorAmount': iqd * 1000};
    final proposal = {'expiresAt': expires.toIso8601String(), 'goodsGross':money(7000),
      'discount':money(0),'serviceFee':money(500),'deliveryFee':money(2000),
      'driverTip':money(0),'customerTotal':money(9500)};
    bool? accepted;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder:(context) => TextButton(
      onPressed:() async { accepted = await showModalBottomSheet<bool>(context:context,
        isScrollControlled:true, builder:(_) => CommercialConfirmationSheet(proposal:proposal,
          storeName:'مطعم فتوش',customerName:'مستلم الاختبار',phone:'رقم الاختبار',address:'عنوان الاختبار',
          paymentLabel:'نقدًا عند الاستلام',items:const [{'name':'صنف الاختبار','quantity':2}],clock:()=>clock)); },
      child:const Text('open'))))));
    await tester.tap(find.text('open')); await tester.pumpAndSettle();
    expect(find.text('مطعم فتوش'), findsOneWidget);
    expect(find.text('2 × صنف الاختبار'), findsOneWidget);
    expect(find.text('تأكيد الطلب • 9,500 د.ع'), findsOneWidget);
    expect(find.text('9,500.000 د.ع'), findsNothing);
    expect(tester.takeException(), isNull);
    clock = expires;
    await tester.pump(const Duration(seconds:1));
    expect(find.text('إعادة مراجعة السعر'), findsOneWidget);
    await tester.tap(find.text('إعادة مراجعة السعر')); await tester.pumpAndSettle();
    expect(accepted, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
