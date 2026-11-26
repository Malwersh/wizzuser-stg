import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/storefront_pricing.dart';
import 'package:foodapp_user/widgets/storefront_value.dart';
import 'package:foodapp_user/widgets/discovery/customer_components.dart';
import 'package:foodapp_user/widgets/discovery/home_discovery_header.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'horizontal section accommodates pending and failed pricing $width/$scale',
        (t) async {
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final pending = Completer<http.Response>();
          final pricing = StorefrontPricing(
            account: () => 'u',
            token: () => 't',
            addressId: () => 'a',
            addressRevision: () => 'v',
            regionId: () => 'r',
            listenToAddress: false,
            client: MockClient((_) => pending.future),
          );
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: Column(
                        children: [
                          DiscoveryHorizontalList(
                            itemCount: 2,
                            itemBuilder:
                                (_, i) => SizedBox(
                                  width: 228,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        height: 132,
                                        child: ColoredBox(color: Colors.blue),
                                      ),
                                      const Text(
                                        'مطعم باسم طويل لاختبار التنسيق',
                                      ),
                                      for (final field in [
                                        StorefrontField.arrival,
                                        StorefrontField.fee,
                                      ])
                                        StorefrontValue(
                                          branchId: 'b',
                                          items: const [],
                                          field: field,
                                          pricing: pricing,
                                          compact: true,
                                        ),
                                    ],
                                  ),
                                ),
                          ),
                          const SizedBox(
                            key: ValueKey('next-section'),
                            height: 100,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          expect(t.takeException(), isNull);
          pending.complete(http.Response('{"success":false}', 503));
          await t.pumpAndSettle();
          expect(find.text('إعادة المحاولة'), findsWidgets);
          expect(t.takeException(), isNull);
          final cardBottom =
              t.getBottomLeft(find.byType(DiscoveryHorizontalList)).dy;
          expect(
            t.getTopLeft(find.byKey(const ValueKey('next-section'))).dy,
            greaterThanOrEqualTo(cardBottom),
          );
          await t.pumpWidget(const SizedBox());
          pricing.dispose();
        },
      );
    }
  }
  testWidgets('home header uses opaque white background', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDiscoveryHeader(
            address: 'المناذرة',
            onAddress: () {},
            onNotifications: () {},
            onAccount: () {},
            onCart: () {},
            unread: false,
          ),
        ),
      ),
    );
    final decoration =
        t
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(HomeDiscoveryHeader),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.gradient, isNull);
  });
}
