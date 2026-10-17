import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';

class PhoneLinkService {
  static const baseUrl = String.fromEnvironment(
    'PHONE_LINK_API_URL',
    defaultValue: 'https://mawqyuutz4.execute-api.us-east-1.amazonaws.com/staging',
  );
  Future<Map<String, dynamic>> call(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await SessionService.instance.getToken();
    if (token == null) throw Exception('يرجى تسجيل الدخول مجددًا');
    final uri = Uri.parse('$baseUrl/phone/$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = await (body == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 25));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['message'] ?? 'تعذر إكمال العملية');
    }
    return data;
  }
}
