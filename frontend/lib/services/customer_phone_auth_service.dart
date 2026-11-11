import '../utils/iraqi_phone.dart';
import '../models/customer_legal_bundle.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';

class CustomerPhoneAuthException implements Exception {
  final String message;
  final String? code;
  const CustomerPhoneAuthException(this.message, [this.code]);
  @override
  String toString() => message;
}

class CustomerPhoneAuthService {
  final http.Client _client;
  final String? expectedOwner;
  CustomerPhoneAuthService({http.Client? client, this.expectedOwner})
    : _client = client ?? http.Client();
  static const baseUrl = String.fromEnvironment(
    'PHONE_AUTH_API_URL',
    defaultValue:
        'https://f44z33oz55.execute-api.us-east-1.amazonaws.com/staging',
  );
  String? _sessionId, _phone;
  CustomerLegalBundle? enrollmentPolicy;
  static String normalizePhone(String input) {
    try {
      return IraqiPhone.normalize(input);
    } on FormatException {
      throw const CustomerPhoneAuthException('أدخل رقم هاتف عراقي صحيح');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (baseUrl.isEmpty)
      throw const CustomerPhoneAuthException('خدمة الدخول غير مهيأة');
    final response = await _client
        .post(
          Uri.parse('$baseUrl/auth/phone/$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 35));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200)
      throw CustomerPhoneAuthException(
        data['message']?.toString() ?? 'تعذر إكمال العملية',
        data['code']?.toString(),
      );
    return data;
  }

  Future<void> send(String phone) async {
    final normalized = normalizePhone(phone);
    final r = await _post('send', {'phone': normalized});
    _phone = normalized;
    _sessionId = r['sessionId'] as String;
  }

  Future<bool> verify(
    String code, {
    String? name,
    bool accepted = false,
  }) async {
    if (_sessionId == null || _phone == null)
      throw const CustomerPhoneAuthException('اطلب رمز التحقق أولًا');
    final digits = code.trim().replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
      final x = m[0]!.codeUnitAt(0);
      return '${x >= 0x6f0 ? x - 0x6f0 : x - 0x660}';
    });
    if (!RegExp(r'^[0-9]{6}$').hasMatch(digits))
      throw const CustomerPhoneAuthException('أدخل رمز التحقق من 6 أرقام');
    final r = await _post('verify', {
      'phone': _phone,
      'sessionId': _sessionId,
      'code': digits,
      'name': name,
      'termsAccepted': accepted,
      'privacyAccepted': accepted,
      'usageAccepted': accepted,
      if (accepted && enrollmentPolicy != null)
        'legalAcceptance': enrollmentPolicy!.pin,
    });
    if (expectedOwner != null &&
        (r['needsName'] == true ||
            r['user']?['userId'] != expectedOwner ||
            SessionService.instance.currentUserId != expectedOwner)) {
      throw const CustomerPhoneAuthException(
        'لم يتم تأكيد الحساب الحالي؛ لم تتغير جلستك',
        'ACCOUNT_MISMATCH',
      );
    }
    if (r['needsName'] == true) return false;
    await SessionService.instance.saveUserSession(
      accessToken: r['accessToken'] as String,
      idToken: r['idToken'] as String,
      refreshToken: r['refreshToken'] as String,
      userData: Map<String, dynamic>.from(r['user']),
    );
    return true;
  }
}
