import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inbox_notification.dart';
import 'session_service.dart';
import 'wallet_transfer_service.dart';

class NotificationInboxService {
  static final instance = NotificationInboxService();
  static final hasUnread = ValueNotifier<bool>(false);
  static final changed = ValueNotifier<int>(0);
  String? _scope;
  String? cursor;
  List<InboxNotification> items = [];
  String? error;
  final WalletTransferService _api;
  NotificationInboxService({WalletTransferService? api})
    : _api = api ?? WalletTransferService();
  bool get isAuthenticated => _scope != null;
  static const _bindingKey = 'notification_account_binding';
  static String _key(String sub) => 'notification_inbox_$sub';
  static Future<void> bindCurrentAccount() async {
    final prefs = await SharedPreferences.getInstance();
    if (!SessionService.instance.isLoggedIn ||
        SessionService.instance.isGuest) {
      await prefs.remove(_bindingKey);
      hasUnread.value = false;
      instance.items = [];
      instance._scope = null;
      changed.value++;
      return;
    }
    final token = await SessionService.instance.getToken();
    if (token == null) return;
    final claims =
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(token.split('.')[1])),
              ),
            )
            as Map<String, dynamic>;
    final sub = claims['sub']?.toString();
    if (sub == null || sub.isEmpty) return;
    await prefs.setString(
      _bindingKey,
      jsonEncode({
        'sub': sub,
        'legacyId': SessionService.instance.currentUserId,
      }),
    );
    if (instance._scope != sub) {
      instance._scope = sub;
      instance.items = [];
      instance.cursor = null;
      instance.error = null;
      hasUnread.value = false;
      changed.value++;
    }
  }

  static Future<InboxNotification?> recordPush(RemoteMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_bindingKey);
    if (raw == null) return null;
    final binding = jsonDecode(raw) as Map<String, dynamic>,
        data = message.data;
    final subject =
        data['subjectId'] ??
        data['customerId'] ??
        data['userId'] ??
        data['driverId'];
    if (subject != null &&
        subject != binding['sub'] &&
        subject != binding['legacyId']) {
      return null;
    }
    final id = (data['eventId'] ?? message.messageId)?.toString();
    if (id == null || id.isEmpty) return null;
    final orderId = data['orderId']?.toString();
    final item = InboxNotification(
      id: id,
      title:
          message.notification?.title ??
          data['title']?.toString() ??
          'إشعار جديد',
      body: message.notification?.body ?? data['body']?.toString() ?? '',
      createdAt: message.sentTime ?? DateTime.now(),
      type: data['type']?.toString() ?? '',
      orderId: orderId?.isNotEmpty == true ? orderId : null,
      orderNumber: data['orderNumber']?.toString(),
      target: data['action'] == 'open_wallet' ? 'wallet' : '',
    );
    final stored =
        (jsonDecode(prefs.getString(_key(binding['sub'])) ?? '[]') as List)
            .cast<Map<String, dynamic>>();
    if (stored.any((x) => x['id'] == id)) return null;
    stored.insert(0, item.toJson());
    await prefs.setString(
      _key(binding['sub']),
      jsonEncode(stored.take(200).toList()),
    );
    if (instance._scope == binding['sub']) {
      if (!instance.items.any((x) => x.id == id)) {
        instance.items = [item, ...instance.items];
      }
      hasUnread.value = instance.items.any((x) => !x.isRead);
    }
    changed.value++;
    return item;
  }

  Future<void> load({bool more = false}) async {
    await bindCurrentAccount();
    final scope = _scope;
    if (scope == null) {
      items = [];
      error = null;
      cursor = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final cached =
        (jsonDecode(prefs.getString(_key(scope)) ?? '[]') as List)
            .map(
              (x) => InboxNotification.fromJson(Map<String, dynamic>.from(x)),
            )
            .toList();
    final merge = <String, InboxNotification>{
      for (final x in (more ? items : cached)) x.id: x,
    };
    try {
      final r = await _api.call(
        'notifications',
        query: more && cursor != null ? {'cursor': cursor!} : null,
      );
      if (_scope != scope) return;
      for (final x in (r['notifications'] as List? ?? [])) {
        final n = InboxNotification.fromJson(Map<String, dynamic>.from(x));
        merge[n.id] = n;
      }
      cursor = r['nextCursor']?.toString();
      error = null;
    } catch (_) {
      if (_scope != scope) return;
      error = 'تعذر تحديث الإشعارات. اسحب لإعادة المحاولة.';
    }
    items =
        merge.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await prefs.setString(
      _key(scope),
      jsonEncode(items.take(200).map((x) => x.toJson()).toList()),
    );
    hasUnread.value = items.any((x) => !x.isRead);
    changed.value++;
  }

  Future<void> markRead(
    List<InboxNotification> selected, {
    bool all = false,
  }) async {
    final scope = _scope;
    if (scope == null) return;
    final ids = selected.where((x) => !x.isRead).map((x) => x.id).toSet();
    final server =
        selected
            .where((x) => !x.isRead && x.source == 'server')
            .map((x) => x.id)
            .toList();
    if (all) {
      await _api.call('notifications', body: {'all': true});
    }
    for (var start = 0; !all && start < server.length; start += 50) {
      await _api.call(
        'notifications',
        body: {'eventIds': server.skip(start).take(50).toList()},
      );
    }
    if (_scope != scope) return;
    items = items.map((x) => ids.contains(x.id) ? x.read() : x).toList();
    await (await SharedPreferences.getInstance()).setString(
      _key(scope),
      jsonEncode(items.take(200).map((x) => x.toJson()).toList()),
    );
    hasUnread.value = items.any((x) => !x.isRead);
    changed.value++;
  }
}
