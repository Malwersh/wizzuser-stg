import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'session_service.dart';

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // ignore
  }
}

class PushNotificationsService {
  static bool _initialized = false;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<dynamic>? _sessionSub;
  static FutureOr<void> Function(RemoteMessage message)? _onNotificationTap;

  static String? _lastKnownFcmToken;

  static const String _pendingOrderKey = 'pendingOrderFromPushTap';
  static const String _pendingTabIndexKey = 'pendingTabIndexFromPushTap';

  static Future<void> initialize({FutureOr<void> Function(RemoteMessage message)? onNotificationTap}) async {
    if (kIsWeb) return;

    if (onNotificationTap != null) {
      _onNotificationTap = onNotificationTap;
    }

    if (_initialized) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      print('PushNotificationsService: Firebase.initializeApp failed: $e');
      print(
        'PushNotificationsService: Firebase config is likely missing/invalid. '
        'Add android/app/google-services.json and ios/Runner/GoogleService-Info.plist. '
        'Expected ids: Android=com.wiz.userapp, iOS=com.wiz.wizuserapp.',
      );
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    // Helps ensure FCM is initialized early on iOS.
    try {
      await messaging.setAutoInitEnabled(true);
    } catch (e) {
      print('PushNotificationsService: setAutoInitEnabled failed: $e');
    }

    print(
      'PushNotificationsService: init (env=${ApiConfig.environment}) '
      'loggedIn=${SessionService.instance.isLoggedIn} guest=${SessionService.instance.isGuest} '
      'central=${ApiConfig.centralPushApiBaseUrl}',
    );

    final perm = await messaging.requestPermission(alert: true, badge: true, sound: true);
    print('PushNotificationsService: permission=${perm.authorizationStatus}');

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final apns = await messaging.getAPNSToken();
        print('PushNotificationsService: APNs token ${apns == null ? 'is NULL' : 'is SET'}');
      } catch (e) {
        print('PushNotificationsService: getAPNSToken failed: $e');
      }
    }

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _refreshTokenAndRegister(messaging);

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      _lastKnownFcmToken = newToken;
      await _attemptRegisterForCurrentSession(newToken);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      final handler = _onNotificationTap;
      if (handler != null) await handler(message);
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      final handler = _onNotificationTap;
      if (handler != null) await handler(initialMessage);
    }

    // If the user signs in later, retry token registration.
    _sessionSub?.cancel();
    _sessionSub = SessionService.instance.sessionStateStream.listen((_) async {
      final tokenToRegister = _lastKnownFcmToken;
      if (tokenToRegister != null && tokenToRegister.isNotEmpty) {
        await _attemptRegisterForCurrentSession(tokenToRegister);
      }
    });

    _initialized = true;
  }

  static Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _sessionSub?.cancel();
    _sessionSub = null;
    _initialized = false;
  }

  static String _platform() {
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.iOS) return 'ios';
    return 'android';
  }

  static Future<String?> _deviceId() async {
    try {
      final info = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await info.androidInfo;
        return android.id;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await info.iosInfo;
        return ios.identifierForVendor;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Future<String?> _getJwt() async {
    // Avoid race conditions where login state flips before tokens are fully persisted.
    // SessionService implements a lightweight readiness gate.
    try {
      await SessionService.instance.waitForSessionReady();
    } catch (_) {
      // ignore
    }

    // Prefer ID token if present (Cognito verifier checks ID token first when clientId is configured).
    final idToken = SessionService.instance.idToken;
    if (idToken != null && idToken.isNotEmpty) return idToken;

    final accessToken = SessionService.instance.accessToken;
    if (accessToken != null && accessToken.isNotEmpty) return accessToken;

    return null;
  }

  static Future<void> _registerToken(String token) async {
    print('PushNotificationsService: registering token for logged-in user…');
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) {
      print('Push token register skipped: no auth session (jwt missing)');
      return;
    }

    final uri = Uri.parse('${ApiConfig.centralPushApiBaseUrl}/push/tokens/register');
    final deviceId = await _deviceId();

    final payload = <String, dynamic>{
      'token': token,
      'platform': _platform(),
      'app': 'user',
      'env': ApiConfig.environment,
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
    };

    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwt',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        print('Push token register failed: ${resp.statusCode} ${resp.body}');
      } else {
        print('Push token registered: ${resp.statusCode}');
      }
    } on TimeoutException {
      print('Push token register timed out');
    } catch (e) {
      print('Push token register error: $e');
    }
  }

  static Future<void> stashOrderFromTap(RemoteMessage message) async {
    try {
      final data = message.data;
      final type = (data['type'] ?? '').toString();
      if (type != 'order_update') return;

      final orderId = (data['orderId'] ?? '').toString();
      if (orderId.isEmpty) return;

      final payload = <String, dynamic>{
        'orderId': orderId,
        'orderNumber': (data['orderNumber'] ?? '').toString(),
        'status': (data['status'] ?? '').toString(),
        'tappedAt': DateTime.now().toIso8601String(),
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingOrderKey, jsonEncode(payload));
    } catch (_) {
      // ignore
    }
  }

  static Future<void> stashPendingTabFromTap(RemoteMessage message) async {
    try {
      final data = message.data;
      final type = (data['type'] ?? '').toString();

      // Order updates should open the Orders tab.
      final targetTab = type == 'order_update' ? 4 : 0;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pendingTabIndexKey, targetTab);
    } catch (_) {
      // ignore
    }
  }

  static Future<int?> consumePendingTabFromTap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_pendingTabIndexKey)) return null;
      final tab = prefs.getInt(_pendingTabIndexKey);
      await prefs.remove(_pendingTabIndexKey);
      if (tab == null) return null;
      return tab.clamp(0, 5);
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Future<Map<String, dynamic>?> consumeStashedOrderFromTap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingOrderKey);
      if (raw == null || raw.isEmpty) return null;
      await prefs.remove(_pendingOrderKey);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Future<void> _refreshTokenAndRegister(FirebaseMessaging messaging) async {
    // On iOS, getToken() may return null early until APNs registration completes.
    const delays = <Duration>[Duration.zero, Duration(seconds: 2), Duration(seconds: 6)];
    for (final d in delays) {
      if (d != Duration.zero) {
        await Future.delayed(d);
      }
      String? token;
      try {
        token = await messaging.getToken();
      } catch (e) {
        print('PushNotificationsService: getToken() failed: $e');
      }
      if (token != null && token.isNotEmpty) {
        _lastKnownFcmToken = token;
        print('PushNotificationsService: got FCM token (${token.substring(0, 12)}…)');
        await _attemptRegisterForCurrentSession(token);
        return;
      }
      print('PushNotificationsService: FCM token not ready yet');
    }
  }

  static Future<void> _attemptRegisterForCurrentSession(String fcmToken) async {
    if (SessionService.instance.isLoggedIn) {
      // Small delay helps on iOS where tokens/session can settle right after login.
      await Future.delayed(const Duration(milliseconds: 250));
      await _registerToken(fcmToken);
      return;
    }

    if (!SessionService.instance.isGuest) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final guestToken = prefs.getString('guest_token');
      if (guestToken == null || guestToken.isEmpty) {
        print('Push guest register skipped: no guest_token yet');
        return;
      }
      await _registerGuestToken(fcmToken, guestToken);
    } catch (e) {
      print('Push guest register error: $e');
    }
  }

  static Future<void> onGuestTokenAvailable(String guestToken) async {
    final token = _lastKnownFcmToken;
    if (token == null || token.isEmpty) return;
    if (guestToken.isEmpty) return;
    await _registerGuestToken(token, guestToken);
  }

  static Future<void> _registerGuestToken(String fcmToken, String guestToken) async {
    final deviceId = await _deviceId();
    final uri = Uri.parse(ApiConfig.buildUrl('/push/tokens/register-guest'));

    final payload = <String, dynamic>{
      'token': fcmToken,
      'platform': _platform(),
      'guestToken': guestToken,
      'env': ApiConfig.environment,
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
    };

    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        print('Guest push token register failed: ${resp.statusCode} ${resp.body}');
      } else {
        print('Guest push token registered: ${resp.statusCode}');
      }
    } on TimeoutException {
      print('Guest push token register timed out');
    } catch (e) {
      print('Guest push token register error: $e');
    }
  }
}
