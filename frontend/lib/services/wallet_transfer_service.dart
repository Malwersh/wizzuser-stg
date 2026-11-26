import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import '../config/api_config.dart';
import 'session_service.dart';

class WalletTransferException implements Exception {
  final String message;
  final String? code;
  WalletTransferException(this.message, [this.code]);
  @override
  String toString() => message;
}

class WalletTransferService {
  static const _baseUrl = String.fromEnvironment(
    'WALLET_TRANSFER_API_URL',
    defaultValue: ApiConfig.isProduction
        ? ''
        : 'https://z14s5f8oxh.execute-api.us-east-1.amazonaws.com/staging',
  );
  static const productionInboxUrl =
      'https://0mar06hzr1.execute-api.us-east-1.amazonaws.com/production';

  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    String? expectedSubject,
  }) async {
    final isInbox = path == 'notifications';
    final baseUrl = isInbox && ApiConfig.isProduction
        ? productionInboxUrl
        : _baseUrl;
    if (baseUrl.isEmpty) {
      throw WalletTransferException('خدمة التحويل غير متاحة حاليًا.');
    }
    final token = await SessionService.instance.getToken();
    if (token == null ||
        (expectedSubject != null &&
            JwtDecoder.decode(token)['sub'] != expectedSubject)) {
      throw WalletTransferException(
        'يرجى تسجيل الدخول مجددًا',
        'REAUTH_REQUIRED',
      );
    }
    final uri = Uri.parse(
      '$baseUrl/wallet/transfers/$path',
    ).replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = await (body == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 20));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      final error = json['error'];
      throw WalletTransferException(
        (error is Map ? error['message'] : json['message'])?.toString() ??
            'تعذر إكمال العملية',
        error is Map ? error['code']?.toString() : json['code']?.toString(),
      );
    }
    return (json['data'] ?? json) as Map<String, dynamic>;
  }
}
