import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/models/customer_legal_bundle.dart';
import 'package:foodapp_user/services/customer_legal_service.dart';
import 'package:foodapp_user/screens/customer_legal_screen.dart';
import 'package:foodapp_user/screens/customer_phone_auth_screen.dart';
import 'package:foodapp_user/services/customer_phone_auth_service.dart';

Map<String, dynamic> legalFixture() => jsonDecode(
  File('test/fixtures/customer_legal_published_344.json').readAsStringSync(),
);

class ReadyLegal extends CustomerLegalService {
  @override
  Future<CustomerLegalBundle> load({bool refresh = false}) async =>
      CustomerLegalBundle.fromJson(legalFixture());
}

class FailedLegal extends CustomerLegalService {
  @override
  Future<CustomerLegalBundle> load({bool refresh = false}) async =>
      throw StateError('unavailable');
}

class RegistrationFake extends CustomerPhoneAuthService {
  int calls = 0;
  Map<String, dynamic>? receivedPin;
  bool stale = false;
  @override
  Future<void> send(String phone) async {}
  @override
  Future<bool> verify(
    String code, {
    String? name,
    bool accepted = false,
  }) async {
    calls++;
    receivedPin = enrollmentPolicy?.pin;
    if (stale)
      throw const CustomerPhoneAuthException(
        'تحدثت السياسات',
        'LEGAL_VERSION_CHANGED',
      );
    return false;
  }
}

void main() {
  test(
    'published policy hash matches central contract and rejects substituted content',
    () {
      final raw = legalFixture(), b = CustomerLegalBundle.fromJson(raw);
      expect(b.documents.length, 4);
      raw['brand']['companyName'] = 'changed';
      expect(() => CustomerLegalBundle.fromJson(raw), throwsFormatException);
    },
  );
  test(
    'policy fetch is public, validates integrity, and explicitly refreshes cached revision',
    () async {
      var count = 0;
      final service = CustomerLegalService(
        baseUrl: 'https://legal.test',
        client: MockClient((r) async {
          count++;
          expect(r.url.path, '/legal');
          expect(r.headers.containsKey('authorization'), false);
          return http.Response.bytes(
            utf8.encode(jsonEncode({'bundle': legalFixture()})),
            200,
          );
        }),
      );
      await service.load();
      await service.load();
      expect(count, 1);
      await service.load(refresh: true);
      expect(count, 2);
    },
  );
  test(
    'phone registration transmits exact published revision and explicit usage, terms and privacy flags',
    () async {
      final posts = <Map<String, dynamic>>[];
      final service = CustomerPhoneAuthService(
        client: MockClient((r) async {
          posts.add(jsonDecode(r.body));
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/send')
                  ? {'sessionId': 's'}
                  : {'needsName': true},
            ),
            200,
          );
        }),
      );
      service.enrollmentPolicy = CustomerLegalBundle.fromJson(legalFixture());
      await service.send('07831367435');
      await service.verify('123456', name: 'مستخدم جديد', accepted: true);
      expect(posts.last['legalAcceptance'], service.enrollmentPolicy!.pin);
      expect(posts.last['usageAccepted'], true);
      expect(posts.last['termsAccepted'], true);
      expect(posts.last['privacyAccepted'], true);
    },
  );
  testWidgets(
    'stale registration policy clears consent and reloads text without discarding entered name or OTP',
    (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final auth = RegistrationFake()..stale = true;
      await t.pumpWidget(
        MaterialApp(
          home: CustomerPhoneAuthScreen(
            registration: true,
            service: auth,
            legalService: ReadyLegal(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '07831367435');
      await t.ensureVisible(find.text('إرسال رمز التحقق'));
      await t.tap(find.text('إرسال رمز التحقق'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(1), '123456');
      await t.enterText(find.byType(TextField).at(2), 'مستخدم جديد');
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.tap(find.byType(CheckboxListTile));
      await t.ensureVisible(find.text('تأكيد ومتابعة'));
      await t.tap(find.text('تأكيد ومتابعة'));
      await t.pumpAndSettle();
      expect(
        auth.receivedPin,
        CustomerLegalBundle.fromJson(legalFixture()).pin,
      );
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(
        t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '123456',
      );
      expect(
        t.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        'مستخدم جديد',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'policy hub lists all four pages; page ends with company logo, name and publication version',
    (t) async {
      await t.pumpWidget(
        MaterialApp(home: CustomerLegalScreen(service: ReadyLegal())),
      );
      await t.pumpAndSettle();
      for (final title in [
        'سياسة الاستخدام',
        'الشروط والأحكام',
        'سياسة الخصوصية',
        'سياسة الإلغاء والإرجاع والتعويض',
      ])
        expect(find.text(title), findsOneWidget);
      await t.tap(find.text('سياسة الاستخدام'));
      await t.pumpAndSettle();
      expect(find.textContaining('الإصدار 1'), findsOneWidget);
      await t.dragUntilVisible(
        find.text('شركة الانطلاق الخاطف'),
        find.byType(ListView).last,
        const Offset(0, -500),
      );
      expect(find.byType(Image), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'registration consent is unchecked and links open the same published policy without selecting checkbox',
    (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final auth = RegistrationFake();
      await t.pumpWidget(
        MaterialApp(
          home: CustomerPhoneAuthScreen(
            registration: true,
            service: auth,
            legalService: ReadyLegal(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await t.tap(find.text('سياسة الاستخدام'));
      await t.pumpAndSettle();
      expect(find.textContaining('الإصدار 1'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(auth.calls, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unavailable policies disable consent and show retry rather than a fabricated current text',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: CustomerPhoneAuthScreen(
            registration: true,
            service: RegistrationFake(),
            legalService: FailedLegal(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
        isNull,
      );
      expect(find.text('إعادة تحميل السياسات'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'policy content remains readable at narrow width and large text',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          builder:
              (c, w) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: TextScaler.linear(1.8)),
                child: w!,
              ),
          home: CustomerLegalScreen(
            documentId: 'PRIVACY',
            bundle: CustomerLegalBundle.fromJson(legalFixture()),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
