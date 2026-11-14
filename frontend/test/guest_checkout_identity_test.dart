import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/models/cart_model.dart';
import 'package:foodapp_user/services/session_service.dart';
import 'package:foodapp_user/widgets/checkout_sign_in_panel.dart';
import 'cart_reliability_test.dart' show line;
import 'package:provider/provider.dart';
import 'package:foodapp_user/providers/app_state_provider.dart';
import 'package:foodapp_user/screens/checkout_screen.dart';

Future<void> signIn(String id) => SessionService.instance.saveUserSession(
  accessToken: 'test-token',
  idToken: 'test-id',
  refreshToken: 'test-refresh',
  userData: {'userId': id, 'name': 'Test'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    await SessionService.instance.loginAsGuest();
  });
  test(
    'verified continuation preserves customized lines and persists only in selected account',
    () async {
      final c = CartModel();
      c.addItem(line(note: 'بدون ملح', choices: {'خبز', 'بصل'}));
      c.changeItemQuantity(c.items.single, 2);
      c.setStoreName('مطعم الاختبار');
      final snapshot = c.captureGuestCheckout();
      await c.saveToStorage();
      await signIn('verified');
      await c.clearOnSessionChange();
      expect(
        await c.restoreGuestCheckout(snapshot, 'verified'),
        GuestCheckoutCartResult.restored,
      );
      expect(c.itemCount, 3);
      expect(c.storeName, 'مطعم الاختبار');
      expect(c.items.single.specialInstructions, 'بدون ملح');
      expect(c.items.single.selectedOptions['إضافات'], {'خبز', 'بصل'});
      final p = await SharedPreferences.getInstance();
      expect(
        jsonDecode(p.getString('cart_items_verified')!).single['quantity'],
        3,
      );
      expect(p.getString('cart_items_guest'), isNotNull);
      expect(
        await c.restoreGuestCheckout(snapshot, 'verified'),
        GuestCheckoutCartResult.accountChanged,
      );
      c.dispose();
    },
  );
  test(
    'saved account basket is never silently replaced; explicit choice restores current checkout',
    () async {
      final c = CartModel();
      c.addItem(line(note: 'سلة الضيف'));
      final snapshot = c.captureGuestCheckout();
      await c.saveToStorage();
      await signIn('verified');
      await c.clearOnSessionChange();
      c.addItem(line(note: 'سلة الحساب'));
      await c.saveToStorage();
      expect(
        await c.restoreGuestCheckout(snapshot, 'verified'),
        GuestCheckoutCartResult.conflict,
      );
      expect(c.items.single.specialInstructions, 'سلة الحساب');
      expect(
        await c.restoreGuestCheckout(
          snapshot,
          'verified',
          replaceSavedBasket: true,
        ),
        GuestCheckoutCartResult.restored,
      );
      expect(c.items.single.specialInstructions, 'سلة الضيف');
      c.dispose();
    },
  );
  test(
    'cancelled sign-in and different account cannot import the guest snapshot',
    () async {
      final c = CartModel();
      c.addItem(line(note: 'ضيف'));
      final snapshot = c.captureGuestCheckout();
      expect(
        await c.restoreGuestCheckout(snapshot, 'verified'),
        GuestCheckoutCartResult.accountChanged,
      );
      expect(c.items.single.specialInstructions, 'ضيف');
      await signIn('other');
      await c.clearOnSessionChange();
      expect(
        await c.restoreGuestCheckout(snapshot, 'verified'),
        GuestCheckoutCartResult.accountChanged,
      );
      expect(c.items, isEmpty);
      expect(() => c.captureGuestCheckout(), throwsStateError);
      c.dispose();
    },
  );
  testWidgets(
    'guest checkout displays account continuation rather than invoice or legacy guest fields',
    (t) async {
      final state = AppStateProvider(canWarmInvoice: () => false);
      await t.pump();
      state.cart.addItem(line());
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(
            home: CheckoutScreen(storeId: 'b1', storeName: 'مطعم الاختبار'),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(CheckoutSignInPanel), findsOneWidget);
      expect(find.text('ملخص الفاتورة'), findsNothing);
      expect(find.text('مراجعة إجمالي الطلب'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await t.pumpWidget(const SizedBox());
      state.dispose();
      expect(t.takeException(), isNull);
    },
  );
  test(
    'provider completes account basket reload before continuation restore',
    () async {
      final state = AppStateProvider(canWarmInvoice: () => false);
      await Future<void>.delayed(Duration.zero);
      state.cart.addItem(line(note: 'ضيف'));
      state.cart.setStoreName('مطعم الضيف');
      final snapshot = state.cart.captureGuestCheckout();
      await state.cart.saveToStorage();
      await signIn('new-account');
      await state.waitForCheckoutCartIdentity();
      expect(state.cart.items, isEmpty);
      expect(state.cart.storeName, isNull);
      expect(
        await state.cart.restoreGuestCheckout(snapshot, 'new-account'),
        GuestCheckoutCartResult.restored,
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.cart.items.single.specialInstructions, 'ضيف');
      state.dispose();
    },
  );
  testWidgets(
    'sign-in panel explains preservation and disables duplicate actions while busy',
    (t) async {
      var taps = 0;
      for (final busy in [false, true]) {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CheckoutSignInPanel(
                storeName: 'مطعم',
                itemCount: 3,
                areaName: 'مركز المناذرة',
                busy: busy,
                onSignIn: () => taps++,
              ),
            ),
          ),
        );
        expect(find.text('3 قطعة في سلتك'), findsOneWidget);
        expect(find.text('منطقة التوصيل: مركز المناذرة'), findsOneWidget);
        await t.ensureVisible(find.text('التحقق بالهاتف والمتابعة'));
        await t.tap(find.text('التحقق بالهاتف والمتابعة'));
        await t.pump();
      }
      expect(taps, 1);
      expect(t.takeException(), isNull);
    },
  );
}
