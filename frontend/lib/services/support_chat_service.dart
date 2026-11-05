import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'support_conversation_store.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SupportReply {
  SupportReply({
    required this.clientId,
    required this.text,
    required this.sender,
    this.serverId,
    this.status = 'pending',
    this.attachmentId,
    this.isUploading = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String clientId;
  final String text;
  final String sender;
  String? serverId;
  String status;
  String? attachmentId;
  bool isUploading;
  DateTime createdAt;
}

/// One authenticated account and conversation per instance. No automatic resend.
class SupportChatService extends ChangeNotifier {
  SupportChatService({
    required this.tokenProvider,
    this.customerName = 'زبون',
    this.store,
    this.orderId,
    this.endpoint = defaultEndpoint,
    this.attachmentsEndpoint = const String.fromEnvironment(
      'SUPPORT_ATTACHMENTS_API_URL',
      defaultValue:
          'https://5ytyphpnkc.execute-api.us-east-1.amazonaws.com/staging/support/attachments',
    ),
    http.Client? attachmentClient,
    WebSocketChannel Function(Uri)? channelFactory,
  }) : _factory = channelFactory ?? WebSocketChannel.connect,
       _imageClient = attachmentClient ?? http.Client();
  static const defaultEndpoint = String.fromEnvironment(
    'SUPPORT_WEBSOCKET_URL',
    defaultValue:
        'wss://vzvnqu5jhl.execute-api.us-east-1.amazonaws.com/staging',
  );
  final Future<String?> Function() tokenProvider;
  final String customerName;
  final SupportConversationStore? store;
  final String? orderId;
  bool _restored = false;
  final String endpoint;
  final String attachmentsEndpoint;
  final http.Client _imageClient;
  bool get imagesAvailable => attachmentsEndpoint.isNotEmpty;
  final WebSocketChannel Function(Uri) _factory;
  String _sessionId = 'customer_${const Uuid().v4()}';
  String get sessionId => _sessionId;
  final List<SupportReply> _messages = [];
  List<SupportReply> get messages => List.unmodifiable(_messages);
  bool _draftEdited = false;
  String _draft = '';
  String get draft => _draft;
  set draft(String value) {
    if (_disposed) return;
    _draftEdited = true;
    _draft = value.length > 4000 ? value.substring(0, 4000) : value;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), _save);
  }

  Timer? _draftTimer;

  void _save() {
    if (store == null || !_restored) return;
    final checkpoint = jsonEncode({
      'version': 1,
      'sessionId': sessionId,
      'draft': _draft,
      'closed': closed,
    });
    unawaited(
      store!.write(checkpoint).catchError((Object _) {
        if (!_disposed) {
          error = 'تعذر حفظ المحادثة على الجهاز. حاول مجددًا قبل المغادرة.';
          notifyListeners();
        }
      }),
    );
  }

  Future<void> _restore() async {
    if (_restored) return;
    final saved = await store?.read();
    if (_disposed) return;
    if (saved != null) {
      final checkpoint = jsonDecode(saved) as Map<String, dynamic>;
      final id = checkpoint['sessionId'];
      final text = checkpoint['draft'];
      if (checkpoint['version'] != 1 ||
          id is! String ||
          !RegExp(r'^customer_[0-9a-f-]{36}$').hasMatch(id) ||
          text is! String ||
          text.length > 4000 ||
          checkpoint['closed'] is! bool) {
        throw StateError('Invalid conversation checkpoint');
      }
      _sessionId = id;
      if (!_draftEdited) _draft = text;
      closed = checkpoint['closed'] as bool;
    }
    _restored = true;
    _save();
  }

  Future<void> startNewConversation() async {
    if (!closed || _disposed || !_restored) return;
    _sessionId = 'customer_${const Uuid().v4()}';
    _messages.clear();
    nextCursor = null;
    historyError = null;
    _draft = '';
    closed = false;
    _save();
    await connect();
  }

  String? error;
  bool ready = false;
  bool connecting = false;
  bool closed = false;
  bool closing = false;
  bool _disposed = false;
  bool _reconnect = true;
  int _generation = 0;
  int _attempt = 0;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _handshake;
  Timer? _closeTimer;
  final Map<String, Timer> _receipts = {};
  String? nextCursor;
  bool loadingHistory = false;
  String? historyError;
  String? _historyRequest;
  String? _requestedCursor;
  Timer? _historyTimer;

  bool loadOlder() => nextCursor != null && _requestHistory(nextCursor);
  bool retryHistory() => _requestHistory(_requestedCursor);

  bool _requestHistory(String? cursor) {
    if (!ready || closed || loadingHistory || _disposed) return false;
    final requestId = const Uuid().v4();
    _historyRequest = requestId;
    _requestedCursor = cursor;
    loadingHistory = true;
    historyError = null;
    try {
      _channel!.sink.add(
        jsonEncode({
          'action': 'get_session_messages',
          'sessionId': sessionId,
          'requestId': requestId,
          if (cursor != null) 'cursor': cursor,
        }),
      );
      _historyTimer = Timer(const Duration(seconds: 15), () {
        loadingHistory = false;
        _historyRequest = null;
        historyError = 'تعذر تحميل السجل. يمكنك المحاولة مجددًا.';
        if (!_disposed) notifyListeners();
      });
      notifyListeners();
      return true;
    } catch (_) {
      _lost();
      return false;
    }
  }

  Future<void> connect() async {
    if (_disposed || closed || ready || connecting) return;
    _retry?.cancel();
    _retry = null;
    _reconnect = true;
    final generation = ++_generation;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      await _restore();
      if (_disposed || generation != _generation) return;
      if (closed) {
        connecting = false;
        notifyListeners();
        return;
      }
      final base = Uri.parse(endpoint);
      if (base.scheme != 'wss' ||
          base.host.isEmpty ||
          base.userInfo.isNotEmpty ||
          base.hasQuery ||
          base.hasFragment) {
        throw StateError('Invalid support endpoint');
      }
      final token = await tokenProvider().timeout(const Duration(seconds: 10));
      if (_disposed || generation != _generation) return;
      if (token == null || token.isEmpty) {
        _reconnect = false;
        throw StateError('Sign in required');
      }
      final channel = _factory(
        base.replace(queryParameters: {'token': token, 'userType': 'customer'}),
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (data) {
          if (generation == _generation && !_disposed) _receive(data);
        },
        onError: (Object _) {
          if (generation == _generation) _lost();
        },
        onDone: () {
          if (generation == _generation) _lost();
        },
      );
      await channel.ready.timeout(const Duration(seconds: 10));
      if (_disposed || generation != _generation) return;
      channel.sink.add(
        jsonEncode({
          'action': 'chat_customer_connect',
          'sessionId': sessionId,
          'customerName': customerName,
          if (orderId != null) 'orderId': orderId,
        }),
      );
      _handshake = Timer(const Duration(seconds: 15), _lost);
    } catch (_) {
      if (!_disposed && generation == _generation) {
        if (!_restored) {
          _reconnect = false;
          error = 'تعذر استعادة المحادثة المحفوظة. حاول مجددًا.';
        }
        _lost();
      }
    }
  }

  bool send(String text) {
    text = text.trim();
    if (!ready || closing || closed || text.isEmpty || text.length > 4000) {
      return false;
    }
    final id = const Uuid().v4();
    final reply = SupportReply(clientId: id, text: text, sender: 'customer');
    _messages.add(reply);
    try {
      _channel!.sink.add(
        jsonEncode({
          'action': 'chat_message',
          'sessionId': sessionId,
          'messageText': text,
          'clientMessageId': id,
        }),
      );
    } catch (_) {
      _messages.remove(reply);
      _lost();
      return false;
    }
    draft = '';
    _receipts[id] = Timer(const Duration(seconds: 15), () {
      _receipts.remove(id);
      if (reply.status == 'pending') reply.status = 'unknown';
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
    return true;
  }

  void _receive(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'];
      if (type == 'error' && data['code'] == 'SESSION_CLOSED') {
        closed = true;
        _reconnect = false;
        _stop();
        _save();
        notifyListeners();
        return;
      }
      if (type == 'error' || type == 'auth_error') {
        error = 'تعذر الوصول إلى الدعم. تحقق من تسجيل الدخول وحاول مجددًا.';
        // Rejected requests are never retried automatically.
        _reconnect = false;
        _lost();
        return;
      }
      if (data['sessionId'] != sessionId) return;
      if (type == 'chat_session_created') {
        _handshake?.cancel();
        connecting = false;
        ready = true;
        _attempt = 0;
        error = null;
        _requestHistory(null);
      } else if (type == 'message_ack') {
        final id = data['clientMessageId'];
        for (final reply in _messages) {
          if (reply.clientId == id && reply.sender == 'customer') {
            _receipts.remove(id)?.cancel();
            reply.status = 'accepted';
            reply.serverId = data['messageId'] as String?;
          }
        }
      } else if (type == 'chat_message') {
        _merge((data['message'] is Map ? data['message'] : data) as Map);
      } else if (type == 'session_messages' || type == 'history_error') {
        if (!loadingHistory || data['requestId'] != _historyRequest) return;
        if (type == 'history_error') {
          historyError = 'تعذر تحميل السجل. يمكنك المحاولة مجددًا.';
        } else {
          if (data['messages'] is! List ||
              (data['nextCursor'] != null && data['nextCursor'] is! String)) {
            return;
          }
          final previous = _messages.length;
          for (final message in (data['messages'] as List).reversed) {
            if (message is Map) _merge(message);
          }
          if (_requestedCursor != null && _messages.length > previous) {
            final older = _messages.sublist(previous);
            _messages.removeRange(previous, _messages.length);
            _messages.insertAll(0, older);
          }
          if (_requestedCursor == null &&
              (data['messages'] as List).any(
                (m) =>
                    m is Map &&
                    m['createdAt'] is String &&
                    DateTime.tryParse(m['createdAt']) != null,
              )) {
            _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          }
          nextCursor = data['nextCursor'] as String?;
          historyError = null;
        }
        _historyTimer?.cancel();
        _historyRequest = null;
        loadingHistory = false;
      } else if (type == 'session_closed') {
        closed = true;
        closing = false;
        _reconnect = false;
        _stop();
        _save();
      }
      notifyListeners();
    } catch (_) {
      // Malformed frames cannot change delivery state or clear the draft.
    }
  }

  void _merge(Map message) {
    final id =
        message['clientMessageId'] ??
        (message['metadata'] is Map
            ? message['metadata']['clientMessageId']
            : null);
    final serverId = message['messageId'] ?? message['id'];
    final sender = message['senderType'];
    if (sender != 'agent' && sender != 'customer') return;
    for (final reply in _messages) {
      if ((id != null && reply.clientId == id && reply.sender == sender) ||
          (serverId != null && reply.serverId == serverId)) {
        _receipts.remove(reply.clientId)?.cancel();
        reply.status = 'accepted';
        reply.isUploading = false;
        final savedAt = DateTime.tryParse(
          message['createdAt'] is String ? message['createdAt'] : '',
        );
        if (savedAt != null) reply.createdAt = savedAt;
        if (message['attachment'] is Map) {
          reply.attachmentId = message['attachment']['attachmentId'] as String?;
        }
        reply.serverId = serverId as String?;
        return;
      }
    }
    final text = message['text'] ?? message['messageText'];
    if (text is! String || (serverId == null && id == null)) return;
    _messages.add(
      SupportReply(
        clientId: (id ?? serverId) as String,
        serverId: serverId as String?,
        text: text,
        sender: sender as String,
        status: 'accepted',
        createdAt: DateTime.tryParse(
          message['createdAt'] is String ? message['createdAt'] : '',
        ),
        attachmentId:
            message['attachment'] is Map
                ? message['attachment']['attachmentId'] as String?
                : null,
      ),
    );
  }

  static const maxImageBytes = 2 * 1024 * 1024;
  Uri _imageEndpoint() {
    final uri = Uri.parse(attachmentsEndpoint);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('Attachments unavailable');
    }
    return uri;
  }

  String _imageType(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw StateError('Invalid image size');
    }
    if (bytes.length >= 8 &&
        listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
      return 'image/png';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[bytes.length - 2] == 255 &&
        bytes.last == 217) {
      return 'image/jpeg';
    }
    throw StateError('Unsupported image');
  }

  Future<Map<String, String>> _imageHeaders() async {
    final token = await tokenProvider().timeout(const Duration(seconds: 10));
    if (token == null || token.isEmpty) throw StateError('Sign in required');
    return {
      'Authorization': 'Bearer $token',
      'X-Support-User-Type': 'customer',
      'Content-Type': 'application/json',
    };
  }

  Future<bool> sendImage(Uint8List bytes, String caption) async {
    if (!ready || closed || closing || _disposed) return false;
    final generation = _generation, conversation = sessionId;
    SupportReply? reply;
    try {
      final uri = _imageEndpoint(), type = _imageType(bytes);
      if (caption.length > 4000) throw StateError('Caption too long');
      final id = const Uuid().v4();
      reply = SupportReply(
        clientId: id,
        text: caption.trim().isEmpty ? '📷 صورة' : caption.trim(),
        sender: 'customer',
        isUploading: true,
      );
      _messages.add(reply);
      notifyListeners();
      final headers = await _imageHeaders();
      if (_disposed || generation != _generation || closed || closing) {
        return false;
      }
      final response = await _imageClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'sessionId': conversation,
              'uploadId': id,
              'contentType': type,
              'dataBase64': base64Encode(bytes),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (_disposed ||
          generation != _generation ||
          conversation != sessionId ||
          closed ||
          closing) {
        return false;
      }
      if (response.statusCode != 200 || response.body.length > 4096) {
        throw StateError('Upload rejected');
      }
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (result['attachmentId'] != id) {
        throw StateError('Upload identity mismatch');
      }
      try {
        _channel!.sink.add(
          jsonEncode({
            'action': 'chat_message',
            'sessionId': conversation,
            'clientMessageId': id,
            'attachmentId': id,
            'messageText': reply.text,
          }),
        );
      } catch (_) {
        reply.status = 'failed';
        _lost();
        return false;
      }
      reply.attachmentId = id;
      reply.isUploading = false;
      _receipts[id] = Timer(const Duration(seconds: 15), () {
        _receipts.remove(id);
        if (reply!.status == 'pending') reply.status = 'unknown';
        if (!_disposed) notifyListeners();
      });
      if (draft == caption) draft = '';
      error = null;
      notifyListeners();
      return true;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        if (reply != null) reply.status = 'failed';
        error =
            'تعذر إرسال الصورة. استخدم JPEG أو PNG بحجم لا يتجاوز ٢ ميغابايت.';
        notifyListeners();
      }
      return false;
    } finally {
      if (reply != null && reply.isUploading) {
        reply.isUploading = false;
        reply.status = 'failed';
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<Uint8List> loadImage(String attachmentId) async {
    if (_disposed || !ready || closed) throw StateError('No active session');
    final generation = _generation, conversation = sessionId;
    final uri = _imageEndpoint().replace(
      queryParameters: {
        'sessionId': conversation,
        'attachmentId': attachmentId,
      },
    );
    final headers = await _imageHeaders();
    if (_disposed || generation != _generation) {
      throw StateError('Session changed');
    }
    final response = await _imageClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (_disposed ||
        generation != _generation ||
        conversation != sessionId ||
        response.statusCode != 200 ||
        response.body.length > 3 * 1024 * 1024) {
      throw StateError('Image unavailable');
    }
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (result['attachmentId'] != attachmentId ||
        result['dataBase64'] is! String) {
      throw StateError('Image mismatch');
    }
    final bytes = base64Decode(result['dataBase64'] as String);
    if (_imageType(bytes) != result['contentType']) {
      throw StateError('Image type mismatch');
    }
    return bytes;
  }

  bool endConversation() {
    if (!ready || closed || closing) return false;
    try {
      _channel!.sink.add(
        jsonEncode({'action': 'chat_session_close', 'sessionId': sessionId}),
      );
      closing = true;
      _closeTimer = Timer(const Duration(seconds: 15), () {
        closing = false;
        error = 'لم يتأكد إغلاق المحادثة. يمكنك المحاولة مجددًا.';
        if (!_disposed) notifyListeners();
      });
      notifyListeners();
      return true;
    } catch (_) {
      _lost();
      return false;
    }
  }

  void _stop() {
    ++_generation;
    ready = false;
    connecting = false;
    closing = false;
    _handshake?.cancel();
    _historyTimer?.cancel();
    loadingHistory = false;
    _historyRequest = null;
    _closeTimer?.cancel();
    _retry?.cancel();
    _retry = null;
    for (final timer in _receipts.values) {
      timer.cancel();
    }
    _receipts.clear();
    for (final reply in _messages) {
      if (reply.isUploading) {
        reply.isUploading = false;
        reply.status = 'failed';
      }
      if (reply.status == 'pending') reply.status = 'unknown';
    }
    final subscription = _subscription;
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    if (channel != null) {
      try {
        unawaited(
          channel.sink.close().then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          ),
        );
      } catch (_) {}
    }
  }

  void _lost() {
    if (_disposed) return;
    _stop();
    error ??= 'انقطع الاتصال. احتفظنا بنص الرسالة.';
    if (_reconnect && !closed) {
      final seconds = 1 << (_attempt < 4 ? _attempt++ : 4);
      _retry = Timer(Duration(seconds: seconds), connect);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _save();
    _disposed = true;
    _reconnect = false;
    _stop();
    _messages.clear();
    _draft = '';
    _imageClient.close();
    super.dispose();
  }
}
