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
        return null; // إرجاع null بدلاً من بيانات افتراضية
      }

      // التحقق من أن userId يبدأ بـ user_ (تنسيق صحيح)
      if (!userId.startsWith('user_') && !userId.contains('@')) {}

      final owner = SessionService.instance.currentUserId;
      if (owner == null || owner != userId) {
        throw StateError('ACCOUNT_MISMATCH');
      }
      final token = await SessionService.instance.getToken();
      if (token == null ||
          token.isEmpty ||
          SessionService.instance.currentUserId != owner) {
        throw StateError('AUTH_REQUIRED');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/users/$userId/profile'),
            headers: {
              'Content-Type': 'application/json',
              // فقط إضافة Authorization إذا كان التوكن حقيقي
              if (token.isNotEmpty && token != 'placeholder_access_token')
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (SessionService.instance.currentUserId != owner) {
        throw StateError('ACCOUNT_CHANGED');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final userData = data['data'] ?? data;
        return userData;
      } else if (response.statusCode == 404) {
        return null;
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        return null;
      } else {
        return null;
      }
    } catch (e) {
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
        return {
          'success': false,
          'message': 'معرف المستخدم غير صالح، يرجى إعادة تسجيل الدخول',
        };
      }

      // التحقق من أن userId يبدأ بـ user_ (تنسيق صحيح)
      if (!userId.startsWith('user_') && !userId.contains('@')) {}

      final owner = SessionService.instance.currentUserId;
      if (owner == null || owner != userId) {
        throw StateError('ACCOUNT_MISMATCH');
      }
      final token = await SessionService.instance.getToken();
      if (token == null ||
          token.isEmpty ||
          SessionService.instance.currentUserId != owner) {
        throw StateError('AUTH_REQUIRED');
      }

      final requestData = <String, dynamic>{};
      if (name != null) requestData['name'] = name;
      if (gender != null) requestData['gender'] = gender;
      if (birthdate != null) requestData['birth_date'] = birthdate;
      if (marketingConsent != null) {
        requestData['marketing_consent'] = marketingConsent;
      }
      if (newsletterSubscription != null) {
        requestData['newsletter_subscription'] = newsletterSubscription;
      }

      final response = await http
          .put(
            Uri.parse('$baseUrl/users/$userId/profile'),
            headers: {
              'Content-Type': 'application/json',
              // فقط إضافة Authorization إذا كان التوكن حقيقي
              if (token.isNotEmpty && token != 'placeholder_access_token')
                'Authorization': 'Bearer $token',
            },
            body: json.encode(requestData),
          )
          .timeout(const Duration(seconds: 20));
      if (SessionService.instance.currentUserId != owner) {
        throw StateError('ACCOUNT_CHANGED');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final saved = data['data'];
        if (saved is Map) {
          await SessionService.instance.updateUserData({
            if (saved['name'] != null) 'name': saved['name'],
            if (saved['marketing_consent'] is bool)
              'marketing_consent': saved['marketing_consent'],
            if (saved['notification_settings'] is Map)
              'notification_settings': saved['notification_settings'],
          });
        }
        return {
          'success': true,
          'message': 'تم تحديث المعلومات بنجاح',
          'data': data,
        };
      } else if (response.statusCode == 404) {
        return {
          'success': false,
          'message': 'المستخدم غير موجود، يرجى إعادة تسجيل الدخول',
        };
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        return {
          'success': false,
          'message': 'غير مخول للوصول، يرجى إعادة تسجيل الدخول',
        };
      } else {
        try {
          final errorData = json.decode(response.body);
          return {
            'success': false,
            'message': errorData['message'] ?? 'خطأ في تحديث المعلومات',
          };
        } catch (parseError) {
          return {
            'success': false,
            'message': 'خطأ في تحديث المعلومات (${response.statusCode})',
          };
        }
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  /// تحديث تفضيلات اللغة
  static Future<Map<String, dynamic>> updateLanguagePreference({
    required String userId,
    required String language,
  }) async {
    try {
      final owner = SessionService.instance.currentUserId;
      if (owner == null || owner != userId) {
        throw StateError('ACCOUNT_MISMATCH');
      }
      final token = await SessionService.instance.getToken();
      if (token == null ||
          token.isEmpty ||
          SessionService.instance.currentUserId != owner) {
        throw StateError('AUTH_REQUIRED');
      }

      final response = await http
          .put(
            Uri.parse('$baseUrl/users/$userId/language'),
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: json.encode({'language': language}),
          )
          .timeout(const Duration(seconds: 20));
      if (SessionService.instance.currentUserId != owner) {
        throw StateError('ACCOUNT_CHANGED');
      }

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
      final owner = SessionService.instance.currentUserId;
      if (owner == null || owner != userId) {
        throw StateError('ACCOUNT_MISMATCH');
      }
      final token = await SessionService.instance.getToken();
      if (token == null ||
          token.isEmpty ||
          SessionService.instance.currentUserId != owner) {
        throw StateError('AUTH_REQUIRED');
      }

      final response = await http
          .put(
            Uri.parse('$baseUrl/users/$userId/password'),
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty && token != 'placeholder_access_token')
                'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (SessionService.instance.currentUserId != owner) {
        throw StateError('ACCOUNT_CHANGED');
      }

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
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }
}
