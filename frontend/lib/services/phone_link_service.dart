import '../utils/iraqi_phone.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';

class PhoneLinkException implements Exception {
  final String message;
  final String? code;
  const PhoneLinkException(this.message, [this.code]);
  @override
  String toString() => message;
}

class PhoneLinkService {
  final http.Client _client;
  final Future<String?> Function() _token;
  final String? Function() _owner;
  PhoneLinkService({
    http.Client? client,
    Future<String?> Function()? token,
    String? Function()? owner,
  }) : _client = client ?? http.Client(),
       _token = token ?? SessionService.instance.getToken,
       _owner = owner ?? (() => SessionService.instance.currentUserId);
  static const baseUrl = String.fromEnvironment(
    'PHONE_LINK_API_URL',
    defaultValue:
        'https://mawqyuutz4.execute-api.us-east-1.amazonaws.com/staging',
  );
  Future<Map<String, dynamic>> call(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final owner = _owner();
    if (owner == null)
      throw const PhoneLinkException(
        'سجّل الدخول لإدارة رقم هاتفك',
        'AUTH_REQUIRED',
      );
    if (path == 'send' && body != null)
      body = {
        ...body,
        'phone': IraqiPhone.normalize(body['phone']?.toString() ?? ''),
      };
    final token = await _token();
    if (owner != _owner())
      throw const PhoneLinkException(
        'تغيّر الحساب؛ أعد فتح الصفحة',
        'ACCOUNT_CHANGED',
      );
    if (token == null)
      throw const PhoneLinkException(
        'تعذر تجديد الجلسة؛ أعد المحاولة أو سجّل الدخول',
        'AUTH_REQUIRED',
      );
    final uri = Uri.parse('$baseUrl/phone/$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = await (body == null
            ? _client.get(uri, headers: headers)
            : _client.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 25));
    if (owner != _owner())
      throw const PhoneLinkException(
        'تغيّر الحساب؛ أعد فتح الصفحة',
        'ACCOUNT_CHANGED',
      );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400)
      throw PhoneLinkException(
        data['message']?.toString() ?? 'تعذر إكمال العملية',
        data['code']?.toString(),
      );
    return data;
  }
}
