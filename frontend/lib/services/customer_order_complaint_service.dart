import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
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
  static const attachments = String.fromEnvironment(
    'SUPPORT_ATTACHMENTS_URL',
    defaultValue:
        ApiConfig.environment == 'staging'
            ? 'https://5ytyphpnkc.execute-api.us-east-1.amazonaws.com/staging/support/attachments'
            : '',
  );
  CustomerOrderComplaintService({
    http.Client? client,
    Future<String?> Function()? token,
  }) : client = client ?? http.Client(),
       token =
           token ?? (() => Future.value(SessionService.instance.accessToken));
  Future<Map<String, dynamic>> call(
    String orderId,
    Map<String, dynamic> input,
  ) async {
    final credential = await token();
    if (credential == null || credential.isEmpty)
      throw StateError('UNAUTHORIZED');
    final response = await client
        .post(
          Uri.parse('$orders/order/cancel'),
          headers: {
            'Authorization': 'Bearer $credential',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            ...input,
            'orderId': orderId,
            'workflow': 'CUSTOMER_POST_DELIVERY',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (await token() != credential) throw StateError('UNAUTHORIZED');
    final value = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        value is! Map<String, dynamic> ||
        value['success'] != true ||
        value['orderId'] != orderId)
      throw StateError(
        value is Map
            ? '${value['code'] ?? 'COMPLAINT_UNAVAILABLE'}'
            : 'COMPLAINT_UNAVAILABLE',
      );
    return value;
  }

  Future<String> upload(
    String orderId,
    String sessionId,
    Uint8List bytes,
    String contentType,
    String uploadId,
  ) async {
    if (bytes.length > 2 * 1024 * 1024 || bytes.isEmpty)
      throw StateError('IMAGE_SIZE_INVALID');
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
    if (await token() != credential) throw StateError('UNAUTHORIZED');
    final value = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        value is! Map ||
        value['attachmentId'] != uploadId)
      throw StateError('COMPLAINT_IMAGE_UNAVAILABLE');
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
      ))
        throw StateError('COMPLAINT_IMAGE_MESSAGE_UNCONFIRMED');
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
    if (await token() != credential) throw StateError('UNAUTHORIZED');
    final value = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        value is! Map ||
        value['attachmentId'] != attachmentId ||
        !['image/png', 'image/jpeg'].contains(value['contentType']) ||
        value['dataBase64'] is! String)
      throw StateError('COMPLAINT_IMAGE_UNAVAILABLE');
    final bytes = base64Decode(value['dataBase64']);
    if (bytes.length > 2 * 1024 * 1024)
      throw StateError('COMPLAINT_IMAGE_UNAVAILABLE');
    return bytes;
  }

  void dispose() => client.close();
}
