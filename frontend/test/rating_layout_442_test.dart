import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/screens/order_rating_screen.dart';
import 'package:foodapp_user/services/order_rating_service.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'rating remains usable on narrow RTL screen with long names at $scale',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final service = OrderRatingService(
          client: MockClient(
            (r) async => http.Response(
              jsonEncode({
                'success': true,
                'orderId': 'o',
                'merchantName': 'مطعم الاختبار ذو الاسم الطويل جدًا',
                'driverName': 'السائق محمد صاحب الحساب التجريبي',
                'driverEligible': true,
                'review': null,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
          endpoint: 'https://ratings.invalid/staging',
          owner: () => 'u',
          token: () async => 't',
        );
        await t.pumpWidget(
          MaterialApp(
            builder:
                (c, w) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: w!,
                ),
            home: OrderRatingScreen(orderId: 'o', service: service),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(
          find.byTooltip('4 من 5 — المطعم'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('4 من 5 — المطعم'));
        await t.pump();
        await t.scrollUntilVisible(
          find.byTooltip('5 من 5 — السائق'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('5 من 5 — السائق'));
        await t.pump();
        await t.scrollUntilVisible(
          find.text('إرسال التقييم'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
