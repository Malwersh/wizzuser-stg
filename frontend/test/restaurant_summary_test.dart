import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:foodapp_user/models/store.dart';
import 'package:foodapp_user/providers/app_state_provider.dart';
import 'package:foodapp_user/services/storefront_pricing.dart';
import 'package:foodapp_user/widgets/restaurant_menu_components.dart';

class EmptyCart extends ChangeNotifier implements AppStateProvider {
  @override
  List<Map<String, dynamic>> get cartItems => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'all restaurant summaries fit $width with explicit labels and minimum',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final cart = EmptyCart();
        for (final id in ['fattoush-summary', 'another-restaurant-summary']) {
          StorefrontPricing.instance.seedBusiness(id, {
            'minimumOrderAmountIqd': 7000,
          });
          final store = Store(
            id: id,
            name: 'مطعم',
            image: '',
            logoUrl: '',
            isOpen: true,
            fee: '',
            rating: '',
            reviews: '',
            distance: '',
            time: '',
            address: '',
            averagePreparationMinutes: 20,
            combos: [],
            sandwiches: [],
            drinks: [],
            extras: [],
            specialties: [],
          );
          await t.pumpWidget(
            ChangeNotifierProvider<AppStateProvider>.value(
              value: cart,
              child: MaterialApp(
                home: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: RestaurantSummaryCard(
                        store: store,
                        onDetails: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          expect(find.text('وقت التحضير'), findsOneWidget);

          expect(find.text('الحد الأدنى للأصناف'), findsOneWidget);
          expect(find.text('7000 د.ع'), findsOneWidget);
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox());
        cart.dispose();
      },
    );
  }
}
