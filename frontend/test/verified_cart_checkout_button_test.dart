import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/storefront_pricing.dart';
import 'package:foodapp_user/widgets/verified_cart_checkout_button.dart';

Map<String, dynamic> preview() => {
  'schemaVersion': 1,
  'kind': 'STOREFRONT_PREVIEW',
  'branchId': 'b',
  'addressId': 'a',
  'expiresAt': '2030-01-01T00:00:00Z',
  'customerDeliveryFee': {
    'moneySchemaVersion': 1,
    'currency': 'IQD',
    'scale': 1000,
    'minorAmount': 1500000,
  },
  'roadDistanceMeters': 1000,
  'deliveryDurationSeconds': 300,
  'preparationMinutes': 15,
};
void main() {
  testWidgets(
    'waits for server success without displaying a premature failure',
    (tester) async {
      final pending = Completer<http.Response>();
      var advances = 0;
      final pricing = StorefrontPricing(
        account: () => 'u',
        token: () => 't',
        addressId: () => 'a',
        addressRevision: () => 'v',
        listenToAddress: false,
        client: MockClient((_) => pending.future),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VerifiedCartCheckoutButton(
              branchId: 'b',
              items: const [],
              subtotal: 7000,
              pricing: pricing,
              onVerified: () => advances++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('التحقق من تفاصيل الطلب'));
      await tester.pump();
      expect(find.text('جارٍ التحقق من تفاصيل الطلب…'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(advances, 0);
      pending.complete(
        http.Response(jsonEncode({'success': true, 'preview': preview()}), 200),
      );
      await tester.pumpAndSettle();
      expect(advances, 1);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      pricing.dispose();
    },
  );
  testWidgets('actual server failure shows error and does not advance', (
    tester,
  ) async {
    var advances = 0;
    final pricing = StorefrontPricing(
      account: () => 'u',
      token: () => 't',
      addressId: () => 'a',
      addressRevision: () => 'v',
      listenToAddress: false,
      client: MockClient((_) async => http.Response('{"success":false}', 503)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerifiedCartCheckoutButton(
            branchId: 'b',
            items: const [],
            subtotal: 7000,
            pricing: pricing,
            onVerified: () => advances++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('التحقق من تفاصيل الطلب'));
    await tester.pumpAndSettle();
    expect(advances, 0);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pricing.dispose();
  });
  testWidgets('enforces authoritative minimum before continuing', (
    tester,
  ) async {
    var advances = 0;
    final pricing = StorefrontPricing(
      account: () => 'u',
      token: () => 't',
      addressId: () => 'a',
      addressRevision: () => 'v',
      listenToAddress: false,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'preview': {
              ...preview(),
              'minimumOrderAmountIqd': 10000,
              'goodsGross': {'minorAmount': 7000000},
            },
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerifiedCartCheckoutButton(
            branchId: 'b',
            items: const [],
            subtotal: 12000,
            pricing: pricing,
            onVerified: () => advances++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('التحقق من تفاصيل الطلب'));
    await tester.pumpAndSettle();
    expect(advances, 0);
    expect(find.textContaining('أضف 3000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pricing.dispose();
  });
}
