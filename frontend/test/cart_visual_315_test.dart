import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/empty_basket_view.dart';
import 'package:foodapp_user/widgets/home_cart_button.dart';
import 'package:foodapp_user/widgets/custom_bottom_navigation.dart';
import 'package:foodapp_user/widgets/rotating_search_hint.dart';

void main() {
  testWidgets(
    'empty cart fits a narrow screen with enlarged text and returns to browsing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var browsed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: EmptyBasketView(onBrowse: () => browsed = true),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(EmptyBasketView)).width, 320);
      expect(tester.getCenter(find.text('سلة التسوق')).dx, 160);
      expect(find.byTooltip('العودة إلى الرئيسية'), findsOneWidget);
      await tester.tap(find.byTooltip('العودة إلى الرئيسية'));
      expect(browsed, true);
      browsed = false;
      await tester.ensureVisible(find.text('متابعة التصفح'));
      await tester.tap(find.text('متابعة التصفح'));
      expect(browsed, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'floating cart hides when empty, shows actual count and opens basket',
    (tester) async {
      var opened = false;
      Widget screen(int count) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: HomeCartButton(count: count, onTap: () => opened = true),
          ),
        ),
      );
      await tester.pumpWidget(screen(0));
      expect(find.byTooltip('فتح السلة'), findsNothing);
      await tester.pumpWidget(screen(5));
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.byTooltip('فتح السلة'));
      expect(opened, true);
      await tester.pumpWidget(screen(0));
      expect(find.byTooltip('فتح السلة'), findsNothing);
    },
  );
  testWidgets('Arabic search icon stays to the right of the fixed text area', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CustomBottomNavigation(
            currentIndex: 0,
            onTap: (_) {},
            searchHints: const ['بيتزا', 'فروج المدينة'],
          ),
        ),
      ),
    );
    final position = tester.getCenter(find.byIcon(Icons.search));
    expect(
      position.dx,
      greaterThan(tester.getCenter(find.byType(RotatingSearchHint)).dx),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(tester.getCenter(find.byIcon(Icons.search)), position);
    await tester.pumpWidget(const SizedBox());
  });
}
