import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../screens/order_tracking_screen.dart';
import 'notification_navigation.dart';

class ActivityLinkNavigation {
  static const _channel = MethodChannel('com.wiz.wizuserapp/activity_link');
  static bool _ready = false;
  static String? _pending;
  static String? _last;
  static DateTime? _lastAt;

  static String? orderIdFromUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'wizuser' || uri.host != 'orders' ||
        uri.pathSegments.length != 1 || uri.hasQuery || uri.hasFragment) return null;
    final id = uri.pathSegments.single;
    return RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$').hasMatch(id) ? id : null;
  }

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openOrderTracking' && call.arguments is String) {
        receive(call.arguments as String);
      }
    });
    try {
      final url = await _channel.invokeMethod<String>('pendingOrderLink');
      if (url != null) receive(url);
    } on MissingPluginException { /* Other platforms use their notification routes. */ }
  }

  static void receive(String url) {
    final id = orderIdFromUrl(url);
    if (id == null) return;
    if (_last == id && _lastAt != null && DateTime.now().difference(_lastAt!).inSeconds < 2) return;
    _last = id;
    _lastAt = DateTime.now();
    _pending = id;
    _openPending();
  }

  static void ready(bool value) {
    _ready = value;
    if (value) _openPending();
  }

  static void _openPending() {
    if (!_ready || _pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = NotificationNavigation.navigatorKey.currentState;
      if (!_ready || nav == null || _pending == null) return;
      final id = _pending!;
      _pending = null;
      nav.push(MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: id, orderNumber: id)));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
