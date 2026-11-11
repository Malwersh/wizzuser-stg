import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/customer_notification_preferences.dart';

void main() {
  test(
    'saved false survives server round trip with fresh credentials',
    () async {
      final service = CustomerNotificationPreferencesService(
        owner: () => 'owner',
        token: () async => 'fresh',
        client: MockClient((r) async {
          expect(r.method, 'PUT');
          expect(r.headers['Authorization'], 'Bearer fresh');
          expect(
            jsonDecode(
              r.body,
            )['notification_settings']['promotion_notifications'],
            false,
          );
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'owner',
                'notification_settings': {
                  'promotion_notifications': false,
                  'order_notifications': true,
                },
              },
            }),
            200,
          );
        }),
      );
      final result = await service.save(
        const CustomerNotificationPreferences(promotions: false),
      );
      expect(result.promotions, false);
      expect(result.orders, true);
      service.close();
    },
  );
  test(
    'switching identity while loading discards old account response',
    () async {
      String owner = 'first';
      final response = Completer<http.Response>();
      final service = CustomerNotificationPreferencesService(
        owner: () => owner,
        token: () async => 'fresh',
        client: MockClient((_) => response.future),
      );
      final future = service.load();
      await Future<void>.delayed(Duration.zero);
      owner = 'second';
      response.complete(
        http.Response(
          jsonEncode({
            'success': true,
            'data': {'id': 'first'},
          }),
          200,
        ),
      );
      await expectLater(future, throwsStateError);
      service.close();
    },
  );
  test('failed save is not reported as success', () async {
    final service = CustomerNotificationPreferencesService(
      owner: () => 'owner',
      token: () async => 'fresh',
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      service.save(const CustomerNotificationPreferences()),
      throwsStateError,
    );
    service.close();
  });
  test('guest never calls authenticated preference endpoint', () async {
    var calls = 0;
    final service = CustomerNotificationPreferencesService(
      owner: () => null,
      token: () async => 'none',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(service.load(), throwsStateError);
    expect(calls, 0);
    service.close();
  });
  test('notification choices never suppress unrelated support messages', () {
    const p = CustomerNotificationPreferences(orders: false, promotions: false);
    expect(p.allows({'type': 'campaign_offer'}), false);
    expect(p.allows({'type': 'order_update'}), false);
    expect(p.allows({'type': 'support_reply'}), true);
  });
}
