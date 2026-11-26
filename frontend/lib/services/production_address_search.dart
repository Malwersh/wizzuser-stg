import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'session_service.dart';

class ProductionAddressSearch {
  static Future<Map<String, dynamic>?> request(Map<String, String> body) async {
    final session = SessionService.instance;
    final user = session.currentUserId;
    if (!session.isLoggedIn || session.isGuest || user == null) return null;

    final token = await session.getToken();
    if (token == null || session.currentUserId != user) {
      throw StateError('Address search session unavailable');
    }
    final endpoint = '/users/${Uri.encodeComponent(user)}/address-search';
    final response = await http
        .post(
          Uri.parse(ApiConfig.buildUrl(endpoint)),
          headers: ApiConfig.getAuthHeaders(token),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200 || session.currentUserId != user) {
      throw StateError('Address search unavailable');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
