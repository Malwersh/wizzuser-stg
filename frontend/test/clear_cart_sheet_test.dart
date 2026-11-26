import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/clear_cart_sheet.dart';

void main() {
  bool? lastResult;

  Future<void> pumpHost(WidgetTester tester) async {
    lastResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  lastResult = await showClearCartConflictSheet(
                    context,
                    otherStoreName: 'مطعم البيك',
                  );
                },
                child: const Text('Open conflict sheet'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the other restaurant name and both actions', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('Open conflict sheet'));
    await tester.pumpAndSettle();

    expect(find.text('بدء سلة جديدة؟'), findsOneWidget);
    expect(
      find.textContaining('مطعم البيك', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('مسح وإضافة العنصر'), findsOneWidget);
    expect(find.text('الاحتفاظ بالسلة'), findsOneWidget);
  });

  testWidgets('clear-and-add returns true and closes the sheet', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('Open conflict sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('مسح وإضافة العنصر'));
    await tester.pumpAndSettle();

    expect(lastResult, isTrue);
    expect(find.text('بدء سلة جديدة؟'), findsNothing);
  });

  testWidgets('keep-current-cart returns false and closes the sheet', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('Open conflict sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الاحتفاظ بالسلة'));
    await tester.pumpAndSettle();

    expect(lastResult, isFalse);
    expect(find.text('بدء سلة جديدة؟'), findsNothing);
  });
}
