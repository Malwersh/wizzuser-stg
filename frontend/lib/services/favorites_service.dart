import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import "session_service.dart";
import '../config/api_config.dart';

/// خدمة إدارة المفضلة - تتصل بـ API المفضلة المنشور في AWS
class FavoritesService {
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  static Future<String?> _getAuthToken() async {
    try {
      final accessToken = SessionService.instance.accessToken;
      if (accessToken != null &&
          accessToken.isNotEmpty &&
          accessToken != 'placeholder_access_token') {
        return accessToken;
      }
    } catch (_) {
      // Ignore and fall back to idToken
    }

    try {
      final idToken = await SessionService.instance.idToken;
      if (idToken != null && idToken.isNotEmpty && idToken != 'temp_token') {
        return idToken;
      }
    } catch (_) {
      // Ignore
    }

    return null;
  }

  /// إضافة مطعم للمفضلة
  static Future<Map<String, dynamic>> addToFavorites({
    required String businessId,
    required String businessName,
    required String businessImage,
    required String businessCategory,
  }) async {
    try {
      developer.log(
        '➕ إضافة مطعم للمفضلة: $businessName',
        name: 'FAVORITES_SERVICE',
      );

      // الحصول على معلومات المستخدم
      final userData = await SessionService.instance.currentUser;
      final token = await _getAuthToken();

      if (userData == null || token == null) {
        return {'success': false, 'error': 'يجب تسجيل الدخول أولاً'};
      }

      final userId =
          userData['userId'] ?? userData['user_id'] ?? userData['email'];
      if (userId == null) {
        return {'success': false, 'error': 'معرف المستخدم غير موجود'};
      }

      final url = Uri.parse('$_baseUrl/users/$userId/favorites');

      final requestBody = {
        'businessId': businessId,
        'businessName': businessName,
        'businessImage': businessImage,
        'businessCategory': businessCategory,
        'favoriteType': 'restaurant',
      };

      developer.log('📡 طلب إضافة مفضلة: $url', name: 'FAVORITES_SERVICE');
      developer.log('📝 بيانات الطلب: $requestBody', name: 'FAVORITES_SERVICE');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 15));

