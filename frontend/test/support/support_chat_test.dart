import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:foodapp_user/widgets/support_attachment_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:foodapp_user/services/support_chat_service.dart';
import 'package:foodapp_user/services/support_conversation_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MemoryStore implements SupportConversationStore {
  String? value;
  bool failRead = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('locked');
    return value;
  }

  @override
  Future<void> write(String next) async {
    value = next;
  }
}

class FakeSink implements WebSocketSink {
  FakeSink(this.channel);
  final FakeChannel channel;
  bool fail = false;
  @override
  void add(dynamic data) {
    if (fail) throw StateError('offline');
    channel.sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!channel.input.isClosed) await channel.input.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeChannel implements WebSocketChannel {
  final input = StreamController<dynamic>(sync: true);
  final sent = <Map<String, dynamic>>[];
  late final fakeSink = FakeSink(this);
  @override
  Stream<dynamic> get stream => input.stream;
  @override
  WebSocketSink get sink => fakeSink;
  @override
  Future<void> get ready => Future.value();
  void receive(Map<String, dynamic> frame) => input.add(jsonEncode(frame));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Fixture {
  Fixture({this.imageClient});
  final http.Client? imageClient;
  String get historyRequest =>
      channels.last.sent.lastWhere(
            (m) => m['action'] == 'get_session_messages',
          )['requestId']
          as String;
  final channels = <FakeChannel>[];
  final uris = <Uri>[];
  late final service = SupportChatService(
    tokenProvider: () async => 'fresh-token',
    attachmentsEndpoint: 'https://support.invalid/images',
    attachmentClient: imageClient,
    channelFactory: (uri) {
      uris.add(uri);
      final channel = FakeChannel();
      channels.add(channel);
      return channel;
    },
  );
  void confirm() => channels.last.receive({
    'type': 'chat_session_created',
    'sessionId': service.sessionId,
  });
}

void main() {
  testWidgets(
    'socket open waits for server handshake and uses customer identity',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      expect(f.uris.single.queryParameters['userType'], 'customer');
      expect(f.uris.single.queryParameters['token'], 'fresh-token');
      expect(f.channels.single.sent.single['action'], 'chat_customer_connect');
      expect(f.service.ready, false);
      f.service.draft = 'مسودة';
      expect(f.service.send('مسودة'), false);
      expect(f.service.draft, 'مسودة');
      f.confirm();
      expect(f.service.ready, true);
      expect(f.channels.single.sent.last['action'], 'get_session_messages');
      f.service.dispose();
    },
  );
  testWidgets('echo then late acknowledgement reconcile one saved reply', (
    tester,
  ) async {
    final f = Fixture();
    await f.service.connect();
    f.confirm();
    expect(f.service.send('مساعدة'), true);
    final id = f.channels.single.sent.last['clientMessageId'];
    f.channels.single.receive({
      'type': 'chat_message',
      'sessionId': f.service.sessionId,
      'message': {
        'messageId': 'server-1',
        'clientMessageId': id,
        'senderType': 'customer',
        'text': 'مساعدة',
      },
    });
    f.channels.single.receive({
      'type': 'message_ack',
      'sessionId': f.service.sessionId,
      'clientMessageId': id,
      'messageId': 'server-1',
    });
    await tester.pump(const Duration(seconds: 16));
    expect(f.service.messages.length, 1);
    expect(f.service.messages.single.status, 'accepted');
    f.service.dispose();
  });
  testWidgets('receipt timeout never resends and accepts late confirmation', (
    tester,
  ) async {
    final f = Fixture();
    await f.service.connect();
    f.confirm();
    f.service.send('طلب');
    final message = f.channels.single.sent.last;
    final count = f.channels.single.sent.length;
    await tester.pump(const Duration(seconds: 16));
    expect(f.service.messages.single.status, 'unknown');
    expect(f.channels.single.sent.length, count);
    f.channels.single.receive({
      'type': 'message_ack',
      'sessionId': f.service.sessionId,
      'clientMessageId': message['clientMessageId'],
      'messageId': 'saved',
    });
    expect(f.service.messages.single.status, 'accepted');
    f.service.dispose();
  });
  testWidgets(
    'socket write failure retains draft without a false successful message',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      f.service.draft = 'احتفظ';
      f.channels.single.fakeSink.fail = true;
      expect(f.service.send('احتفظ'), false);
      expect(f.service.draft, 'احتفظ');
      expect(f.service.messages, isEmpty);
      f.service.dispose();
    },
  );
  testWidgets(
    'close receipt does not end conversation until server confirms closure',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      expect(f.service.endConversation(), true);
      f.channels.single.receive({
        'type': 'chat_session_close_ack',
        'sessionId': f.service.sessionId,
      });
      expect(f.service.closed, false);
      expect(f.service.closing, true);
      f.channels.single.receive({
        'type': 'session_closed',
        'sessionId': f.service.sessionId,
      });
      expect(f.service.closed, true);
      expect(f.service.ready, false);
      f.service.dispose();
    },
  );
  testWidgets('missing token cannot open socket or retry automatically', (
    tester,
  ) async {
    var attempts = 0;
    final service = SupportChatService(
      tokenProvider: () async => null,
      channelFactory: (_) {
        attempts++;
        return FakeChannel();
      },
    );
    await service.connect();
    await tester.pump(const Duration(seconds: 30));
    expect(attempts, 0);
    expect(service.ready, false);
    service.dispose();
  });
  testWidgets('late token after disposal cannot open socket', (tester) async {
    final token = Completer<String?>();
    var attempts = 0;
    final service = SupportChatService(
      tokenProvider: () => token.future,
      channelFactory: (_) {
        attempts++;
        return FakeChannel();
      },
    );
    final pending = service.connect();
    service.dispose();
    token.complete('late');
    await pending;
    expect(attempts, 0);
  });
  testWidgets(
    'foreign-session frames cannot confirm or close this conversation',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      f.service.send('طلب');
      f.channels.single.receive({
        'type': 'session_closed',
        'sessionId': 'other',
      });
      f.channels.single.receive({
        'type': 'message_ack',
        'sessionId': 'other',
        'clientMessageId': f.service.messages.single.clientId,
      });
      expect(f.service.closed, false);
      expect(f.service.messages.single.status, 'pending');
      f.service.dispose();
    },
  );
  testWidgets('permission rejection stops automatic reconnection', (
    tester,
  ) async {
    final f = Fixture();
    await f.service.connect();
    f.confirm();
    f.channels.single.receive({'type': 'error', 'code': 'FORBIDDEN'});
    await tester.pump(const Duration(seconds: 30));
    expect(f.channels.length, 1);
    expect(f.service.ready, false);
    f.service.dispose();
  });
  testWidgets(
    'reconnect refreshes token and rejoins the same conversation without resending',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      f.service.send('رسالة');
      final session = f.service.sessionId;
      unawaited(f.channels.single.input.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(f.channels.length, 2);
      expect(f.channels.last.sent.single['sessionId'], session);
      expect(f.channels.last.sent.single['action'], 'chat_customer_connect');
      expect(f.service.messages.single.status, 'unknown');
      f.confirm();
      expect(
        f.channels.last.sent.where((m) => m['action'] == 'chat_message'),
        isEmpty,
      );
      f.service.dispose();
    },
  );
  testWidgets(
    'history is chronological and reconciles a lost receipt by client ID',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      f.service.send('سؤال');
      final id = f.service.messages.single.clientId;
      f.channels.single.receive({
        'type': 'session_messages',
        'requestId': f.historyRequest,
        'sessionId': f.service.sessionId,
        'messages': [
          {'messageId': 'reply', 'senderType': 'agent', 'text': 'جواب'},
          {
            'messageId': 'question',
            'senderType': 'customer',
            'text': 'سؤال',
            'metadata': {'clientMessageId': id},
          },
        ],
      });
      expect(f.service.messages.length, 2);
      expect(f.service.messages.first.status, 'accepted');
      expect(f.service.messages.last.text, 'جواب');
      f.service.dispose();
    },
  );
  testWidgets(
    'screen exit flushes latest draft and reopening rejoins saved session',
    (tester) async {
      final store = MemoryStore();
      final first = SupportChatService(
        tokenProvider: () async => 'token',
        store: store,
        channelFactory: (_) => FakeChannel(),
      );
      await first.connect();
      final session = first.sessionId;
      first.draft = 'مسودة محفوظة';
      first.dispose();
      final channel = FakeChannel();
      final restored = SupportChatService(
        tokenProvider: () async => 'token',
        store: store,
        channelFactory: (_) => channel,
      );
      await restored.connect();
      expect(restored.sessionId, session);
      expect(restored.draft, 'مسودة محفوظة');
      expect(channel.sent.single['sessionId'], session);
      expect(
        restored.messages,
        isEmpty,
      ); // Server is the source of message history.
      restored.dispose();
    },
  );
  testWidgets(
    'confirmed closure survives restart and explicit new conversation gets a new ID',
    (tester) async {
      final store = MemoryStore();
      final channel = FakeChannel();
      final first = SupportChatService(
        tokenProvider: () async => 'token',
        store: store,
        channelFactory: (_) => channel,
      );
      await first.connect();
      final session = first.sessionId;
      channel.receive({'type': 'session_closed', 'sessionId': session});
      first.dispose();
      var connections = 0;
      final next = SupportChatService(
        tokenProvider: () async => 'token',
        store: store,
        channelFactory: (_) {
          connections++;
          return FakeChannel();
        },
      );
      await next.connect();
      expect(next.closed, true);
      expect(connections, 0);
      await next.startNewConversation();
      expect(next.sessionId, isNot(session));
      expect(connections, 1);
      next.dispose();
    },
  );
  testWidgets(
    'locked storage cannot silently replace an existing conversation',
    (tester) async {
      final store = MemoryStore()..failRead = true;
      var connections = 0;
      final service = SupportChatService(
        tokenProvider: () async => 'token',
        store: store,
        channelFactory: (_) {
          connections++;
          return FakeChannel();
        },
      );
      await service.connect();
      await tester.pump(const Duration(seconds: 30));
      expect(connections, 0);
      expect(store.value, isNull);
      service.dispose();
    },
  );
  testWidgets(
    'closed-session rejection from server preserves checkpoint until explicit restart',
    (tester) async {
      final channel = FakeChannel();
      final store = MemoryStore();
      final service = SupportChatService(
        tokenProvider: () async => 'token',
        store: store,
        channelFactory: (_) => channel,
      );
      await service.connect();
      channel.receive({'type': 'error', 'code': 'SESSION_CLOSED'});
      expect(service.closed, true);
      expect(jsonDecode(store.value!)['closed'], true);
      service.dispose();
    },
  );
  test('secure checkpoints isolate accounts, orders and endpoints', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = SecureSupportConversationStore(
      ownerId: 'owner-1',
      endpoint: 'wss://one.invalid',
    );
    await first.write('private draft');
    expect(
      await SecureSupportConversationStore(
        ownerId: 'owner-1',
        endpoint: 'wss://one.invalid',
      ).read(),
      'private draft',
    );
    expect(
      await SecureSupportConversationStore(
        ownerId: 'owner-2',
        endpoint: 'wss://one.invalid',
      ).read(),
      isNull,
    );
    expect(
      await SecureSupportConversationStore(
        ownerId: 'owner-1',
        endpoint: 'wss://one.invalid',
        orderId: 'order-1',
      ).read(),
      isNull,
    );
    expect(
      await SecureSupportConversationStore(
        ownerId: 'owner-1',
        endpoint: 'wss://two.invalid',
      ).read(),
      isNull,
    );
  });
  testWidgets(
    'order context is included only in the order conversation handshake',
    (tester) async {
      final channel = FakeChannel();
      final service = SupportChatService(
        tokenProvider: () async => 'token',
        orderId: 'order-42',
        channelFactory: (_) => channel,
      );
      await service.connect();
      expect(channel.sent.single['orderId'], 'order-42');
      service.dispose();
    },
  );

  testWidgets(
    'older pages prepend chronologically and deduplicate overlapping live messages',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      f.channels.single.receive({
        'type': 'session_messages',
        'requestId': f.historyRequest,
        'sessionId': f.service.sessionId,
        'messages': [
          {'messageId': 'm3', 'senderType': 'agent', 'text': 'third'},
          {'messageId': 'm2', 'senderType': 'agent', 'text': 'second'},
        ],
        'nextCursor': 'cursor-2',
      });
      expect(f.service.loadOlder(), true);
      expect(f.service.loadOlder(), false);
      final request = f.channels.single.sent.last;
      expect(request['cursor'], 'cursor-2');
      f.channels.single.receive({
        'type': 'chat_message',
        'sessionId': f.service.sessionId,
        'message': {'messageId': 'm4', 'senderType': 'agent', 'text': 'fourth'},
      });
      f.channels.single.receive({
        'type': 'session_messages',
        'requestId': f.historyRequest,
        'sessionId': f.service.sessionId,
        'messages': [
          {'messageId': 'm2', 'senderType': 'agent', 'text': 'second'},
          {'messageId': 'm1', 'senderType': 'agent', 'text': 'first'},
        ],
        'nextCursor': null,
      });
      expect(f.service.messages.map((m) => m.text), [
        'first',
        'second',
        'third',
        'fourth',
      ]);
      expect(f.service.nextCursor, isNull);
      expect(f.service.loadOlder(), false);
      f.service.dispose();
    },
  );
  testWidgets(
    'history timeout offers retry and stale request responses cannot replace its cursor',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      final old = f.historyRequest;
      await tester.pump(const Duration(seconds: 16));
      expect(f.service.loadingHistory, false);
      expect(f.service.historyError, isNotNull);
      expect(f.service.retryHistory(), true);
      final current = f.historyRequest;
      expect(current, isNot(old));
      f.channels.single.receive({
        'type': 'session_messages',
        'requestId': old,
        'sessionId': f.service.sessionId,
        'messages': [],
        'nextCursor': 'stale',
      });
      expect(f.service.loadingHistory, true);
      expect(f.service.nextCursor, isNull);
      f.channels.single.receive({
        'type': 'history_error',
        'requestId': current,
        'sessionId': f.service.sessionId,
      });
      expect(f.service.loadingHistory, false);
      expect(f.service.ready, true);
      f.service.dispose();
    },
  );
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  testWidgets(
    'customer uploads privately then publishes only a correlated reference',
    (tester) async {
      final f = Fixture(
        imageClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fresh-token');
          expect(request.headers['X-Support-User-Type'], 'customer');
          final body = jsonDecode(request.body);
          expect(base64Decode(body['dataBase64']), png);
          return http.Response(
            jsonEncode({'attachmentId': body['uploadId']}),
            200,
          );
        }),
      );
      await f.service.connect();
      f.confirm();
      f.service.draft = 'صورة الطلب';
      expect(await f.service.sendImage(png, 'صورة الطلب'), true);
      final frame = f.channels.single.sent.last;
      expect(frame['attachmentId'], frame['clientMessageId']);
      expect(frame.containsKey('dataBase64'), false);
      expect(f.service.messages.single.isUploading, false);
      expect(f.service.messages.single.status, 'pending');
      expect(f.service.draft, '');
      f.channels.single.receive({
        'type': 'message_ack',
        'sessionId': f.service.sessionId,
        'clientMessageId': frame['clientMessageId'],
        'messageId': 'saved',
      });
      expect(f.service.messages.single.status, 'accepted');
      f.service.dispose();
    },
  );
  testWidgets(
    'rejected upload preserves caption and never sends an image message',
    (tester) async {
      final f = Fixture(
        imageClient: MockClient((_) async => http.Response('{}', 403)),
      );
      await f.service.connect();
      f.confirm();
      f.service.draft = 'احتفظ';
      final count = f.channels.single.sent.length;
      expect(await f.service.sendImage(png, 'احتفظ'), false);
      expect(f.channels.single.sent.length, count);
      expect(f.service.draft, 'احتفظ');
      expect(f.service.messages.single.isUploading, false);
      expect(f.service.messages.single.status, 'failed');
      f.service.dispose();
    },
  );
  testWidgets('unsupported or oversized bytes are rejected before HTTP', (
    tester,
  ) async {
    var requests = 0;
    final f = Fixture(
      imageClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    await f.service.connect();
    f.confirm();
    expect(await f.service.sendImage(Uint8List.fromList([1, 2, 3]), ''), false);
    expect(
      await f.service.sendImage(
        Uint8List(SupportChatService.maxImageBytes + 1),
        '',
      ),
      false,
    );
    expect(requests, 0);
    expect(f.service.messages, isEmpty);
    f.service.dispose();
  });
  testWidgets(
    'upload completing after server closure cannot publish into new conversation',
    (tester) async {
      final response = Completer<http.Response>(), started = Completer<void>();
      String? uploadId;
      final f = Fixture(
        imageClient: MockClient((request) {
          uploadId = jsonDecode(request.body)['uploadId'];
          started.complete();
          return response.future;
        }),
      );
      await f.service.connect();
      f.confirm();
      final upload = f.service.sendImage(png, 'caption');
      await started.future;
      f.channels.single.receive({
        'type': 'session_closed',
        'sessionId': f.service.sessionId,
      });
      await f.service.startNewConversation();
      f.confirm();
      final count = f.channels.last.sent.length;
      response.complete(
        http.Response(jsonEncode({'attachmentId': uploadId}), 200),
      );
      expect(await upload, false);
      expect(f.channels.last.sent.length, count);
      expect(f.service.messages, isEmpty);
      f.service.dispose();
    },
  );
  testWidgets(
    'image download authenticates session and rejects mismatched identity',
    (tester) async {
      var wrong = false;
      final f = Fixture(
        imageClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['sessionId'], isNotEmpty);
          expect(request.headers['X-Support-User-Type'], 'customer');
          return http.Response(
            jsonEncode({
              'attachmentId': wrong ? 'other' : 'image-1',
              'contentType': 'image/png',
              'dataBase64': base64Encode(png),
            }),
            200,
          );
        }),
      );
      await f.service.connect();
      f.confirm();
      expect(await f.service.loadImage('image-1'), png);
      wrong = true;
      await expectLater(f.service.loadImage('image-1'), throwsStateError);
      f.service.dispose();
    },
  );
  testWidgets('late download after disposal cannot expose old session bytes', (
    tester,
  ) async {
    final response = Completer<http.Response>(), started = Completer<void>();
    final f = Fixture(
      imageClient: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    await f.service.connect();
    f.confirm();
    final check = expectLater(f.service.loadImage('image-1'), throwsStateError);
    await started.future;
    f.service.dispose();
    response.complete(
      http.Response(
        jsonEncode({
          'attachmentId': 'image-1',
          'contentType': 'image/png',
          'dataBase64': base64Encode(png),
        }),
        200,
      ),
    );
    await check;
  });
  testWidgets(
    'image preview loads only on demand and retries authentication failure',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportAttachmentImage(
              load: () async {
                calls++;
                throw StateError('expired');
              },
            ),
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.text('عرض الصورة'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('تعذر عرض الصورة؛ إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
  testWidgets(
    'latest history sorts saved older messages before an unsent local reply',
    (tester) async {
      final f = Fixture();
      await f.service.connect();
      f.confirm();
      f.service.send('new local');
      f.channels.single.receive({
        'type': 'session_messages',
        'requestId': f.historyRequest,
        'sessionId': f.service.sessionId,
        'messages': [
          {
            'messageId': 'old',
            'senderType': 'agent',
            'text': 'old reply',
            'createdAt': '2020-01-01T00:00:00Z',
          },
        ],
      });
      expect(f.service.messages.map((m) => m.text), ['old reply', 'new local']);
      f.service.dispose();
    },
  );
  testWidgets(
    'image preview displays valid PNG bytes and late results after removal stay hidden',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SupportAttachmentImage(load: () async => png)),
        ),
      );
      await tester.tap(find.text('عرض الصورة'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
      final pending = Completer<Uint8List>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportAttachmentImage(
              key: const ValueKey('other'),
              load: () => pending.future,
            ),
          ),
        ),
      );
      await tester.tap(find.text('عرض الصورة'));
      await tester.pump();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('حساب آخر'))),
      );
      pending.complete(png);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
