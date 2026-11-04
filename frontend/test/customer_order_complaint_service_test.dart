import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/customer_order_complaint_service.dart';

void main() {
  test('uses protected endpoint and original identity', () async {
    final s = CustomerOrderComplaintService(
      token: () async => 'signed',
      client: MockClient((r) async {
        expect(r.url.path, '/staging/order/cancel');
        expect(r.headers['Authorization'], 'Bearer signed');
        expect(jsonDecode(r.body), {
          'orderId': 'o',
          'action': 'READ',
          'workflow': 'CUSTOMER_POST_DELIVERY',
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
