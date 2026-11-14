import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/phone_link_service.dart';
import 'package:foodapp_user/screens/verified_phone_screen.dart';

class FakeLink extends PhoneLinkService {
  bool fresh = false, pending = false;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add(path);
    if (path == 'status')
      return {
        'phone': '+9647831367435',
        'verified': true,
        'requiresReauthentication': !fresh,
        'pendingSessionId': pending ? 'pending' : null,
      };
    if (path == 'send') return {'sessionId': 'new', 'resendAfter': 60};
    return {'phone': '+9647801234567', 'verified': true};
  }
}

Widget host(Widget child) => MaterialApp(
  home: Directionality(textDirection: TextDirection.rtl, child: child),
);
void main() {
  test(
    'service refreshes credential and canonicalizes phone at request boundary',
    () async {
      final api = PhoneLinkService(
        owner: () => 'owner',
        token: () async => 'fresh',
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer fresh');
          expect(jsonDecode(r.body)['phone'], '+9647831367435');
          return http.Response('{}', 200);
        }),
      );
      await api.call('send', {'phone': '٠٧٨٣١٣٦٧٤٣٥'});
    },
  );
  test(
    'reauthentication is a typed action distinct from losing session',
    () async {
      final api = PhoneLinkService(
        owner: () => 'owner',
        token: () async => 'fresh',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'REAUTH_REQUIRED', 'message': 'تحقق من هويتك'}),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        api.call('send', {'phone': '07831367435'}),
        throwsA(
          isA<PhoneLinkException>().having(
            (e) => e.code,
            'code',
            'REAUTH_REQUIRED',
          ),
        ),
      );
    },
  );
  test('late response from old account cannot be applied', () async {
    String? owner = 'owner';
    final response = Completer<http.Response>();
    final api = PhoneLinkService(
      owner: () => owner,
      token: () async => 'fresh',
      client: MockClient((_) => response.future),
    );
    final request = api.call('status');
    await Future<void>.delayed(Duration.zero);
    owner = 'other';
    response.complete(http.Response('{}', 200));
    await expectLater(
      request,
      throwsA(
        isA<PhoneLinkException>().having(
          (e) => e.code,
          'code',
          'ACCOUNT_CHANGED',
        ),
      ),
    );
  });
  testWidgets(
    'saved session displays current number; recent proof then new OTP without logout',
    (t) async {
      final api = FakeLink();
      String? saved;
      var reauth = 0;
      await t.pumpWidget(
        host(
          VerifiedPhoneScreen(
            service: api,
            currentOwner: () => 'owner',
            reauthenticate: (_, phone) async {
              expect(phone, '+9647831367435');
              reauth++;
              api.fresh = true;
              return true;
            },
            savePhone: (phone) async => saved = phone,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('+9647831367435'), findsOneWidget);
      expect(api.calls, ['status']);
      await t.tap(find.text('تأكيد هويتي للمتابعة'));
      await t.pumpAndSettle();
      expect(reauth, 1);
      await t.enterText(find.byType(TextFormField), '07801234567');
      await t.tap(find.text('إرسال رمز للرقم الجديد'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '123456');
      await t.tap(find.text('تأكيد تغيير الرقم'));
      await t.pumpAndSettle();
      expect(saved, '+9647801234567');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pending operation has resume action and does not resend OTP', (
    t,
  ) async {
    final api = FakeLink()..pending = true;
    await t.pumpWidget(
      host(
        VerifiedPhoneScreen(
          service: api,
          currentOwner: () => 'owner',
          savePhone: (_) async {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('إكمال تحديث الرقم'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(api.calls, ['status']);
    await t.pumpWidget(const SizedBox());
  });
}
