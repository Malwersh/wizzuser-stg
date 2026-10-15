import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../config.dart';
import "session_service.dart";

class UserProfileService {
  // استخدام URL الموحد من التكوين
  static String get baseUrl => ApiConfig.baseUrl;

  /// جلب المعلومات الشخصية من قاعدة البيانات WizzUser_users_dev
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      // التحقق من صحة userId
      if (userId.isEmpty ||
          userId == 'placeholder_user_id' ||
          userId == 'default_user_id') {
        print('⚠️ تحذير: استخدام userId غير صالح ($userId)');
        return null; // إرجاع null بدلاً من بيانات افتراضية
      }

      // التحقق من أن userId يبدأ بـ user_ (تنسيق صحيح)
      if (!userId.startsWith('user_') && !userId.contains('@')) {
        print('⚠️ تحذير: تنسيق userId غير متوقع: $userId');
      }

      final token = SessionService.instance.accessToken;

      print('🔍 جلب المعلومات الشخصية للمستخدم: $userId');
      print('🌐 API URL: $baseUrl/users/$userId/profile');

      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId/profile'),
        headers: {
          'Content-Type': 'application/json',
          // فقط إضافة Authorization إذا كان التوكن حقيقي
          if (token != null &&
              token.isNotEmpty &&
              token != 'placeholder_access_token')
            'Authorization': 'Bearer $token',
        },
      );

      print('📊 Get Profile Response: ${response.statusCode}');
      print('📋 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final userData = data['data'] ?? data;
        return userData;
      } else if (response.statusCode == 404) {
        print('❌ المستخدم غير موجود في قاعدة البيانات (404)');
        print('💡 تأكد من أن userId صحيح: $userId');
        return null;
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        print('🔒 غير مخول للوصول (${response.statusCode})');
        print('💡 تحقق من صحة الـ token أو إعادة تسجيل الدخول');
        return null;
      } else {
        print('❌ خطأ في جلب المعلومات: ${response.statusCode}');
        print('📋 رد الخادم: ${response.body}');
        return null;
      }
    } catch (e) {
      print('💥 استثناء في جلب المعلومات: $e');
      print('🔍 تحقق من الاتصال بالإنترنت والـ API URL');
      return null;
    }
  }

  /// تحديث المعلومات الشخصية في قاعدة البيانات WizzUser_users_dev
  static Future<Map<String, dynamic>> updatePersonalInfo({
    required String userId,
    String? name,
    String? gender,
    String? birthdate,
    bool? marketingConsent,
    bool? newsletterSubscription,
  }) async {
    try {
      // التحقق من صحة userId
      if (userId.isEmpty ||
          userId == 'placeholder_user_id' ||
          userId == 'default_user_id') {
        print('❌ خطأ: معرف المستخدم غير صالح ($userId)');
        return {
          'success': false,
          'message': 'معرف المستخدم غير صالح، يرجى إعادة تسجيل الدخول',
        };
      }

      // التحقق من أن userId يبدأ بـ user_ (تنسيق صحيح)
      if (!userId.startsWith('user_') && !userId.contains('@')) {
        print('⚠️ تحذير: تنسيق userId غير متوقع: $userId');
      }

      final token = SessionService.instance.accessToken;

      final requestData = <String, dynamic>{};
      if (name != null) requestData['name'] = name;
      if (gender != null) requestData['gender'] = gender;
      if (birthdate != null) requestData['birth_date'] = birthdate;
      if (marketingConsent != null)
        requestData['marketing_consent'] = marketingConsent;
      if (newsletterSubscription != null)
        requestData['newsletter_subscription'] = newsletterSubscription;

      print('📤 تحديث المعلومات للمستخدم: $userId');
      print('📋 البيانات المرسلة: $requestData');

      final response = await http.put(
        Uri.parse('$baseUrl/users/$userId/profile'),
        headers: {
          'Content-Type': 'application/json',
          // فقط إضافة Authorization إذا كان التوكن حقيقي
          if (token != null &&
              token.isNotEmpty &&
              token != 'placeholder_access_token')
            'Authorization': 'Bearer $token',
        },
        body: json.encode(requestData),
      );

      print('📊 Update Profile Response: ${response.statusCode}');
      print('📋 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'تم تحديث المعلومات بنجاح',
          'data': data,
        };
      } else if (response.statusCode == 404) {
        print('❌ المستخدم غير موجود في قاعدة البيانات (404)');
        return {
          'success': false,
          'message': 'المستخدم غير موجود، يرجى إعادة تسجيل الدخول',
        };
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        print('🔒 غير مخول للوصول (${response.statusCode})');
        return {
          'success': false,
          'message': 'غير مخول للوصول، يرجى إعادة تسجيل الدخول',
        };
      } else {
        try {
          final errorData = json.decode(response.body);
          print('❌ خطأ في تحديث المعلومات: ${errorData['message']}');
          return {
            'success': false,
            'message': errorData['message'] ?? 'خطأ في تحديث المعلومات',
          };
        } catch (parseError) {
          print('❌ خطأ في تحليل رد الخادم: ${response.body}');
          return {
            'success': false,
            'message': 'خطأ في تحديث المعلومات (${response.statusCode})',
          };
        }
      }
    } catch (e) {
      print('💥 استثناء في تحديث المعلومات: $e');
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  /// تحديث تفضيلات اللغة
  static Future<Map<String, dynamic>> updateLanguagePreference({
    required String userId,
    required String language,
  }) async {
    try {
      final token = SessionService.instance.accessToken;

      print('🌐 تحديث تفضيل اللغة للمستخدم: $userId');
      print('🗣️ اللغة الجديدة: $language');

      final response = await http.put(
        Uri.parse('$baseUrl/users/$userId/language'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        body: json.encode({'language': language}),
      );

      print('📊 Update Language Response: ${response.statusCode}');
      print('📋 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'تم تحديث تفضيل اللغة بنجاح',
          'data': data,
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'خطأ في تحديث تفضيل اللغة',
        };
      }
    } catch (e) {
      print('💥 استثناء في تحديث تفضيل اللغة: $e');
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  /// تغيير كلمة المرور
  static Future<Map<String, dynamic>> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final token = SessionService.instance.accessToken;

      print('🔐 تغيير كلمة المرور للمستخدم: $userId');

      final response = await http.put(
        Uri.parse('$baseUrl/users/$userId/password'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null &&
              token.isNotEmpty &&
              token != 'placeholder_access_token')
            'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      print('📊 Change Password Response: ${response.statusCode}');
      print('📋 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'تم تغيير كلمة المرور بنجاح',
          'data': data,
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'خطأ في تغيير كلمة المرور',
        };
      }
    } catch (e) {
      print('💥 استثناء في تغيير كلمة المرور: $e');
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }
}