      developer.log(
        '📊 إضافة مفضلة - الحالة: ${response.statusCode}',
        name: 'FAVORITES_SERVICE',
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        developer.log(
          '✅ تم إضافة المطعم للمفضلة بنجاح',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': true,
          'message': responseData['message'] ?? 'تم إضافة المطعم للمفضلة',
          'data': responseData['data'],
        };
      } else {
        final errorData = jsonDecode(response.body);
        developer.log(
          '❌ فشل في إضافة المفضلة: ${errorData['message']}',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': false,
          'error': errorData['message'] ?? 'فشل في إضافة المفضلة',
        };
      }
    } catch (e) {
      developer.log('❌ خطأ في إضافة المفضلة: $e', name: 'FAVORITES_SERVICE');
      return {'success': false, 'error': 'خطأ في الاتصال: $e'};
    }
  }

  /// إزالة مطعم من المفضلة
  static Future<Map<String, dynamic>> removeFromFavorites({
    required String favoriteId,
  }) async {
    try {
      developer.log(
        '➖ إزالة مطعم من المفضلة: $favoriteId',
        name: 'FAVORITES_SERVICE',
      );

      // الحصول على معلومات المستخدم
      final userData = await SessionService.instance.currentUser;
      final token = await _getAuthToken();

      if (userData == null || token == null) {
        return {'success': false, 'error': 'يجب تسجيل الدخول أولاً'};
      }

      final userId =
          userData['userId'] ?? userData['user_id'] ?? userData['email'];
      if (userId == null) {
        return {'success': false, 'error': 'معرف المستخدم غير موجود'};
      }

      final url = Uri.parse('$_baseUrl/users/$userId/favorites/$favoriteId');

      developer.log('📡 طلب إزالة مفضلة: $url', name: 'FAVORITES_SERVICE');

      final response = await http
          .delete(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      developer.log(
        '📊 إزالة مفضلة - الحالة: ${response.statusCode}',
        name: 'FAVORITES_SERVICE',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        developer.log(
          '✅ تم إزالة المطعم من المفضلة بنجاح',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': true,
          'message': responseData['message'] ?? 'تم إزالة المطعم من المفضلة',
        };
      } else {
        final errorData = jsonDecode(response.body);
        developer.log(
          '❌ فشل في إزالة المفضلة: ${errorData['message']}',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': false,
          'error': errorData['message'] ?? 'فشل في إزالة المفضلة',
        };
      }
    } catch (e) {
      developer.log('❌ خطأ في إزالة المفضلة: $e', name: 'FAVORITES_SERVICE');
      return {'success': false, 'error': 'خطأ في الاتصال: $e'};
    }
  }

  /// جلب قائمة المفضلة للمستخدم
  static Future<Map<String, dynamic>> getUserFavorites() async {
    try {
      developer.log('📋 جلب قائمة المفضلة للمستخدم', name: 'FAVORITES_SERVICE');

      // الحصول على معلومات المستخدم
      final userData = await SessionService.instance.currentUser;
      final token = await _getAuthToken();

      if (userData == null || token == null) {
        return {'success': false, 'error': 'يجب تسجيل الدخول أولاً'};
      }

      final userId =
          userData['userId'] ?? userData['user_id'] ?? userData['email'];
      if (userId == null) {
        return {'success': false, 'error': 'معرف المستخدم غير موجود'};
      }

      final url = Uri.parse(
        '$_baseUrl/users/$userId/favorites?type=restaurant',
      );

      developer.log('📡 طلب جلب المفضلة: $url', name: 'FAVORITES_SERVICE');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      developer.log(
        '📊 جلب المفضلة - الحالة: ${response.statusCode}',
        name: 'FAVORITES_SERVICE',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final favorites = responseData['data']['favorites'] ?? [];
        developer.log(
          '✅ تم جلب المفضلة بنجاح: ${favorites.length} مطعم',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': true,
          'data': {'favorites': favorites},
        };
      } else {
        final errorData = jsonDecode(response.body);
        developer.log(
          '❌ فشل في جلب المفضلة: ${errorData['message']}',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': false,
          'error': errorData['message'] ?? 'فشل في جلب المفضلة',
        };
      }
    } catch (e) {
      developer.log('❌ خطأ في جلب المفضلة: $e', name: 'FAVORITES_SERVICE');
      return {'success': false, 'error': 'خطأ في الاتصال: $e'};
    }
  }

  /// فحص ما إذا كان مطعم معين مفضل
  static Future<Map<String, dynamic>> checkFavoriteStatus({
    required String businessId,
  }) async {
    try {
      developer.log(
        '🔍 فحص حالة المفضلة للمطعم: $businessId',
        name: 'FAVORITES_SERVICE',
      );

      // الحصول على معلومات المستخدم
      final userData = await SessionService.instance.currentUser;
      final token = await _getAuthToken();

      if (userData == null || token == null) {
        return {'success': false, 'error': 'يجب تسجيل الدخول أولاً'};
      }

      final userId =
          userData['userId'] ?? userData['user_id'] ?? userData['email'];
      if (userId == null) {
        return {'success': false, 'error': 'معرف المستخدم غير موجود'};
      }

      final url = Uri.parse(
        '$_baseUrl/users/$userId/favorites/check/$businessId',
      );

      developer.log('📡 طلب فحص المفضلة: $url', name: 'FAVORITES_SERVICE');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      developer.log(
        '📊 فحص المفضلة - الحالة: ${response.statusCode}',
        name: 'FAVORITES_SERVICE',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final isFavorite = responseData['data']['is_favorite'] ?? false;
        final favoriteId = responseData['data']['favorite_id'];

        developer.log(
          '✅ حالة المفضلة: ${isFavorite ? 'مفضل' : 'غير مفضل'}',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': true,
          'data': {'is_favorite': isFavorite, 'favoriteId': favoriteId},
        };
      } else {
        final errorData = jsonDecode(response.body);
        developer.log(
          '❌ فشل في فحص المفضلة: ${errorData['message']}',
          name: 'FAVORITES_SERVICE',
        );
        return {
          'success': false,
          'error': errorData['message'] ?? 'فشل في فحص المفضلة',
        };
      }
    } catch (e) {
      developer.log('❌ خطأ في فحص المفضلة: $e', name: 'FAVORITES_SERVICE');
      return {'success': false, 'error': 'خطأ في الاتصال: $e'};
    }
  }

  /// تبديل حالة المفضلة (إضافة أو إزالة)
  static Future<Map<String, dynamic>> toggleFavorite({
    required String businessId,
    required String businessName,
    required String businessImage,
    required String businessCategory,
  }) async {
    try {
      developer.log(
        '🔄 تبديل حالة المفضلة للمطعم: $businessName',
        name: 'FAVORITES_SERVICE',
      );

      // أولاً فحص الحالة الحالية
      final statusResult = await checkFavoriteStatus(businessId: businessId);

      if (!statusResult['success']) {
        return statusResult;
      }

      final isFavorite = statusResult['isFavorite'] ?? false;
      final favoriteId = statusResult['favoriteId'];

      if (isFavorite && favoriteId != null) {
        // إزالة من المفضلة
        return await removeFromFavorites(favoriteId: favoriteId);
      } else {
        // إضافة للمفضلة
        return await addToFavorites(
          businessId: businessId,
          businessName: businessName,
          businessImage: businessImage,
          businessCategory: businessCategory,
        );
      }
    } catch (e) {
      developer.log('❌ خطأ في تبديل المفضلة: $e', name: 'FAVORITES_SERVICE');
      return {'success': false, 'error': 'خطأ في تبديل المفضلة: $e'};
    }
  }
}
