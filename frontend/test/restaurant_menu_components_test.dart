import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/store.dart';
import 'package:foodapp_user/models/product_model.dart';
import 'package:foodapp_user/widgets/restaurant_menu_components.dart';

void main() {
  testWidgets(
    'photo header retains real restaurant information in RTL on a narrow phone',
    (tester) async {
      var opened = false;
      final store = Store(
        id: 'b',
        combos: [],
        sandwiches: [],
        drinks: [],
        extras: [],
        specialties: [],
        name: 'مطعم فتوش',
        image: '',
        logoUrl: '',
        isOpen: true,
        fee: '1500 د.ع',
        rating: '4.6',
        reviews: '120',
        distance: '2 كم',
        time: '20–30 دقيقة',
        address: 'بغداد',
        category: 'مشويات',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: RestaurantHeroDetails(
                    store: store,
                    onDetails: () => opened = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('مطعم فتوش'), findsOneWidget);
      expect(find.text('4.6'), findsOneWidget);
      expect(find.text('مشويات  •  بغداد'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('4.6'));
      expect(opened, isTrue);
    },
  );
  testWidgets(
    'menu tile preserves prices and actions, and blocks unavailable additions',
    (tester) async {
      var added = 0;
      var opened = 0;
      final p = ProductModel(
        id: 'p',
        businessId: 'b',
        categoryId: 'c',
        name: 'كباب',
        description: 'وجبة مشوية',
        imageUrl: '',
        price: 3500,
        createdAt: DateTime(2026),
      );
      Future<void> mount(bool available) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 160,
              child: RestaurantMenuTile(
                product: p,
                available: available,
                onDetails: () => opened++,
                onAdd: () => added++,
              ),
            ),
          ),
        ),
      );
      await mount(true);
      expect(find.text('3500 د.ع'), findsOneWidget);
      await tester.tap(find.byTooltip('إضافة إلى السلة'));
      await tester.tap(find.text('كباب'));
      expect(added, 1);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await mount(false);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      expect(find.text('غير متاح حالياً'), findsOneWidget);
    },
  );
}
