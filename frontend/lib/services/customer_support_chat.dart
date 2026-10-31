import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'session_service.dart';
import '../config/api_config.dart';

class SupportIdentity {
  final String subject, token, name, phone;
  const SupportIdentity(this.subject, this.token, this.name, this.phone);
}

abstract class SupportTransport {
  Stream<dynamic> get stream;
  Future<void> get ready;
  void send(String value);
  Future<void> close();
}

class _SocketTransport implements SupportTransport {
  final IOWebSocketChannel channel;
  _SocketTransport(Uri uri, String token)
    : channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
  @override
  Stream<dynamic> get stream => channel.stream;
  @override
  Future<void> get ready => channel.ready;
  @override
  void send(String value) => channel.sink.add(value);
  @override
  Future<void> close() async {
    await channel.sink.close();
  }
}

/// Customer adapter for the existing authenticated support protocol, scoped to the complaint order.
/// A message is confirmed by a server receipt, never by writing to a socket.
class CustomerSupportChat extends ChangeNotifier {
  static const endpoint = String.fromEnvironment(
    'SUPPORT_CHAT_WS_URL',
    defaultValue:
        ApiConfig.environment == 'production' ||
                ApiConfig.environment != 'staging'
            ? ''
            : 'wss://vzvnqu5jhl.execute-api.us-east-1.amazonaws.com/staging',
  );
  final String orderId, fixedSessionId;
  final Future<SupportIdentity> Function() identity;
  final SupportTransport Function(Uri, String) transport;
  final Future<String?> Function(String) readSession;
  final Future<void> Function(String, String) saveSession;
  final Duration timeout;
  final List<Map<String, dynamic>> messages = [];
  SupportTransport? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _historyTimer;
  Completer<void>? _handshake;
  Completer<bool>? _ack;
  String? _sessionId, _subject, _pendingId, _pendingText, _historyRequest;
  String? _pendingAttachment;
  String? nextCursor;
  String? historyError;
  String status = 'disconnected';
  bool sending = false, historyLoading = false, _disposed = false;
  int _generation = 0;
  String? get sessionId => _sessionId;
  bool get connected => status == 'connected';
  CustomerSupportChat({
    required this.orderId,
    required this.fixedSessionId,
    Future<SupportIdentity> Function()? identity,
    SupportTransport Function(Uri, String)? transport,
    Future<String?> Function(String)? readSession,
    Future<void> Function(String, String)? saveSession,
    this.timeout = const Duration(seconds: 15),
  }) : identity = identity ?? _identity,
       transport = transport ?? ((uri, token) => _SocketTransport(uri, token)),
       readSession =
           readSession ??
           ((key) async =>
               (await SharedPreferences.getInstance()).getString(key)),
       saveSession =
           saveSession ??
           ((key, value) async {
             await (await SharedPreferences.getInstance()).setString(
               key,
               value,
             );
           });
  static Future<SupportIdentity> _identity() async {
    final session = SessionService.instance;
    final token = session.accessToken;
    if (session.isGuest || token == null) throw StateError('AUTH_REQUIRED');
    final claims =
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(token.split('.')[1])),
              ),
            )
            as Map;
    final subject = claims['sub'];
    if (subject is! String || subject.isEmpty)
      throw StateError('AUTH_REQUIRED');
    return SupportIdentity(
      subject,
      token,
      '${session.currentUser?['name'] ?? 'زبون'}',
      '',
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _send(Map<String, dynamic> message) =>
      _socket!.send(jsonEncode(message));
  void _fail([String next = 'error']) {
    status = next;
    _heartbeat?.cancel();
    historyLoading = false;
    _historyTimer?.cancel();
    if (_handshake != null && !_handshake!.isCompleted) _handshake!.complete();
    if (_ack != null && !_ack!.isCompleted) _ack!.complete(false);
    _changed();
  }

  Future<void> connect({bool newConversation = false}) async {
    if (_disposed || status == 'connecting') return;
    final generation = ++_generation;
    status = 'connecting';
    _changed();
    _heartbeat?.cancel();
    try {
      await _subscription?.cancel();
      try {
        await _socket?.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
      historyLoading = false;
      _historyTimer?.cancel();
      _historyRequest = null;
      final actor = await identity().timeout(timeout);
      if (_disposed || generation != _generation) return;
      if (actor.subject.trim().isEmpty || actor.token.isEmpty)
        throw StateError('AUTH_REQUIRED');
      if (_subject != actor.subject || newConversation) {
        messages.clear();
        _pendingId = null;
        _pendingText = null;
        nextCursor = null;
      }
      _subject = actor.subject;
      final key = 'customer-support-v2:${actor.subject}:$orderId';

      if (_disposed || generation != _generation) return;
      _sessionId = fixedSessionId;
      final uri = Uri.parse(endpoint);
      if (uri.scheme != 'wss' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery)
        throw StateError('INVALID_SUPPORT_ENDPOINT');
      _socket = transport(
        uri.replace(
          queryParameters: {'userType': 'customer', 'platform': 'wizzuser_app'},
        ),
        actor.token,
      );
      _handshake = Completer<void>();
      _subscription = _socket!.stream.listen(
        (event) {
          if (!_disposed && generation == _generation) _receive(event);
        },
        onError: (_) {
          if (generation == _generation) _fail();
        },
        onDone: () {
          if (generation == _generation && status != 'closed')
            _fail('disconnected');
        },
      );
      await _socket!.ready.timeout(timeout);
      if (_disposed || generation != _generation) return;
      _send({
        'action': 'chat_customer_connect',
        'customerId': actor.subject,
        'customerName': actor.name,
        'orderId': orderId,
        'sessionId': _sessionId,
      });
      await _handshake!.future.timeout(timeout);
      if (_disposed || generation != _generation) return;
      if (!connected) throw StateError('SUPPORT_NOT_READY');
      await saveSession(key, _sessionId!);
      if (_disposed || generation != _generation) return;
      _heartbeat = Timer.periodic(const Duration(seconds: 40), (_) {
        if (connected) _send({'action': 'heartbeat'});
      });
      loadHistory();
    } catch (_) {
      if (!_disposed && generation == _generation && status != 'closed')
        _fail();
    }
  }

  void _merge(Map<String, dynamic> item) {
    final id = item['messageId'];
    if (id is! String ||
        id.isEmpty ||
        item['senderType'] is! String ||
        item['text'] is! String)
      return;
    final existing = messages.indexWhere((m) => m['messageId'] == id);
    if (existing >= 0) {
      messages[existing] = {...messages[existing], ...item};
    } else {
      messages.add({...item});
    }
    messages.sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
  }

  void _receive(dynamic raw) {
    try {
      final parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is! Map) return;
      final event = Map<String, dynamic>.from(parsed);
      if (event['sessionId'] != null && event['sessionId'] != _sessionId)
        return;
      switch (event['type']) {
        case 'chat_session_created':
          if (event['sessionId'] != _sessionId) return;
          status = 'connected';
          if (!_handshake!.isCompleted) _handshake!.complete();
          break;
        case 'session_messages':
          if (event['requestId'] != _historyRequest) return;
          for (final m in (event['messages'] as List? ?? [])) {
            if (m is Map) _merge(Map<String, dynamic>.from(m));
          }
          nextCursor =
              event['nextCursor'] is String ? event['nextCursor'] : null;
          historyLoading = false;
          _historyTimer?.cancel();
          break;
        case 'history_error':
          historyError = 'تعذر تحميل الرسائل السابقة';
          historyLoading = false;
          break;
        case 'chat_message':
          if (event['message'] is Map)
            _merge(Map<String, dynamic>.from(event['message']));
          break;
        case 'message_ack':
          if (event['clientMessageId'] == _pendingId &&
              event['messageId'] is String) {
            _merge({
              'messageId': event['messageId'],
              'senderType': 'customer',
              'text': _pendingText ?? '',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            });
            if (_ack != null && !_ack!.isCompleted) _ack!.complete(true);
          }
          break;
        case 'session_closed':
          _fail('closed');
          break;
        case 'error':
          _fail(event['code'] == 'SESSION_CLOSED' ? 'closed' : 'error');
          if (status == 'closed') loadHistory();
          break;
      }
      _changed();
    } catch (_) {
      _fail();
    }
  }

  void loadHistory({bool older = false}) {
    if ((!connected && status != 'closed') ||
        historyLoading ||
        older && nextCursor == null)
      return;
    historyLoading = true;
    historyError = null;
    _historyRequest = const Uuid().v4();
    _send({
      'action': 'get_session_messages',
      'sessionId': _sessionId,
      'requestId': _historyRequest,
      'limit': 30,
      if (older) 'cursor': nextCursor,
    });
    _historyTimer?.cancel();
    _historyTimer = Timer(timeout, () {
      historyError = 'تعذر تحميل الرسائل السابقة';
      historyLoading = false;
      _changed();
    });
    _changed();
  }

  Future<bool> send(
    String text, {
    String? attachmentId,
    String? clientMessageId,
  }) async {
    text = text.trim();
    if (!connected || sending || text.isEmpty || text.length > 2000)
      return false;
    if (_pendingText != text || _pendingAttachment != attachmentId) {
      _pendingAttachment = attachmentId;
      _pendingId = clientMessageId ?? const Uuid().v4();
      _pendingText = text;
    }
    sending = true;
    _ack = Completer<bool>();
    _changed();
    var confirmed = false;
    try {
      _send({
        'action': 'chat_message',
        'sessionId': _sessionId,
        'senderType': 'customer',
        'messageText': text,
        'clientMessageId': _pendingId,
        if (attachmentId != null) 'attachmentId': attachmentId,
      });
      confirmed = await _ack!.future.timeout(timeout, onTimeout: () => false);
      if (confirmed) {
        _pendingText = null;
        _pendingId = null;
      }
    } catch (_) {
      confirmed = false;
    } finally {
      sending = false;
      _changed();
    }
    return confirmed;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _heartbeat?.cancel();
    _historyTimer?.cancel();
    if (_handshake != null && !_handshake!.isCompleted) _handshake!.complete();
    if (_ack != null && !_ack!.isCompleted) _ack!.complete(false);
    _subscription?.cancel();
    _socket?.close();
    super.dispose();
  }
}
