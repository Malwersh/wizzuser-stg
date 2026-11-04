import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/discovery/home_discovery_header.dart';

void main() {
  testWidgets(
    'compact RTL header exposes only address and notification actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var address = 0, notifications = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: HomeDiscoveryHeader(
                address: 'مركز المناذرة',
                unread: true,
                onAddress: () => address++,
                onAccount: () {},
                onCart: () {},
                onNotifications: () => notifications++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('مركز المناذرة'));
      expect(address, 1);
      await tester.tap(find.byTooltip('الإشعارات'));
      expect(notifications, 1);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('حسابي'), findsOneWidget);
      expect(find.byTooltip('السلة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pictured categories retain selected state and return the actual type key',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTypeCategories(
              categories: const [
                HomeTypeCategory('all', 'الكل', 'assets/icons/cat_rest.png'),
                HomeTypeCategory(
                  'restaurant',
                  'مطاعم',
                  'assets/icons/burger.png',
                ),
              ],
              selected: 'all',
              onChanged: (v) => selected = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('مطاعم'));
      expect(selected, 'restaurant');
      expect(tester.takeException(), isNull);
    },
  );
}
