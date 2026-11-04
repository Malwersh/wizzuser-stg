import 'dart:convert';
import 'package:flutter/material.dart';
import 'notification_navigation.dart';
import '../screens/order_tracking_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Silent, per-order progress notification, updated from committed server state.
class AndroidOrderTracking {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _key = 'android_order_tracking_v1';
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<void> initialize({bool requestPermission = false}) async {
    if (!supported) return;
    if (!_ready) {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) async {
          final id = r.payload;
          if (id == null || id.isEmpty) return;
          final nav = NotificationNavigation.navigatorKey.currentState;
          if (nav != null) {
            await nav.push(
              MaterialPageRoute(
                builder:
                    (_) => OrderTrackingScreen(orderId: id, orderNumber: id),
              ),
            );
          } else {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('pendingOrderFromPushTap', id);
            await prefs.setInt('pendingTabIndexFromPushTap', 1);
          }
        },
      );
      _ready = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final id = launch?.notificationResponse?.payload;
        if (id != null && id.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pendingOrderFromPushTap', id);
          await prefs.setInt('pendingTabIndexFromPushTap', 1);
        }
      }
    }
    if (requestPermission)
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
  }

  static Future<Map<String, dynamic>> _state() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return Map<String, dynamic>.from(jsonDecode(p.getString(_key) ?? '{}'));
  }

  static Future<void> show(Map<String, dynamic> v) async {
    if (!supported) return;
    await initialize();
    final orderId = v['orderId']?.toString() ?? '';
    if (orderId.isEmpty) return;
    final state = await _state();
    final old = state[orderId] as Map?;
    final revision =
        DateTime.tryParse(
          v['updatedAt']?.toString() ?? '',
        )?.millisecondsSinceEpoch;
    if (revision == null ||
        old != null && revision < (old['revision'] as num).toInt())
      return;
    final terminal = [
      'delivered',
      'cancelled',
      'failed',
      'expired',
      'rejected',
      'returned',
    ].contains(v['status']);
    // Stable local IDs allocated without hash collisions. Keep terminal tombstones
    // so delayed delivery cannot resurrect a completed order.
    final id =
        old?['id'] ??
        ((state.values.fold<int>(41000, (m, e) => e['id'] > m ? e['id'] : m)) +
            1);
    state[orderId] = {'id': id, 'revision': revision, 'terminal': terminal};
    if (old?['terminal'] == true && !terminal) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state));
    if (terminal) {
      await _plugin.cancel(id);
      return;
    }
    final latest = (v['arrivalLatestEpoch'] as num?)?.toDouble();
    final eta =
        latest != null && latest * 1000 <= DateTime.now().millisecondsSinceEpoch
            ? 'يجري تحديث وقت الوصول'
            : v['etaText']?.toString() ?? 'يجري تقدير وقت الوصول';
    final title = v['storeName']?.toString();
    final text = '${v['statusLabel'] ?? 'تحديث الطلب'} • $eta';
    await _plugin.show(
      id,
      title == null || title.isEmpty ? 'تتبع طلبك' : title,
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'order_tracking_v1',
          'تتبع الطلبات',
          channelDescription: 'حالة طلبك ووقت الوصول المتوقع',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: (((v['progress'] as num?) ?? 0) * 100).round().clamp(
            0,
            100,
          ),
          visibility: NotificationVisibility.private,
          styleInformation: BigTextStyleInformation(text, contentTitle: title),
          subText: 'طلب #${v['orderNumber'] ?? orderId}',
        ),
      ),
      payload: orderId,
    );
  }

  static Future<void> fromPush(Map<String, dynamic> data) async {
    if (!supported || data['tracking'] == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getString('current_user_id') != data['userId'] ||
        prefs.getBool('is_logged_in') != true)
      return;
    final v = jsonDecode(data['tracking'].toString());
    if (v is Map) await show(Map<String, dynamic>.from(v));
  }

  static Future<void> end(String id) async {
    if (!supported) return;
    await initialize();
    final state = await _state();
    final item = state[id];
    if (item != null) await _plugin.cancel(item['id']);
  }

  static Future<void> clear() async {
    if (!supported) return;
    await initialize();
    final s = await _state();
    for (final v in s.values) {
      await _plugin.cancel(v['id']);
    }
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
