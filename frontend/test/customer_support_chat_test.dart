import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/customer_support_chat.dart';

class FakeTransport implements SupportTransport {
  final events = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool handshake = true, receipt = true;
  @override
  Stream<dynamic> get stream => events.stream;
  @override
  Future<void> get ready async {}
  @override
  Future<void> close() async {}
  @override
  void send(String raw) {
    final message = Map<String, dynamic>.from(jsonDecode(raw));
    sent.add(message);
    if (message['action'] == 'chat_customer_connect' && handshake)
      emit({'type': 'chat_session_created', 'sessionId': message['sessionId']});
    if (message['action'] == 'chat_message' && receipt)
      emit({
        'type': 'message_ack',
        'sessionId': message['sessionId'],
        'clientMessageId': message['clientMessageId'],
        'messageId': 'saved-1',
      });
  }

  void emit(Map<String, dynamic> message) => events.add(jsonEncode(message));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeTransport socket;
  late CustomerSupportChat chat;
  setUp(() {
    socket = FakeTransport();
    chat = CustomerSupportChat(
      orderId: 'order-1',
      fixedSessionId: 'owned-session',
      identity:
          () async =>
              const SupportIdentity('signed-sub', 'signed-token', 'سائق', ''),
      transport: (uri, token) {
        expect(uri.scheme, 'wss');
        expect(uri.queryParameters['userType'], 'customer');
        expect(token, 'signed-token');
        return socket;
      },
      readSession: (_) async => 'owned-session',
      saveSession: (key, value) async {},
      timeout: const Duration(milliseconds: 100),
    );
  });
  tearDown(() {
    chat.dispose();
    socket.events.close();
  });
  test(
    'server handshake required, cannot claim connected after socket creation',
    () async {
      socket.handshake = false;
      final connecting = chat.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(chat.connected, false);
      expect(chat.status, 'connecting');
      socket.emit({
        'type': 'chat_session_created',
        'sessionId': 'owned-session',
      });
      await connecting;
      expect(chat.connected, true);
      expect(socket.sent.first['customerId'], 'signed-sub');
    },
  );
  test(
    'receipt confirms exactly one message and restores same owner session',
    () async {
      await chat.connect();
      expect(chat.sessionId, 'owned-session');
      expect(await chat.send('مرحبا'), true);
      expect(chat.messages.single['messageId'], 'saved-1');
      socket.emit({
        'type': 'chat_message',
        'sessionId': 'owned-session',
        'message': {
          'messageId': 'saved-1',
          'senderType': 'customer',
          'text': 'مرحبا',
          'createdAt': '2026-10-24T00:00:00Z',
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(chat.messages.length, 1);
    },
  );
  test(
    'uncertain send retry retains idempotency key and does not invent saved message',
    () async {
      await chat.connect();
      socket.receipt = false;
      expect(await chat.send('رسالة'), false);
      expect(chat.messages, isEmpty);
      final first = socket.sent.last['clientMessageId'];
      socket.receipt = true;
      expect(await chat.send('رسالة'), true);
      expect(socket.sent.last['clientMessageId'], first);
    },
  );
  test('another session cannot confirm a send or insert history', () async {
    await chat.connect();
    socket.receipt = false;
    final sending = chat.send('رسالة');
    socket.emit({
      'type': 'message_ack',
      'sessionId': 'other',
      'clientMessageId': socket.sent.last['clientMessageId'],
      'messageId': 'forged',
    });
    expect(await sending, false);
    expect(chat.messages, isEmpty);
  });
  test(
    'session closure blocks send and does not switch to an unrelated support conversation',
    () async {
      await chat.connect();
      socket.emit({'type': 'session_closed', 'sessionId': 'owned-session'});
      await Future<void>.delayed(Duration.zero);
      expect(chat.status, 'closed');
      expect(await chat.send('x'), false);
      await chat.connect(newConversation: true);
      expect(chat.sessionId, 'owned-session');
      expect(chat.connected, true);
    },
  );
  test('old history response cannot override the requested page', () async {
    await chat.connect();
    socket.emit({
      'type': 'session_messages',
      'sessionId': 'owned-session',
      'requestId': 'unrequested',
      'messages': [
        {'messageId': 'x', 'senderType': 'agent', 'text': 'wrong'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(chat.messages, isEmpty);
    final request = socket.sent.last;
    socket.emit({
      'type': 'session_messages',
      'sessionId': 'owned-session',
      'requestId': request['requestId'],
      'messages': [
        {
          'messageId': 'a',
          'senderType': 'agent',
          'text': 'الدعم',
          'createdAt': '2026-10-24T00:00:00Z',
        },
      ],
      'nextCursor': 'older',
    });
    await Future<void>.delayed(Duration.zero);
    expect(chat.messages.length, 1);
    expect(chat.nextCursor, 'older');
  });
  test('no signed identity means no transport and no mock identity', () async {
    final invalid = CustomerSupportChat(
      orderId: 'order-1',
      fixedSessionId: 'owned-session',
      identity: () async => throw StateError('logged out'),
      transport: (_, __) => throw StateError('must not connect'),
      readSession: (_) async => null,
      saveSession: (_, __) async {},
    );
    await invalid.connect();
    expect(invalid.status, 'error');
    expect(invalid.connected, false);
    invalid.dispose();
  });
  test(
    'history failure offers retry and clears error for a new request',
    () async {
      await chat.connect();
      socket.emit({'type': 'history_error', 'sessionId': 'owned-session'});
      await Future<void>.delayed(Duration.zero);
      expect(chat.historyLoading, false);
      expect(chat.historyError, isNotNull);
      chat.loadHistory();
      expect(chat.historyLoading, true);
      expect(chat.historyError, isNull);
    },
  );
}
