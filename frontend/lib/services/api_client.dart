import 'package:dio/dio.dart';

/// عميل API مع إدارة تلقائية للـ authentication
class ApiClient {
  static ApiClient? _instance;

  // Singleton pattern
  static ApiClient get instance {
    _instance ??= ApiClient._internal();
    return _instance!;
  }

  ApiClient._internal();

  // Placeholder Dio getter (غير مستخدم فعلياً)
  Dio get dio => throw UnimplementedError('API client is placeholder only.');

  // === طرق API المخصصة (كلها Placeholder) ===

  Future<Response> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    // Placeholder: نجاح وهمي
    return Response(requestOptions: RequestOptions(path: '/auth/register'), statusCode: 200, data: {'success': true});
  }

  Future<Response> confirmSignup({
    required String username,
    required String code,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/auth/confirm'), statusCode: 200, data: {'success': true});
  }

  Future<Response> login({
    required String username,
    required String password,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/auth/login'), statusCode: 200, data: {'token': 'mock_token'});
  }

  Future<Response> resendConfirmationCode({
    required String username,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/auth/resend-code'), statusCode: 200, data: {'success': true});
  }

  Future<Response> forgotPassword({
    required String username,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/auth/forgot-password'), statusCode: 200, data: {'success': true});
  }

  Future<Response> confirmForgotPassword({
    required String username,
    required String code,
    required String newPassword,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/auth/confirm-forgot-password'), statusCode: 200, data: {'success': true});
  }

  Future<Response> getUserProfile() async {
    return Response(requestOptions: RequestOptions(path: '/user/profile'), statusCode: 200, data: {'name': 'Mock User', 'email': 'mock@example.com'});
  }

  Future<Response> updateUserProfile({
    required Map<String, dynamic> userData,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/user/profile'), statusCode: 200, data: {'success': true});
  }

  Future<Response> getRestaurants({
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/restaurants'), statusCode: 200, data: [
      {'id': '1', 'name': 'مطعم تجريبي', 'category': 'Fast Food'},
      {'id': '2', 'name': 'مطعم آخر', 'category': 'Desserts'},
    ]);
  }

  Future<Response> getRestaurantDetails(String restaurantId) async {
    return Response(requestOptions: RequestOptions(path: '/restaurants/$restaurantId'), statusCode: 200, data: {'id': restaurantId, 'name': 'مطعم تجريبي', 'menu': []});
  }

  Future<Response> createOrder({
    required Map<String, dynamic> orderData,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/orders'), statusCode: 200, data: {'order_id': 'mock_order_id'});
  }

  Future<Response> getOrderHistory({
    int page = 1,
    int limit = 10,
  }) async {
    return Response(requestOptions: RequestOptions(path: '/orders/history'), statusCode: 200, data: []);
  }

  Future<Response> trackOrder(String orderId) async {
    return Response(requestOptions: RequestOptions(path: '/orders/$orderId/track'), statusCode: 200, data: {'status': 'pending'});
  }

  Future<Response> healthCheck() async {
    return Response(requestOptions: RequestOptions(path: '/health'), statusCode: 200, data: {'status': 'ok'});
  }
}

