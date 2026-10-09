// Real OptimizedApiService - Now Connected to Backend
// This service connects to the actual backend API

import 'dart:async';
import 'real_api_client.dart';

class OptimizedApiService {
  static final OptimizedApiService _instance = OptimizedApiService._internal();
  factory OptimizedApiService() => _instance;
  OptimizedApiService._internal();

  final RealApiClient _apiClient = RealApiClient();
  
  // Cache for optimization
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Duration _cacheExpiry = const Duration(minutes: 5);

  // Check if cache is valid
  bool _isCacheValid(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheExpiry;
  }

  // Get cached data or fetch new
  Future<T> _getCachedOrFetch<T>(String key, Future<T> Function() fetchFunction) async {
    if (_isCacheValid(key) && _cache.containsKey(key)) {
      return _cache[key] as T;
    }
    
    final result = await fetchFunction();
    _cache[key] = result;
    _cacheTimestamps[key] = DateTime.now();
    return result;
  }

  // Restaurant APIs
  Future<Map<String, dynamic>> getRestaurants({
    int page = 1,
    int limit = 20,
    String? category,
    String? search,
    String? searchQuery,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? filters,
  }) async {
    // Build query parameters
    final queryParams = <String, String>{
      'page': (page - 1).toString(), // Convert to 0-based pagination for API
      'limit': limit.toString(),
    };
    
    if (category != null) queryParams['category'] = category;
    if (search != null || searchQuery != null) {
      queryParams['search'] = search ?? searchQuery!;
    }
    
    // Convert filters to query parameters
    if (filters != null) {
      filters.forEach((key, value) {
        if (value != null) {
          queryParams[key] = value.toString();
        }
      });
    }
    
    // Build endpoint with query parameters
    final endpoint = '/businesses?${queryParams.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&')}';
    
    final cacheKey = 'restaurants_${page}_${limit}_${category}_${search ?? searchQuery}';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get(endpoint));
  }

  Future<Map<String, dynamic>> getRestaurantDetails(String restaurantId) async {
    final cacheKey = 'restaurant_$restaurantId';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/restaurants/$restaurantId'));
  }

  Future<Map<String, dynamic>> getRestaurantMenu(String restaurantId) async {
    final cacheKey = 'menu_$restaurantId';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/restaurants/$restaurantId/menu'));
  }

  // Dish APIs
  Future<Map<String, dynamic>> getDishes({
    String? restaurantId,
    String? storeId,
    String? category,
    String? search,
    int page = 1,
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    final cacheKey = 'dishes_${restaurantId ?? storeId}_${category}_${page}_$limit';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/dishes'));
  }

  Future<Map<String, dynamic>> getDishDetails(String dishId) async {
    final cacheKey = 'dish_$dishId';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/dishes/$dishId'));
  }

  Future<Map<String, dynamic>> searchDishes(String query, {int page = 1, int limit = 20}) async {
    return _apiClient.get('/dishes/search?q=$query&page=$page&limit=$limit');
  }

  // Order APIs
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    return _apiClient.post('/orders', body: orderData);
  }

  Future<Map<String, dynamic>> getOrders({int page = 1, int limit = 20}) async {
    return _apiClient.get('/orders');
  }

  Future<Map<String, dynamic>> getOrderDetails(String orderId) async {
    return _apiClient.get('/orders/$orderId');
  }

  Future<Map<String, dynamic>> updateOrderStatus(String orderId, String status) async {
    return _apiClient.put('/orders/$orderId/status', body: {'status': status});
  }

  Future<Map<String, dynamic>> cancelOrder(String orderId) async {
    return _apiClient.delete('/orders/$orderId');
  }

  // User Profile APIs
  Future<Map<String, dynamic>> getUserProfile() async {
    final cacheKey = 'user_profile';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/user/profile'));
  }

  Future<Map<String, dynamic>> updateUserProfile(Map<String, dynamic> profileData) async {
    _cache.remove('user_profile'); // Invalidate cache
    return _apiClient.put('/user/profile', body: profileData);
  }

  Future<Map<String, dynamic>> changePassword(String oldPassword, String newPassword) async {
    return _apiClient.post('/user/change-password', body: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  Future<Map<String, dynamic>> changeEmail(String newEmail) async {
    return _apiClient.post('/user/change-email', body: {'email': newEmail});
  }

  // Address APIs
  Future<Map<String, dynamic>> getAddresses() async {
    final cacheKey = 'user_addresses';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/user/addresses'));
  }

  Future<Map<String, dynamic>> addAddress(Map<String, dynamic> addressData) async {
    _cache.remove('user_addresses'); // Invalidate cache
    return _apiClient.post('/user/addresses', body: addressData);
  }

  Future<Map<String, dynamic>> updateAddress(String addressId, Map<String, dynamic> addressData) async {
    _cache.remove('user_addresses'); // Invalidate cache
    return _apiClient.put('/user/addresses/$addressId', body: addressData);
  }

  Future<Map<String, dynamic>> deleteAddress(String addressId) async {
    _cache.remove('user_addresses'); // Invalidate cache
    return _apiClient.delete('/user/addresses/$addressId');
  }

  // Payment APIs
  Future<Map<String, dynamic>> getPaymentMethods() async {
    final cacheKey = 'payment_methods';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/user/payment-methods'));
  }

  Future<Map<String, dynamic>> addPaymentMethod(Map<String, dynamic> paymentData) async {
    _cache.remove('payment_methods'); // Invalidate cache
    return _apiClient.post('/user/payment-methods', body: paymentData);
  }

  Future<Map<String, dynamic>> deletePaymentMethod(String paymentMethodId) async {
    _cache.remove('payment_methods'); // Invalidate cache
    return _apiClient.delete('/user/payment-methods/$paymentMethodId');
  }

  // Favorites APIs
  Future<Map<String, dynamic>> getFavorites() async {
    final cacheKey = 'user_favorites';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/user/favorites'));
  }

  Future<Map<String, dynamic>> addToFavorites(String restaurantId) async {
    _cache.remove('user_favorites'); // Invalidate cache
    return _apiClient.post('/user/favorites', body: {'restaurantId': restaurantId});
  }

  Future<Map<String, dynamic>> removeFromFavorites(String restaurantId) async {
    _cache.remove('user_favorites'); // Invalidate cache
    return _apiClient.delete('/user/favorites/$restaurantId');
  }

  // Reviews APIs
  Future<Map<String, dynamic>> getReviews(String restaurantId, {int page = 1, int limit = 20}) async {
    return _apiClient.get('/reviews/$restaurantId?page=$page&limit=$limit');
  }

  Future<Map<String, dynamic>> addReview(String restaurantId, Map<String, dynamic> reviewData) async {
    return _apiClient.post('/reviews/$restaurantId', body: reviewData);
  }

  // Categories APIs
  Future<Map<String, dynamic>> getCategories() async {
    final cacheKey = 'categories';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/categories'));
  }

  // Promotions APIs
  Future<Map<String, dynamic>> getPromotions() async {
    final cacheKey = 'promotions';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/promotions'));
  }

  Future<Map<String, dynamic>> applyPromoCode(String promoCode) async {
    return _apiClient.post('/promotions/apply', body: {'code': promoCode});
  }

  // Notification APIs
  Future<Map<String, dynamic>> getNotifications({int page = 1, int limit = 20}) async {
    return _apiClient.get('/notifications?page=$page&limit=$limit');
  }

  Future<Map<String, dynamic>> markNotificationAsRead(String notificationId) async {
    return _apiClient.put('/notifications/$notificationId/read');
  }

  Future<Map<String, dynamic>> updateNotificationSettings(Map<String, dynamic> settings) async {
    return _apiClient.put('/user/notification-settings', body: settings);
  }

  // Analytics placeholder
  Future<Map<String, dynamic>> trackEvent(String eventName, Map<String, dynamic> properties) async {
    return _apiClient.post('/analytics/track', body: {
      'event': eventName,
      'properties': properties,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Performance stats placeholder
  Future<Map<String, dynamic>> getPerformanceStats() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return {
      'success': true,
      'data': {
        'apiCalls': 150,
        'cacheHits': 89,
        'cacheMisses': 61,
        'averageResponseTime': 250,
        'errorRate': 0.02,
      }
    };
  }

  // Smart search placeholder
  Future<Map<String, dynamic>> smartSearch(String query, {Map<String, dynamic>? filters}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return {
      'success': true,
      'data': {
        'restaurants': [
          {
            'id': '1',
            'name': 'Search Result Restaurant',
            'rating': 4.5,
            'cuisine': 'Mixed',
          }
        ],
        'dishes': [
          {
            'id': '1',
            'name': 'Search Result Dish',
            'price': 12.99,
            'restaurant': 'Test Restaurant',
          }
        ],
        'suggestions': ['pizza', 'burger', 'sushi'],
      }
    };
  }

  // Cache management
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  void clearCacheForKey(String key) {
    _cache.remove(key);
    _cacheTimestamps.remove(key);
  }

  // Static methods for backward compatibility
  static Future<Map<String, dynamic>> getRestaurantsStatic({
    int page = 1,
    int limit = 20,
    String? category,
    String? search,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? filters,
  }) async {
    final instance = OptimizedApiService();
    return instance.getRestaurants(
      page: page,
      limit: limit,
      category: category,
      search: search,
      latitude: latitude,
      longitude: longitude,
      filters: filters,
    );
  }

  static Future<Map<String, dynamic>> getDishesStatic({
    int page = 1,
    int limit = 20,
    String? storeId,
    String? restaurantId,
    String? category,
    String? search,
    Map<String, dynamic>? filters,
  }) async {
    final instance = OptimizedApiService();
    return instance.getDishes(
      page: page,
      limit: limit,
      storeId: storeId,
      restaurantId: restaurantId,
      category: category,
      search: search,
      filters: filters,
    );
  }
}

// Extension for additional restaurant API methods
extension RestaurantApiExtensions on OptimizedApiService {
  Future<Map<String, dynamic>> getPopularRestaurants({int limit = 10}) async {
    final cacheKey = 'popular_restaurants_$limit';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/restaurants/popular?limit=$limit'));
  }

  Future<Map<String, dynamic>> getNearbyRestaurants(double latitude, double longitude, {double radius = 5.0}) async {
    return _apiClient.get('/restaurants/nearby?lat=$latitude&lng=$longitude&radius=$radius');
  }

  Future<Map<String, dynamic>> getRestaurantsByCategory(String category, {int page = 1, int limit = 20}) async {
    final cacheKey = 'restaurants_category_${category}_${page}_$limit';
    return _getCachedOrFetch(cacheKey, () => _apiClient.get('/restaurants/category/$category?page=$page&limit=$limit'));
  }
}
