import 'package:foodapp_user/models/business_model.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/order_rating_service.dart';
import 'package:foodapp_user/screens/order_rating_screen.dart';

void main() {
  test('restaurant verified rating and count survive model caching', () {
    final business=BusinessModel.fromJson({'id':'m1','business_name':'مطعم','rating':4.9,'reviewCount':100,'customerRating':3.5,'customerRatingCount':2});
    expect(business.rating,3.5); expect(business.reviewCount,2);
    final cached=BusinessModel.fromJson(business.toJson());
    expect(cached.rating,3.5); expect(cached.reviewCount,2);
  });
  Map<String, dynamic> eligibility({
    bool driver = true,
    Map<String, dynamic>? review,
  }) => {
    'success': true,
    'orderId': 'o1',
    'merchantName': 'مطعم الاختبار',
    'driverName': 'السائق',
    'driverEligible': driver,
    'review': review,
  };
  OrderRatingService service(
    Future<http.Response> Function(http.Request) handler, {
    String? Function()? owner,
    Future<String?> Function()? token,
  }) => OrderRatingService(
    client: MockClient(handler),
    endpoint: 'https://ratings.invalid/staging',
    owner: owner ?? () => 'user',
    token: token ?? () async => 'valid',
  );
  test(
    'loads eligibility with bearer and encoded path, no caller target IDs',
    () async {
      final s = service((r) async {
        expect(r.method, 'GET');
        expect(r.url.path, '/staging/orders/o1/rating');
        expect(r.headers['Authorization'], 'Bearer valid');
        return http.Response(
          jsonEncode(eligibility()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      expect((await s.load('o1'))['driverEligible'], true);
      s.dispose();
    },
  );
  test('submission sends separate stars and comment only', () async {
    final s = service((r) async {
      expect(r.method, 'POST');
      expect(jsonDecode(r.body), {
        'merchantStars': 4,
        'driverStars': 2,
        'comment': 'جيد',
      });
      return http.Response(
        jsonEncode({'success': true, 'orderId': 'o1', 'review': {}}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await s.submit('o1', merchantStars: 4, driverStars: 2, comment: ' جيد ');
    s.dispose();
  });
  test('signed out identity cannot use transport', () async {
    var calls = 0;
    final s = service((r) async {
      calls++;
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }, owner: () => null);
    await expectLater(s.load('o1'), throwsA(isA<RatingException>()));
    expect(calls, 0);
    s.dispose();
  });
  test('missing fresh token cannot use transport', () async {
    var calls = 0;
    final s = service((r) async {
      calls++;
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }, token: () async => null);
    await expectLater(s.load('o1'), throwsA(isA<RatingException>()));
    expect(calls, 0);
    s.dispose();
  });
  test('account change while token loads prevents request', () async {
    String? owner = 'first';
    final pending = Completer<String?>();
    var calls = 0;
    final s = service(
      (r) async {
        calls++;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      },
      owner: () => owner,
      token: () => pending.future,
    );
    final result = s.load('o1');
    owner = 'second';
    pending.complete('token');
    await expectLater(result, throwsA(isA<RatingException>()));
    expect(calls, 0);
    s.dispose();
  });
  test('late response from previous account never reaches screen', () async {
    String? owner = 'first';
    final pending = Completer<http.Response>();
    final s = service((r) => pending.future, owner: () => owner);
    final result = s.load('o1');
    await Future<void>.delayed(Duration.zero);
    owner = 'second';
    pending.complete(
      http.Response(
        jsonEncode(eligibility()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await expectLater(result, throwsA(isA<RatingException>()));
    s.dispose();
  });
  test('wrong order and server failure never report saved', () async {
    for (final payload in [
      {'success': true, 'orderId': 'other'},
      {'success': false, 'code': 'ALREADY_RATED'},
    ]) {
      final s = service(
        (r) async => http.Response(
          jsonEncode(payload),
          payload['success'] == true ? 200 : 409,
        ),
      );
      await expectLater(
        s.submit('o1', merchantStars: 5),
        throwsA(isA<RatingException>()),
      );
      s.dispose();
    }
  });
  testWidgets(
    'separate stars required; no optimistic saved message; successful submission locks review',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var posts = 0;
      final pending = Completer<http.Response>();
      final s = service((r) async {
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode(eligibility()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        posts++;
        return pending.future;
      });
      await tester.pumpWidget(
        MaterialApp(home: OrderRatingScreen(orderId: 'o1', service: s)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('4 من 5 — المطعم'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('5 من 5 — السائق'));
      await tester.pump();
      await tester.ensureVisible(find.text('إرسال التقييم'));
      await tester.tap(find.text('إرسال التقييم'));
      await tester.pump();
      expect(posts, 1);
      expect(find.text('شكرًا، تم حفظ تقييمك'), findsNothing);
      pending.complete(
        http.Response(
          jsonEncode({'success': true, 'orderId': 'o1', 'review': {}}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('شكرًا، تم حفظ تقييمك'), findsOneWidget);
      expect(find.text('إرسال التقييم'), findsNothing);
    },
  );
  testWidgets('merchant delivered orders do not invent a driver rating', (
    tester,
  ) async {
    final s = service(
      (r) async => http.Response(
        jsonEncode(eligibility(driver: false)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: OrderRatingScreen(orderId: 'o1', service: s)),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('5 من 5 — السائق'), findsNothing);
    await tester.tap(find.byTooltip('3 من 5 — المطعم'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets('stored review is restored read-only on reopen', (tester) async {
    final s = service(
      (r) async => http.Response(
        jsonEncode(
          eligibility(
            review: {
              'merchantStars': 4,
              'driverStars': 3,
              'comment': 'ملاحظة محفوظة',
            },
          ),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: OrderRatingScreen(orderId: 'o1', service: s)),
    );
    await tester.pumpAndSettle();
    expect(find.text('شكرًا، تم حفظ تقييمك'), findsOneWidget);
    expect(find.text('إرسال التقييم'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
  });
  testWidgets(
    'failed save keeps selected stars and comment for a deliberate retry',
    (tester) async {
      final s = service(
        (r) async =>
            r.method == 'GET'
                ? http.Response(
                  jsonEncode(eligibility(driver: false)),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                )
                : http.Response(
                  '{"success":false,"code":"RATINGS_UNAVAILABLE"}',
                  503,
                ),
      );
      await tester.pumpWidget(
        MaterialApp(home: OrderRatingScreen(orderId: 'o1', service: s)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('4 من 5 — المطعم'));
      await tester.enterText(find.byType(TextField), 'نصي محفوظ');
      await tester.ensureVisible(find.text('إرسال التقييم'));
      await tester.tap(find.text('إرسال التقييم'));
      await tester.pumpAndSettle();
      expect(find.text('شكرًا، تم حفظ تقييمك'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'نصي محفوظ',
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );
}
