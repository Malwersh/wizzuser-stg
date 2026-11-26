import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/customer_order_complaint_service.dart';
import 'package:foodapp_user/config/api_config.dart';

void main() {
  test('uses protected endpoint and original identity', () async {
    final s = CustomerOrderComplaintService(
      token: () async => 'signed',
      client: MockClient((r) async {
        expect(
          r.url.path,
          ApiConfig.isProduction
              ? '/production/complaints/customer'
              : '/staging/order/cancel',
        );
        expect(r.headers['Authorization'], 'Bearer signed');
        expect(jsonDecode(r.body), {
          'orderId': 'o',
          'action': 'READ',
          if (!ApiConfig.isProduction) 'workflow': 'CUSTOMER_POST_DELIVERY',
        });
        return http.Response('{"success":true,"orderId":"o","version":1}', 200);
      }),
    );
    expect((await s.call('o', {'action': 'READ'}))['version'], 1);
    s.dispose();
  });
  test('rejects another order result', () async {
    final s = CustomerOrderComplaintService(
      token: () async => 'signed',
      client: MockClient(
        (r) async => http.Response('{"success":true,"orderId":"other"}', 200),
      ),
    );
    await expectLater(s.call('o', {'action': 'READ'}), throwsStateError);
    s.dispose();
  });
  test('logout racing response hides previous case', () async {
    String? token = 'signed';
    final s = CustomerOrderComplaintService(
      token: () async => token,
      client: MockClient((r) async {
        token = null;
        return http.Response('{"success":true,"orderId":"o"}', 200);
      }),
    );
    await expectLater(s.call('o', {'action': 'READ'}), throwsStateError);
    s.dispose();
  });
  test(
    'a refreshed access token keeps only the same customer session',
    () async {
      String jwt(String subject, int version) {
        final claims = base64Url
            .encode(utf8.encode(jsonEncode({'sub': subject, 'iat': version})))
            .replaceAll('=', '');
        return 'e30.$claims.test';
      }

      for (final subject in ['customer', 'another-customer']) {
        var token = jwt('customer', 1);
        final service = CustomerOrderComplaintService(
          token: () async => token,
          client: MockClient((request) async {
            token = jwt(subject, 2);
            return http.Response('{"success":true,"orderId":"o"}', 200);
          }),
        );
        final response = service.call('o', {'action': 'READ'});
        if (subject == 'customer') {
          expect((await response)['orderId'], 'o');
        } else {
          await expectLater(response, throwsStateError);
        }
        service.dispose();
      }
    },
  );
  test('server error is not success', () async {
    final s = CustomerOrderComplaintService(
      token: () async => 'signed',
      client: MockClient(
        (r) async => http.Response('{"code":"COMPLAINT_CHANGED"}', 409),
      ),
    );
    await expectLater(s.call('o', {'action': 'OPEN'}), throwsStateError);
    s.dispose();
  });
}
