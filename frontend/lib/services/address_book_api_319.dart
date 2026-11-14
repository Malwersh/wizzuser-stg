import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class AddressBookApi319 {
  static final instance = AddressBookApi319();
  final http.Client client;
  final Duration timeout;
  AddressBookApi319({
    http.Client? client,
    this.timeout = const Duration(seconds: 35),
  }) : client = client ?? http.Client();
  Future<Map<String, dynamic>> request({
    required String method,
    required String owner,
    required String token,
    String? addressId,
    bool setDefault = false,
    Map<String, dynamic>? body,
  }) async {
    final suffix =
        addressId == null
            ? ''
            : '/${Uri.encodeComponent(addressId)}${setDefault ? '/set-default' : ''}';
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/users/${Uri.encodeComponent(owner)}/addresses$suffix',
    );
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      final parsed =
          response.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(utf8.decode(response.bodyBytes));
      if ([200, 201, 204].contains(response.statusCode) &&
          parsed is Map &&
          parsed['success'] != false)
        return {'success': true, 'data': parsed, 'status': response.statusCode};
      return {
        'success': false,
        'status': response.statusCode,
        'code': parsed is Map ? parsed['code'] : null,
        'message':
            parsed is Map && parsed['message'] is String
                ? parsed['message']
                : 'تعذر إكمال العملية. أعد المحاولة.',
        'uncertain': response.statusCode >= 500,
      };
    } on TimeoutException {
      return {
        'success': false,
        'code': 'ADDRESS_RESULT_UNCERTAIN',
        'uncertain': true,
        'message':
            'لم يصل تأكيد العملية بعد. أعد المحاولة للتحقق من نتيجتها؛ لن نكرر حفظ العنوان.',
      };
    } catch (_) {
      return {
        'success': false,
        'code': 'ADDRESS_RESULT_UNCERTAIN',
        'uncertain': true,
        'message':
            'تعذر تأكيد العملية بسبب الاتصال. أعد المحاولة للتحقق من النتيجة.',
      };
    }
  }
}
