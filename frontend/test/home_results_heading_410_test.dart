import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/discovery/customer_components.dart';

void main() {
  for (final count in <int?>[null, 0, 8]) {
    testWidgets('filter results header supports $count and reset', (t) async {
      var resets = 0;
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: HomeResultsHeading(count: count, onReset: () => resets++),
            ),
          ),
        ),
      );
      expect(
        find.text(count == null ? 'جارٍ تحديث النتائج…' : 'النتائج: $count'),
        findsOneWidget,
      );
      await t.tap(find.text('إعادة ضبط'));
      expect(resets, 1);
      expect(t.takeException(), isNull);
    });
  }
}
