import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/driver_tip_selector.dart';

void main() {
  test(
    'accepts whole IQD in local digits and rejects negative or fractional tips',
    () {
      expect(parseDriverTipIqd('١٥٠٠'), 1500);
      expect(parseDriverTipIqd('۵۰۰'), 500);
      for (final text in ['', '-1', '1.5', '1000000001', 'abc']) {
        expect(parseDriverTipIqd(text), isNull);
      }
    },
  );
  testWidgets('selects preset, custom amount and no tip explicitly', (
    tester,
  ) async {
    var tip = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder:
                (context, update) => DriverTipSelector(
                  amountIqd: tip,
                  onChanged: (value) => update(() => tip = value),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1000 د.ع'));
    await tester.pump();
    expect(tip, 1000);
    await tester.tap(find.text('مبلغ آخر'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-500');
    await tester.tap(find.text('تطبيق'));
    await tester.pump();
    expect(tip, 1000);
    expect(find.text('أدخل مبلغًا صحيحًا بالدينار'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '١٥٠٠');
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(tip, 1500);
    await tester.tap(find.text('دون إكرامية'));
    await tester.pump();
    expect(tip, 0);
  });
  testWidgets('does not alter a pending order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverTipSelector(
            amountIqd: 500,
            enabled: false,
            onChanged: (_) => fail('tip changed'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1000 د.ع'));
    await tester.tap(find.text('مبلغ آخر'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
