import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
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
