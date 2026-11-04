import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/services/android_order_tracking.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            calls.add(call);
            if (call.method == 'getNotificationAppLaunchDetails')
              return {'notificationLaunchedApp': false};
            return true;
          },
        );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  Map<String, dynamic> v(String id, String status, int time) => {
    'orderId': id,
    'status': status,
    'statusLabel': 'اختبار',
    'etaText': 'وصول تقديري',
    'updatedAt': DateTime.utc(2026, 10, 17, 20, 0, time).toIso8601String(),
    'progress': 0.4,
  };
  test(
    'terminal notification is removed and a delayed earlier push cannot revive it',
    () async {
      await AndroidOrderTracking.show(v('a', 'preparing', 1));
      await AndroidOrderTracking.show(v('a', 'delivered', 3));
      await AndroidOrderTracking.show(v('a', 'preparing', 2));
      expect(calls.where((c) => c.method == 'show').length, 1);
      expect(calls.where((c) => c.method == 'cancel').length, 1);
    },
  );
  test(
    'different orders get distinct stable IDs and silent ongoing progress',
    () async {
      await AndroidOrderTracking.show(v('a', 'preparing', 1));
      await AndroidOrderTracking.show(v('b', 'preparing', 1));
      await AndroidOrderTracking.show(v('a', 'preparing', 2));
      final shows = calls.where((c) => c.method == 'show').toList();
      expect(shows[0].arguments['id'], shows[2].arguments['id']);
      expect(shows[0].arguments['id'], isNot(shows[1].arguments['id']));
      final details = shows.first.arguments['platformSpecifics'];
      expect(details['ongoing'], true);
      expect(details['playSound'], false);
    },
  );
  test('background push from another account is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'current_user_id': 'owner',
      'is_logged_in': true,
    });
    await AndroidOrderTracking.fromPush({
      'userId': 'other',
      'tracking': jsonEncode(v('a', 'preparing', 1)),
    });
    expect(calls.where((c) => c.method == 'show'), isEmpty);
    await AndroidOrderTracking.fromPush({
      'userId': 'owner',
      'tracking': jsonEncode(v('a', 'preparing', 1)),
    });
    expect(calls.where((c) => c.method == 'show').length, 1);
  });
}
