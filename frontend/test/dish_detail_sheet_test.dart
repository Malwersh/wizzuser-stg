import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:foodapp_user/models/dish.dart';
import 'package:foodapp_user/models/product_model.dart';
import 'package:foodapp_user/screens/dish_detail_screen.dart';

class _TestNavigatorObserver extends NavigatorObserver {
  final pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}

void main() {
  testWidgets('meal details open in a bottom sheet and keep their interactions', (
    tester,
  ) async {
    final observer = _TestNavigatorObserver();
    final dish = Dish(
      id: 'dish-1',
      name: 'Chicken burger',
      imageUrls: const [],
      description: 'Grilled chicken with fresh vegetables',
      likesPercent: 90,
      likesCount: 20,
      basePrice: 12,
      optionGroups: const [],
    );
    final product = ProductModel(
      id: 'dish-1',
      businessId: 'store-1',
      categoryId: 'category-1',
      name: dish.name,
      description: dish.description,
      imageUrl: '',
      price: dish.basePrice,
      createdAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDishDetailBottomSheet(
                    context,
                    dish: dish,
                    storeId: 'store-1',
                    storeName: 'Test restaurant',
                    productData: product,
                  );
                },
                child: const Text('Open meal'),
              ),
            ),
          ),
        ),
      ),
    );
    observer.pushedRoutes.clear();

    await tester.tap(find.text('Open meal'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    // مقبض السحب (_DragHandle) خاص بمكتبة Flutter وغير متاح كفئة عامة،
    // لذا نتحقق منه عبر Semantics الزر الذي يعرضه في أعلى اللوحة
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
      findsWidgets,
    );
    expect(find.byType(DishDetailScreen), findsOneWidget);
    expect(find.text('Chicken burger'), findsOneWidget);
    expect(observer.pushedRoutes, hasLength(1));
    expect(observer.pushedRoutes.single, isA<ModalBottomSheetRoute<dynamic>>());
    expect(
      observer.pushedRoutes.whereType<MaterialPageRoute<dynamic>>(),
      isEmpty,
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // شكل الأرقام العربية يعتمد على إصدار حزمة intl (قد تظهر ٢ أو 2)
    final arabicTwo = NumberFormat.decimalPattern('ar').format(2);
    expect(find.text(arabicTwo), findsOneWidget);
    expect(find.text('إضافة إلى الطلب • 24 د.ع'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(DishDetailScreen), findsNothing);
    expect(find.text('Open meal'), findsOneWidget);
  });
}
