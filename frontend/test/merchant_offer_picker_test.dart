import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/store_discount.dart';
import '../lib/widgets/merchant_offer_picker.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('many offers searchable and selectable at $width', (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final offers = List.generate(15, (i) => StoreDiscount(discountId: '$i', businessId: 'store', title: 'عرض المطعم رقم $i', type: 'fixedAmount', value: 500, minimumOrderAmount: 7000));
      StoreDiscount? picked;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
        picked = await showModalBottomSheet<StoreDiscount>(context: context, isScrollControlled: true, builder: (_) => MerchantOfferPicker(offers: offers));
      }, child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'رقم 14');
      await tester.pumpAndSettle();
      expect(find.text('عرض المطعم رقم 14'), findsOneWidget);
      expect(find.text('عرض المطعم رقم 1'), findsNothing);
      await tester.tap(find.text('عرض المطعم رقم 14'));
      await tester.pumpAndSettle();
      expect(picked?.discountId, '14');
      expect(tester.takeException(), isNull);
    });
  }
}
