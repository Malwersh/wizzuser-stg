import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Authenticated bytes only. Public image URLs never enter a support message.
class SupportPrivateImages {
  SupportPrivateImages({
    required this.endpoint,
    required this.role,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String endpoint, role;
  final Future<String> Function() token;
  final http.Client _client;
  static const maxBytes = 2 * 1024 * 1024;
  Uri _uri() {
    final uri = Uri.parse(endpoint);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment)
      throw StateError('ATTACHMENTS_UNAVAILABLE');
    return uri;
  }

  static String contentType(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes)
      throw StateError('INVALID_IMAGE_SIZE');
    if (bytes.length >= 8 &&
        listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]))
      return 'image/png';
    if (bytes.length >= 4 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[bytes.length - 2] == 255 &&
        bytes.last == 217)
      return 'image/jpeg';
    throw StateError('INVALID_IMAGE_TYPE');
  }

  Future<Map<String, String>> _headers() async => {
    'Authorization': 'Bearer ${await token()}',
    'X-Support-User-Type': role,
    'Content-Type': 'application/json',
  };
  Future<String> upload({
    required String sessionId,
    required String uploadId,
    required Uint8List bytes,
    required bool Function() isCurrent,
  }) async {
    final content = contentType(bytes), uri = _uri();
    final headers = await _headers();
    if (!isCurrent()) throw StateError('SESSION_CHANGED');
    final response = await _client
        .post(
          uri,
          headers: headers,
          body: jsonEncode({
            'sessionId': sessionId,
            'uploadId': uploadId,
            'contentType': content,
            'dataBase64': base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (!isCurrent() || response.statusCode != 200)
      throw StateError('UPLOAD_UNCONFIRMED');
    final result = jsonDecode(response.body);
    if (result is! Map || result['attachmentId'] != uploadId)
      throw StateError('INVALID_UPLOAD_RECEIPT');
    return uploadId;
  }

  Future<Uint8List> load({
    required String sessionId,
    required String attachmentId,
    required bool Function() isCurrent,
  }) async {
    final uri = _uri().replace(
      queryParameters: {'sessionId': sessionId, 'attachmentId': attachmentId},
    );
    final headers = await _headers();
    if (!isCurrent()) throw StateError('SESSION_CHANGED');
    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (!isCurrent() ||
        response.statusCode != 200 ||
        response.body.length > 3 * 1024 * 1024)
      throw StateError('ATTACHMENT_UNAVAILABLE');
    final result = jsonDecode(response.body);
    if (result is! Map ||
        result['attachmentId'] != attachmentId ||
        !['image/png', 'image/jpeg'].contains(result['contentType']))
      throw StateError('INVALID_ATTACHMENT');
    final bytes = base64Decode(result['dataBase64'] as String);
    if (contentType(bytes) != result['contentType'])
      throw StateError('INVALID_ATTACHMENT');
    return bytes;
  }

  void dispose() => _client.close();
}
