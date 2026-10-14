import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'session_service.dart';

class AccountDeletionService {
  static const _base = String.fromEnvironment(
    'ACCOUNT_DELETION_API_URL',
    defaultValue:
        'https://77j15qyukg.execute-api.us-east-1.amazonaws.com/staging',
  );
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accountName: 'wizz_account_deletion'),
    aOptions: AndroidOptions(sharedPreferencesName: 'wizz_account_deletion'),
  );

  static Future<bool> hasSavedReceipt() async =>
      await _storage.read(key: 'receipt') != null;

  Future<Map<String, dynamic>> _receipt() async {
    final saved = await _storage.read(key: 'receipt');
    if (saved == null) throw Exception('يرجى تسجيل الدخول إلى حسابك');
    final receipt = jsonDecode(saved) as Map<String, dynamic>;
    final current = SessionService().currentUserId;
    if (SessionService().isLoggedIn && current != receipt['ownerId']) {
      throw Exception('يرجى تسجيل الدخول إلى حسابك');
    }
    try {
      return await _request('receipt', body: {'receiptToken': receipt['token']});
    } on _AuthenticationExpired {
      throw Exception('انتهت صلاحية إيصال المتابعة؛ تواصل مع الدعم بمرجع طلبك');
    }
  }

  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = SessionService().accessToken;
    if (token == null || token.isEmpty) {
      if (path == 'status') return _receipt();
      throw Exception('يرجى تسجيل الدخول إلى حسابك');
    }
    try {
      final result = await _request(path, token: token, body: body);
      if (result['receiptToken'] is String) {
        await _storage.write(
          key: 'receipt',
          value: jsonEncode({
            'ownerId': SessionService().currentUserId,
            'token': result['receiptToken'],
          }),
        );
      }
      return result;
    } on _AuthenticationExpired {
      if (path == 'status') return _receipt();
      throw Exception('يرجى تسجيل الدخول إلى حسابك');
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse('$_base/deletion/$path');
    final response = await (body == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401) throw _AuthenticationExpired();
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(
        data['message'] ??
            'تعذر إكمال العملية؛ حدّث حالة الطلب قبل إعادة المحاولة',
      );
    }
    return data;
  }
}

class _AuthenticationExpired implements Exception {}
