import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'session_service.dart';
import '../config/api_config.dart';
import 'customer_support_chat.dart';

class CustomerOrderComplaintService {
  final http.Client client;
  final Future<String?> Function() token;
  static const orders = String.fromEnvironment(
    'ORDER_SERVICE_URL',
    defaultValue:
        ApiConfig.environment == 'staging'
            ? 'https://mqwom78d3c.execute-api.us-east-1.amazonaws.com/staging'
            : '',
  );
  static const _productionEndpoint = String.fromEnvironment(
    'CUSTOMER_COMPLAINT_URL',
    defaultValue:
        'https://huytzvtrki.execute-api.us-east-1.amazonaws.com/production/complaints/customer',
  );
  static const attachments = String.fromEnvironment(
    'SUPPORT_ATTACHMENTS_URL',
    defaultValue: CustomerSupportChat.attachmentsEndpoint,
  );
  CustomerOrderComplaintService({
    http.Client? client,
    Future<String?> Function()? token,
  }) : client = client ?? http.Client(),
       token = token ?? SessionService.instance.getToken;

  Future<void> _assertSameSession(String original) async {
    final current = await token();
    if (current == original) return;
    if (current != null) {
      try {
        final before = JwtDecoder.decode(original)['sub'];
        final after = JwtDecoder.decode(current)['sub'];
        if (before is String && before.isNotEmpty && before == after) return;
      } on Exception {
        throw StateError('UNAUTHORIZED');
      }
    }
    throw StateError('UNAUTHORIZED');
  }

  Future<Map<String, dynamic>> call(
    String orderId,
    Map<String, dynamic> input,
  ) async {
    final credential = await token();
    if (credential == null || credential.isEmpty) {
      throw StateError('UNAUTHORIZED');
    }
    final response = await client
        .post(
          Uri.parse(
            ApiConfig.isProduction
                ? _productionEndpoint
                : '$orders/order/cancel',
          ),
          headers: {
            'Authorization': 'Bearer $credential',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            ...input,
            'orderId': orderId,
            if (!ApiConfig.isProduction) 'workflow': 'CUSTOMER_POST_DELIVERY',
          }),
        )
        .timeout(const Duration(seconds: 20));
    await _assertSameSession(credential);
    final value = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        value is! Map<String, dynamic> ||
        value['success'] != true ||
        value['orderId'] != orderId) {
      throw StateError(
        value is Map
            ? '${value['code'] ?? 'COMPLAINT_UNAVAILABLE'}'
            : 'COMPLAINT_UNAVAILABLE',
      );
    }
    return value;
  }

  Future<String> upload(
    String orderId,
    String sessionId,
    Uint8List bytes,
    String contentType,
    String uploadId,
  ) async {
    if (bytes.length > 2 * 1024 * 1024 || bytes.isEmpty) {
      throw StateError('IMAGE_SIZE_INVALID');
    }
    final credential = await token();
    if (credential == null) throw StateError('UNAUTHORIZED');
    final response = await client
        .post(
          Uri.parse(attachments),
          headers: {
            'Authorization': 'Bearer $credential',
            'Content-Type': 'application/json',
            'X-Support-User-Type': 'customer',
          },
          body: jsonEncode({
            'sessionId': sessionId,
            'uploadId': uploadId,
            'contentType': contentType,
            'dataBase64': base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 25));
    await _assertSameSession(credential);
    final value = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        value is! Map ||
        value['attachmentId'] != uploadId) {
      throw StateError('COMPLAINT_IMAGE_UNAVAILABLE');
    }
    final chat = CustomerSupportChat(
      orderId: orderId,
      fixedSessionId: sessionId,
    );
    try {
      await chat.connect();
      if (!await chat.send(
        'صورة مرفقة لمراجعة شكوى الطلب',
        attachmentId: uploadId,
        clientMessageId: uploadId,
      )) {
        throw StateError('COMPLAINT_IMAGE_MESSAGE_UNCONFIRMED');
      }
    } finally {
      chat.dispose();
    }
    return uploadId;
  }

  Future<Uint8List> readImage(String sessionId, String attachmentId) async {
    final credential = await token();
    if (credential == null) throw StateError('UNAUTHORIZED');
    final response = await client
        .get(
          Uri.parse(attachments).replace(
            queryParameters: {
              'sessionId': sessionId,
              'attachmentId': attachmentId,
            },
          ),
          headers: {
            'Authorization': 'Bearer $credential',
            'X-Support-User-Type': 'customer',
          },
        )
        .timeout(const Duration(seconds: 20));
    await _assertSameSession(credential);
    final value = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        value is! Map ||
        value['attachmentId'] != attachmentId ||
        !['image/png', 'image/jpeg'].contains(value['contentType']) ||
        value['dataBase64'] is! String) {
      throw StateError('COMPLAINT_IMAGE_UNAVAILABLE');
    }
    final bytes = base64Decode(value['dataBase64']);
    if (bytes.length > 2 * 1024 * 1024) {
      throw StateError('COMPLAINT_IMAGE_UNAVAILABLE');
    }
    return bytes;
  }

  void dispose() => client.close();
}
