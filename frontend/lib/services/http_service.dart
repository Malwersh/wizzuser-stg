// lib/services/http_service.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import "session_service.dart";
import '../config/api_config.dart' as app_config;

class HttpService {
  static String get _baseUrl {
    final url = app_config.ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  /// إرسال طلب GET مع التوكن
  static Future<http.Response> get(String endpoint) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    final headers = await _getHeaders();
    
    return await http.get(url, headers: headers);
  }

  /// إرسال طلب POST مع التوكن
  static Future<http.Response> post(String endpoint, {Map<String, dynamic>? body}) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    final headers = await _getHeaders();
    
    return await http.post(
      url,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// إرسال طلب PUT مع التوكن
  static Future<http.Response> put(String endpoint, {Map<String, dynamic>? body}) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    final headers = await _getHeaders();
    
    return await http.put(
      url,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// إرسال طلب DELETE مع التوكن
  static Future<http.Response> delete(String endpoint) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    final headers = await _getHeaders();
    
    return await http.delete(url, headers: headers);
  }

  /// إرسال طلب بدون توكن (للمصادقة)
  static Future<http.Response> postPublic(String endpoint, {Map<String, dynamic>? body}) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    final headers = {'Content-Type': 'application/json'};
    
    // Add detailed logging for debugging
    developer.log('🌐 HTTP_DETAILED: Making POST request to: $url', name: 'HTTP_SERVICE');
    developer.log('📤 HTTP_DETAILED: Request headers: $headers', name: 'HTTP_SERVICE');
    developer.log('📤 HTTP_DETAILED: Request body: ${body != null ? jsonEncode(body) : "null"}', name: 'HTTP_SERVICE');
    
    try {
      final response = await http.post(
        url,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      
      developer.log('📥 HTTP_DETAILED: Response status: ${response.statusCode}', name: 'HTTP_SERVICE');
      developer.log('📥 HTTP_DETAILED: Response headers: ${response.headers}', name: 'HTTP_SERVICE');
      developer.log('📥 HTTP_DETAILED: Response body: ${response.body}', name: 'HTTP_SERVICE');
      
      return response;
    } catch (e) {
      developer.log('❌ HTTP_ERROR: Exception during request: $e', name: 'HTTP_SERVICE');
      rethrow;
    }
  }

  /// بناء headers مع التوكن
  static Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    
    // إضافة التوكن إذا كان متاحاً
    final token = await SessionService.instance.getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    return headers;
  }

  /// التحقق من حالة الاستجابة ومعالجة أخطاء التوكن
  static Future<Map<String, dynamic>> handleResponse(http.Response response) async {
    // إذا كان التوكن منتهي الصلاحية
    if (response.statusCode == 401) {
      await SessionService.instance.logout();
      return {
        'success': false,
        'message': 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مرة أخرى',
        'requiresLogin': true
      };
    }

    // تحديث وقت آخر نشاط عند النجاح
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Session refresh if needed - implement in SessionService if required
    }

    try {
      final responseData = jsonDecode(utf8.decode(response.bodyBytes));
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'data': responseData,
        'statusCode': response.statusCode
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'خطأ في معالجة الاستجابة',
        'statusCode': response.statusCode
      };
    }
  }
}
