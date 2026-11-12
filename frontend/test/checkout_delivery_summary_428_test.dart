import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/checkout_delivery_summary.dart';

void main() {
  testWidgets(
    'compact delivery summary remains readable with large Arabic text and opens editing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var edited = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: CheckoutDeliverySummary(
                  name: 'محمد علي',
                  phone: '+9647800868280',
                  address:
                      'مركز المناذرة، حي الجمعية، خلف إعدادية الصناعة قرب المدخل الرئيسي',
                  onEdit: () => edited = true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('محمد علي'), findsOneWidget);
      expect(find.text('+9647800868280'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('تعديل'));
      expect(edited, true);
    },
  );
}
