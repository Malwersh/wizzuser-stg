import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/custom_bottom_navigation.dart';

void main() {
  testWidgets(
    'floating controls fit a narrow phone and route every action correctly',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: CustomBottomNavigation(
              currentIndex: 0,
              cartCount: 3,
              onTap: (v) => selected = v,
            ),
          ),
        ),
      );
      for (final entry
          in {
            'الرئيسية': 0,
            'تصفح المطاعم': 3,
          }.entries) {
        await tester.tap(find.byTooltip(entry.key));
        expect(selected, entry.value);
      }
      await tester.tap(find.byIcon(Icons.search));
      expect(selected, 6);
      expect(find.byTooltip('السلة'), findsNothing);
      expect(find.byTooltip('حسابي'), findsNothing);
      expect(find.text('الإشعارات'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
