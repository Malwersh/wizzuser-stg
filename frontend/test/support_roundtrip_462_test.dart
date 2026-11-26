import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/customer_support_chat.dart';
import 'customer_support_chat_test.dart' show FakeTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  test(
    'uncertain receipt survives reopening without automatic resend',
    () async {
      final store = <String, String>{};
      var socket = FakeTransport();
      CustomerSupportChat create() => CustomerSupportChat(
        orderId: 'order',
        fixedSessionId: 'owned',
        identity:
            () async => const SupportIdentity('owner', 'token', 'name', ''),
        transport: (_, __) => socket,
        readSession: (k) async => store[k],
        saveSession: (k, v) async {
          store[k] = v;
        },
        timeout: const Duration(milliseconds: 40),
      );
      var chat = create();
      await chat.connect();
      socket.receipt = false;
      expect(await chat.send('لا تتكرر'), false);
      final id = socket.sent.last['clientMessageId'];
      chat.dispose();
      await socket.events.close();
      socket = FakeTransport();
      chat = create();
      await chat.connect();
      expect(socket.sent.where((m) => m['action'] == 'chat_message'), isEmpty);
      expect(await chat.send('لا تتكرر'), true);
      expect(socket.sent.last['clientMessageId'], id);
      chat.dispose();
      await socket.events.close();
    },
  );
  test(
    'draft restores only within authenticated owner and backend scope',
    () async {
      final store = <String, String>{};
      String owner = 'alice';
      var socket = FakeTransport();
      CustomerSupportChat create() => CustomerSupportChat(
        orderId: 'order',
        fixedSessionId: 'owned',
        identity: () async => SupportIdentity(owner, 'token', 'name', ''),
        transport: (_, __) => socket,
        readSession: (k) async => store[k],
        saveSession: (k, v) async {
          store[k] = v;
        },
      );
      var chat = create();
      await chat.connect();
      chat.setDraft('مسودة خاصة');
      chat.dispose();
      await Future<void>.delayed(Duration.zero);
      await socket.events.close();
      socket = FakeTransport();
      chat = create();
      await chat.connect();
      expect(chat.draft, 'مسودة خاصة');
      chat.dispose();
      await socket.events.close();
      owner = 'bob';
      socket = FakeTransport();
      chat = create();
      await chat.connect();
      expect(chat.draft, isEmpty);
      chat.dispose();
      await socket.events.close();
    },
  );
  test(
    'image receipt failure retry reuses upload and confirmed message reference',
    () async {
      final socket = FakeTransport();
      int uploads = 0;
      final chat = CustomerSupportChat(
        orderId: 'order',
        fixedSessionId: 'owned',
        identity:
            () async => const SupportIdentity('owner', 'token', 'name', ''),
        transport: (_, __) => socket,
        readSession: (_) async => null,
        saveSession: (_, __) async {},
        timeout: const Duration(milliseconds: 40),
        imageClient: MockClient((r) async {
          uploads++;
          return http.Response(
            jsonEncode({'attachmentId': jsonDecode(r.body)['uploadId']}),
            200,
          );
        }),
      );
      await chat.connect();
      socket.receipt = false;
      expect(await chat.sendImage(png), false);
      final id = socket.sent.last['clientMessageId'];
      socket.receipt = true;
      expect(await chat.sendImage(png), true);
      expect(uploads, 1);
      expect(socket.sent.last['clientMessageId'], id);
      expect(chat.messages.single['attachment']['attachmentId'], id);
      chat.dispose();
      await socket.events.close();
    },
  );
  test(
    'invalidating identity during upload cannot publish or retain transcript',
    () async {
      final pending = Completer<http.Response>(), socket = FakeTransport();
      final chat = CustomerSupportChat(
        orderId: 'order',
        fixedSessionId: 'owned',
        identity:
            () async => const SupportIdentity('owner', 'token', 'name', ''),
        transport: (_, __) => socket,
        readSession: (_) async => null,
        saveSession: (_, __) async {},
        imageClient: MockClient((_) => pending.future),
      );
      await chat.connect();
      final send = chat.sendImage(png);
      await Future<void>.delayed(Duration.zero);
      chat.invalidateIdentity();
      pending.complete(http.Response('{"attachmentId":"wrong"}', 200));
      expect(await send, false);
      expect(socket.sent.where((m) => m['action'] == 'chat_message'), isEmpty);
      expect(chat.messages, isEmpty);
      chat.dispose();
      await socket.events.close();
    },
  );
}
