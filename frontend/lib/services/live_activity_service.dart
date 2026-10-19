import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/order_model.dart';
import 'session_service.dart';
import 'android_order_tracking.dart';

class LiveActivityService {
  static const enabled = bool.fromEnvironment(
    'ORDER_LIVE_ACTIVITY_ENABLED',
    defaultValue: false,
  );
  static const MethodChannel _methodChannel = MethodChannel(
    'com.wiz.wizuserapp/live_activity',
  );
  static const EventChannel _tokenChannel = EventChannel(
    'com.wiz.wizuserapp/live_activity_token',
  );

  static StreamSubscription<dynamic>? _tokenSub;
  static String? _pendingOrderId;
  static String? _pendingGuestToken;

  /// Persist the guest token returned by the backend for guest orders.
  /// Keeps it in memory and in SharedPreferences so token registration can use it.
  static Future<void> setGuestToken(String token) async {
    if (token.isEmpty) return;
    _pendingGuestToken = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('guest_token', token);
    } catch (_) {
      // ignore
    }
  }

  static Future<void> initialize() async {
    await AndroidOrderTracking.initialize(requestPermission:true);
    if (!enabled || kIsWeb || !Platform.isIOS) return;
    _tokenSub?.cancel();
    _tokenSub = _tokenChannel.receiveBroadcastStream().listen(
      _onActivityPushToken,
      onError: (dynamic e) => debugPrint('LiveActivity token stream error: $e'),
    );
  }

  static Future<void> dispose() async {
    await _tokenSub?.cancel();
    _tokenSub = null;
  }

  static Future<Map<String, dynamic>?> start({
    required String orderId,
    required String status,
    required String statusLabel,
    required String storeName,
    required String orderNumber,
    String? etaText,
    double? arrivalEarliestEpoch,
    double? arrivalLatestEpoch,
    double progress = 0.0,
  }) async {
    if (!enabled || kIsWeb || !Platform.isIOS) return null;
    try {
      _pendingOrderId = orderId;
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'startOrderLiveActivity',
        <String, dynamic>{
          'orderId': orderId,
          'status': status,
          'statusLabel': statusLabel,
          'storeName': storeName,
          'orderNumber': orderNumber,
          'etaText': etaText ?? '',
          if (arrivalEarliestEpoch != null)
            'arrivalEarliestEpoch': arrivalEarliestEpoch,
          if (arrivalLatestEpoch != null)
            'arrivalLatestEpoch': arrivalLatestEpoch,
          'progress': progress,
        },
      );
      return result?.cast<String, dynamic>();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('LiveActivity start error: ${e.code} - ${e.message}');
      return null;
    }
  }

  static Future<void> update({
    required String orderId,
    String? status,
    String? statusLabel,
    String? storeName,
    String? orderNumber,
    String? etaText,
    double? arrivalEarliestEpoch,
    double? arrivalLatestEpoch,
    double? progress,
  }) async {
    if (!enabled || kIsWeb || !Platform.isIOS) return;
    try {
      await _methodChannel
          .invokeMethod('updateOrderLiveActivity', <String, dynamic>{
            'orderId': orderId,
            if (status != null) 'status': status,
            if (statusLabel != null) 'statusLabel': statusLabel,
            if (storeName != null) 'storeName': storeName,
            if (orderNumber != null) 'orderNumber': orderNumber,
            if (etaText != null) 'etaText': etaText,
            if (arrivalEarliestEpoch != null)
              'arrivalEarliestEpoch': arrivalEarliestEpoch,
            if (arrivalLatestEpoch != null)
              'arrivalLatestEpoch': arrivalLatestEpoch,
            if (progress != null) 'progress': progress,
          });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('LiveActivity update error: ${e.code} - ${e.message}');
    }
  }

  static Future<void> end(String orderId) async {
    await AndroidOrderTracking.end(orderId);
    if (!enabled || kIsWeb || !Platform.isIOS) return;
    try {
      await _methodChannel.invokeMethod(
        'endOrderLiveActivity',
        <String, dynamic>{'orderId': orderId},
      );
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('LiveActivity end error: ${e.code} - ${e.message}');
    }
  }

  /// Start a Live Activity for a newly created order.
  static Future<void> startForOrder(OrderModel order) async {
    if (isTerminal(order.status)) return;
    await _android(order);
    await start(
      orderId: order.id,
      status: order.status.value,
      statusLabel: order.status.arabicName,
      storeName: order.storeName,
      orderNumber: order.orderNumber,
      etaText: etaText(order),
      arrivalEarliestEpoch: _arrival(order, false),
      arrivalLatestEpoch: _arrival(order, true),
      progress: statusProgress(order.status),
    );
  }

  /// Push the current order state to the Live Activity, ending it if terminal.
  static Future<void> syncOrder(OrderModel order) async {
    await _android(order);
    await update(
      orderId: order.id,
      status: order.status.value,
      statusLabel: order.status.arabicName,
      storeName: order.storeName,
      orderNumber: order.orderNumber,
      etaText: etaText(order),
      arrivalEarliestEpoch: _arrival(order, false),
      arrivalLatestEpoch: _arrival(order, true),
      progress: statusProgress(order.status),
    );
    if (isTerminal(order.status)) {
      await end(order.id);
    }
  }

  static Future<void> _android(OrderModel order) async {
    await AndroidOrderTracking.show({'orderId':order.id,'status':order.status.value,'statusLabel':order.status.arabicName,'storeName':order.storeName,'orderNumber':order.orderNumber,'etaText':etaText(order),'arrivalLatestEpoch':_arrival(order,true),'progress':statusProgress(order.status),'updatedAt':(order.updatedAt??order.createdAt).toIso8601String()});
  }

  static bool isTerminal(OrderStatus status) {
    return [
      OrderStatus.delivered,
      OrderStatus.cancelled,
      OrderStatus.failed,
      OrderStatus.expired,
      OrderStatus.rejected,
    ].contains(status);
  }

  static double? _arrival(OrderModel order, bool latest) {
    if (order.status == OrderStatus.pending ||
        order.driverSearchUnavailable ||
        isTerminal(order.status))
      return null;
    final date =
        DateTime.tryParse(
          order.deliveryEstimate?[latest ? 'latestAt' : 'earliestAt']
                  ?.toString() ??
              '',
        ) ??
        order.estimatedDeliveryTime;
    return date == null || !date.isAfter(DateTime.now())
        ? null
        : date.millisecondsSinceEpoch / 1000;
  }

  static Future<void> endAll() async {
    await AndroidOrderTracking.clear();
    if (!enabled || kIsWeb || !Platform.isIOS) return;
    try {
      await _methodChannel.invokeMethod('endAllOrderLiveActivities');
    } catch (_) {}
  }

  static String etaText(OrderModel order) {
    if (order.status == OrderStatus.pending) return 'بانتظار موافقة المطعم';
    if (order.driverSearchUnavailable) return 'بانتظار سائق';
    final early =
        DateTime.tryParse(
          order.deliveryEstimate?['earliestAt']?.toString() ?? '',
        ) ??
        order.estimatedDeliveryTime;
    final late =
        DateTime.tryParse(
          order.deliveryEstimate?['latestAt']?.toString() ?? '',
        ) ??
        early;
    if (late == null) return 'يجري تقدير وقت الوصول';
    if (!late.isAfter(DateTime.now())) return 'يجري تحديث وقت الوصول';
    String time(DateTime date) {
      final d = date.toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    return early == null || early == late
        ? 'وصول تقديري ${time(late)}'
        : 'وصول تقديري ${time(early)}–${time(late)}';
  }

  static double statusProgress(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 0.1;
      case OrderStatus.confirmed:
        return 0.25;
      case OrderStatus.preparing:
        return 0.4;
      case OrderStatus.readyForPickup:
        return 0.5;
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.headingToStore:
        return 0.6;
      case OrderStatus.arrivedAtStore:
        return 0.65;
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
      case OrderStatus.headingToCustomer:
        return 0.8;
      case OrderStatus.arrivedAtCustomer:
        return 0.95;
      case OrderStatus.delivered:
        return 1.0;
      case OrderStatus.cancelled:
      case OrderStatus.failed:
      case OrderStatus.expired:
      case OrderStatus.rejected:
        return 1.0;
      default:
        return 0.0;
    }
  }

  static Future<void> _onActivityPushToken(dynamic token) async {
    final orderId =
        token is Map ? token['orderId']?.toString() : _pendingOrderId;
    token = token is Map ? token['token'] : token;
    if (token == null || token is! String || token.isEmpty) return;
    if (orderId == null || orderId.isEmpty) return;

    if (!enabled) return;
    final userId = SessionService.instance.currentUserId;
    final isGuest = SessionService.instance.isGuest;

    String? authToken;
    String? guestToken;

    if (isGuest) {
      // Prefer the in-memory token from this session's order, else fall back to storage.
      guestToken = _pendingGuestToken;
      if (guestToken == null || guestToken.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        guestToken = prefs.getString('guest_token');
      }
    } else {
      authToken =
          SessionService.instance.idToken ??
          SessionService.instance.accessToken;
    }

    if (authToken == null && guestToken == null) return;
    final uri = Uri.parse(
      '${ApiConfig.centralPushApiBaseUrl}/live-activity/register',
    );

    final payload = <String, dynamic>{
      'orderId': orderId,
      'activityPushToken': token,
      'platform': 'ios',
      'app': 'user',
      'env': ApiConfig.environment,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
      if (guestToken != null && guestToken.isNotEmpty) 'guestToken': guestToken,
    };

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (authToken != null && authToken.isNotEmpty)
          'Authorization': 'Bearer $authToken',
      };
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));
      debugPrint('LiveActivity token register: ${resp.statusCode}');
    } on TimeoutException {
      debugPrint('LiveActivity token register timed out');
    } catch (e) {
      debugPrint('LiveActivity token register error: $e');
    }
  }
}
