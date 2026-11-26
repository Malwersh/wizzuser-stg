import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/custom_bottom_navigation.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('Arabic navigation order and actions fit width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tapped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 850),
              disableAnimations: true,
            ),
            child: Scaffold(
              bottomNavigationBar: CustomBottomNavigation(
                currentIndex: 0,
                cartCount: 3,
                onTap: tapped.add,
              ),
            ),
          ),
        ),
      );
      final icons = [
        Icons.home_rounded,
        Icons.shopping_cart_outlined,
        Icons.search,
        Icons.map_outlined,
        Icons.person_outline_rounded,
      ];
      final positions =
          icons.map((icon) => tester.getCenter(find.byIcon(icon)).dx).toList();
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], lessThan(positions[i - 1]));
      }
      for (final icon in icons) {
        await tester.tap(find.byIcon(icon));
      }
      expect(tapped, [0, 7, 6, 3, 5]);
      expect(find.text('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
