import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/home_navigation.dart';
import 'package:foodapp_user/models/menu_classification_focus.dart';
import 'package:foodapp_user/models/product_model.dart';
import 'package:foodapp_user/widgets/menu_classification_focus_section.dart';

void main() {
  HomeNavigation navigation({
    bool enabled = true,
    bool topics = true,
    String kind = 'cuisine',
  }) => HomeNavigation.fromJson({
    'enabled': enabled,
    'topicsEnabled': topics,
    'items': [
      {
        'id': 'pizza-chip',
        'label': 'بيتزا',
        'kind': kind,
        'value': 'pizza',
        'parentActivities': ['RESTAURANT'],
      },
    ],
  });
  test(
    'only an active cuisine selection in the current activity becomes menu context',
    () {
      expect(
        MenuClassificationFocus.fromNavigation(
          navigation(),
          'pizza-chip',
          activity: 'RESTAURANT',
        )?.id,
        'pizza',
      );
      expect(
        MenuClassificationFocus.fromNavigation(
          navigation(),
          'pizza-chip',
          activity: 'STORE',
        ),
        isNull,
      );
      expect(
        MenuClassificationFocus.fromNavigation(
          navigation(enabled: false),
          'pizza-chip',
        ),
        isNull,
      );
      expect(
        MenuClassificationFocus.fromNavigation(
          navigation(topics: false),
          'pizza-chip',
        ),
        isNull,
      );
      expect(
        MenuClassificationFocus.fromNavigation(
          navigation(kind: 'brand'),
          'pizza-chip',
        ),
        isNull,
      );
      expect(
        MenuClassificationFocus.fromNavigation(navigation(), 'all'),
        isNull,
      );
      expect(
        MenuClassificationFocus.fromNavigation(null, 'pizza-chip'),
        isNull,
      );
    },
  );
  ProductModel product(
    String id, {
    String branch = 'b',
    List<String> tags = const [],
    String name = 'بيتزا',
    bool available = true,
  }) => ProductModel(
    id: id,
    businessId: branch,
    categoryId: 'c',
    name: name,
    description: '',
    imageUrl: '',
    price: 12000,
    cuisineIds: tags,
    isAvailable: available,
    createdAt: DateTime(2026),
  );
  test(
    'matches explicit published IDs, isolates branches, and deduplicates without changing prices or availability',
    () {
      const focus = MenuClassificationFocus(id: 'pizza', label: 'بيتزا');
      final match = product('p', tags: ['pizza']);
      final unavailable = product('out', tags: ['pizza'], available: false);
      final result = focus.productsFor('b', [
        product('name-only'),
        product('foreign', branch: 'other', tags: ['pizza']),
        match,
        match,
        unavailable,
      ]);
      expect(result.map((p) => p.id), ['p', 'out']);
      expect(identical(result.first, match), true);
      expect(result.first.price, 12000);
      expect(result.last.isAvailable, false);
      expect(focus.productsFor('b', [product('only-name')]), isEmpty);
    },
  );
  testWidgets(
    'a branch-only classification gives an honest empty state and allows returning to the menu',
    (tester) async {
      var cleared = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: MenuClassificationFocusSection(
                focus: const MenuClassificationFocus(
                  id: 'pizza',
                  label: 'بيتزا',
                ),
                products: [],
                onClear: () => cleared = true,
                available: (_) => true,
                reason: (_) => null,
                onOpen: (_) {},
                onAdd: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('لم تُربط أصناف'), findsOneWidget);
      await tester.tap(find.text('تصفّح القائمة كاملة'));
      expect(cleared, true);
      expect(tester.takeException(), isNull);
    },
  );
}
