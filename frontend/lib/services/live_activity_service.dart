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

class LiveActivityService {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.wiz.wizuserapp/live_activity',
  );
  static const EventChannel _tokenChannel = EventChannel(
    'com.wiz.wizuserapp/live_activity_token',
  );

  static StreamSubscription<dynamic>? _tokenSub;
  static String? _pendingOrderId;

  static Future<void> initialize() async {
    if (!Platform.isIOS) return;
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
    double progress = 0.0,
  }) async {
    if (!Platform.isIOS) return null;
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
          'progress': progress,
        },
      );
      return result?.cast<String, dynamic>();
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
    double? progress,
  }) async {
    if (!Platform.isIOS) return;
    try {
      await _methodChannel.invokeMethod(
        'updateOrderLiveActivity',
        <String, dynamic>{
          'orderId': orderId,
          if (status != null) 'status': status,
          if (statusLabel != null) 'statusLabel': statusLabel,
          if (storeName != null) 'storeName': storeName,
          if (orderNumber != null) 'orderNumber': orderNumber,
          if (etaText != null) 'etaText': etaText,
          if (progress != null) 'progress': progress,
        },
      );
    } on PlatformException catch (e) {
      debugPrint('LiveActivity update error: ${e.code} - ${e.message}');
    }
  }

  static Future<void> end(String orderId) async {
    if (!Platform.isIOS) return;
    try {
      await _methodChannel.invokeMethod(
        'endOrderLiveActivity',
        <String, dynamic>{'orderId': orderId},
      );
    } on PlatformException catch (e) {
      debugPrint('LiveActivity end error: ${e.code} - ${e.message}');
    }
  }

  /// Start a Live Activity for a newly created order.
  static Future<void> startForOrder(OrderModel order) async {
    final etaMinutes = order.estimatedDeliveryTime
            ?.difference(order.createdAt)
            .inMinutes ??
        30;
    await start(
      orderId: order.id,
      status: order.status.value,
      statusLabel: order.status.arabicName,
      storeName: order.storeName,
      orderNumber: order.orderNumber,
      etaText: 'التوصيل المتوقع خلال $etaMinutes دقيقة',
      progress: statusProgress(order.status),
    );
  }

  /// Push the current order state to the Live Activity, ending it if terminal.
  static Future<void> syncOrder(OrderModel order) async {
    await update(
      orderId: order.id,
      status: order.status.value,
      statusLabel: order.status.arabicName,
      storeName: order.storeName,
      orderNumber: order.orderNumber,
      etaText: etaText(order),
      progress: statusProgress(order.status),
    );
    if (isTerminal(order.status)) {
      await end(order.id);
    }
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

  static String etaText(OrderModel order) {
    final estimated = order.estimatedDeliveryTime;
    if (estimated == null) return '';
    final minutes = estimated.difference(DateTime.now()).inMinutes;
    if (minutes <= 0) return 'الطلب قريباً';
    return 'التوصيل المتوقع خلال $minutes دقيقة';
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
    if (token == null || token is! String || token.isEmpty) return;
    final orderId = _pendingOrderId;
    if (orderId == null || orderId.isEmpty) return;

    final userId = SessionService.instance.currentUserId;
    final isGuest = SessionService.instance.isGuest;

    String? authToken;
    String? guestToken;

    if (isGuest) {
      final prefs = await SharedPreferences.getInstance();
      guestToken = prefs.getString('guest_token');
    } else {
      authToken = SessionService.instance.idToken ?? SessionService.instance.accessToken;
    }

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
        if (authToken != null && authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
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
