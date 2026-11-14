import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/support_private_images.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  test(
    'upload authenticates scoped bytes and requires matching receipt',
    () async {
      final images = SupportPrivateImages(
        endpoint: 'https://support.invalid/images',
        role: 'customer',
        token: () async => 'token',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer token');
          expect(request.headers['X-Support-User-Type'], 'customer');
          final body = jsonDecode(request.body);
          expect(body['sessionId'], 'owned-session');
          expect(base64Decode(body['dataBase64']), png);
          return http.Response(
            jsonEncode({'attachmentId': body['uploadId']}),
            200,
          );
        }),
      );
      expect(
        await images.upload(
          sessionId: 'owned-session',
          uploadId: 'image-1',
          bytes: png,
          isCurrent: () => true,
        ),
        'image-1',
      );
      images.dispose();
    },
  );
  test('late upload result cannot publish into changed session', () async {
    final pending = Completer<http.Response>();
    bool current = true;
    final images = SupportPrivateImages(
      endpoint: 'https://support.invalid/images',
      role: 'customer',
      token: () async => 'token',
      client: MockClient((_) => pending.future),
    );
    final operation = images.upload(
      sessionId: 'old',
      uploadId: 'id',
      bytes: png,
      isCurrent: () => current,
    );
    final assertion = expectLater(operation, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete(http.Response('{"attachmentId":"id"}', 200));
    await assertion;
    images.dispose();
  });
  test(
    'rejects GIF oversized images and insecure endpoint before network',
    () async {
      var calls = 0;
      final images = SupportPrivateImages(
        endpoint: 'http://support.invalid/images',
        role: 'customer',
        token: () async => 'token',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      for (final data in [
        Uint8List.fromList(utf8.encode('GIF89a')),
        Uint8List(2 * 1024 * 1024 + 1),
        png,
      ]) {
        await expectLater(
          images.upload(
            sessionId: 's',
            uploadId: 'i',
            bytes: data,
            isCurrent: () => true,
          ),
          throwsStateError,
        );
      }
      expect(calls, 0);
      images.dispose();
    },
  );
  test(
    'private image read validates identity header reference and bytes',
    () async {
      final images = SupportPrivateImages(
        endpoint: 'https://support.invalid/images',
        role: 'customer',
        token: () async => 'new-token',
        client: MockClient((request) async {
          expect(request.url.queryParameters, {
            'sessionId': 's',
            'attachmentId': 'i',
          });
          expect(request.headers['Authorization'], 'Bearer new-token');
          return http.Response(
            jsonEncode({
              'attachmentId': 'i',
              'contentType': 'image/png',
              'dataBase64': base64Encode(png),
            }),
            200,
          );
        }),
      );
      expect(
        await images.load(
          sessionId: 's',
          attachmentId: 'i',
          isCurrent: () => true,
        ),
        png,
      );
      images.dispose();
    },
  );
  test('forged download reference is rejected', () async {
    final images = SupportPrivateImages(
      endpoint: 'https://support.invalid/images',
      role: 'customer',
      token: () async => 'token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'attachmentId': 'other',
            'contentType': 'image/png',
            'dataBase64': base64Encode(png),
          }),
          200,
        ),
      ),
    );
    await expectLater(
      images.load(sessionId: 's', attachmentId: 'i', isCurrent: () => true),
      throwsStateError,
    );
    images.dispose();
  });
}
