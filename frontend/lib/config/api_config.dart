// lib/config/api_config.dart
/// New Backend Configuration - Post Migration to Account 031857856164
class ApiConfig {
  // 🔄 NEW BACKEND URLs - تم التحديث للنظام الجديد
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    // IMPORTANT: no trailing slash; endpoints are defined with leading '/'
    defaultValue: 'https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging',
  );
  static const String webSocketUrl =
    String.fromEnvironment('WEBSOCKET_URL', defaultValue: 'wss://igcrhwc84c.execute-api.us-east-1.amazonaws.com/staging');

  // 🔔 CentralPlatform Notifications API (shared push service)
  static const String centralPushApiBaseUrl = String.fromEnvironment(
    'CENTRAL_PUSH_API_BASE_URL',
    // IMPORTANT: no trailing slash
    defaultValue: 'https://x066k4dftk.execute-api.us-east-1.amazonaws.com/staging',
  );
  
  // 🔄 NEW Cognito Configuration - Updated to match current backend stack
  static const String cognitoUserPoolId =
    String.fromEnvironment('COGNITO_USER_POOL_ID', defaultValue: 'us-east-1_TpyyrVkEE');
  static const String cognitoClientId =
    String.fromEnvironment('APP_CLIENT_ID', defaultValue: '4a9e8o3em311eq2rgckp0pd2s9');
  static const String cognitoRegion =
    String.fromEnvironment('COGNITO_REGION', defaultValue: 'us-east-1');
  
  // 📡 API Endpoints
  static const String healthEndpoint = '/health';
  static const String authEndpoint = '/auth';
  static const String usersEndpoint = '/users';
  static const String businessesEndpoint = '/businesses';
  static const String ordersEndpoint = '/orders';
  static const String addressesEndpoint = '/addresses';
  static const String favoritesEndpoint = '/favorites';
  
  // 🆕 Smart Delivery System Endpoints
  static const String regionLookupEndpoint = '/api/regions/find-by-coordinates';
  static const String getBusinessesByRegionEndpoint = '/api/businesses/by-region';
  static const String getNearbyBusinessesEndpoint = '/api/businesses/nearby';
  static const String checkDeliveryAvailabilityEndpoint = '/api/check-delivery';
  
  // 🆕 Version Check Endpoints (Real-time Updates)
  static const String checkMenuVersionEndpoint = '/api/check-menu-version';
  static const String checkListingVersionEndpoint = '/api/check-listing-version';
  static const String batchCheckVersionsEndpoint = '/api/batch-check-versions';
  
  // 🔒 Security Headers
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  
  // 🌍 Environment Settings
  static const String environment =
      String.fromEnvironment('ENVIRONMENT', defaultValue: 'staging');
  static const bool isProduction = environment == 'prod' || environment == 'production';
  
  // ⏱️ Timeout Settings
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration connectionTimeout = Duration(seconds: 10);
  
  // 📱 App Configuration
  static const String appVersion = '1.0.0';
  static const String appName = 'Food App';
  
  // 🔄 Registration API Format Requirements
  static const String registrationTypeEmail = 'email';
  static const String registrationTypePhone = 'phone';
  
  // 🌐 Build complete URL for endpoint
  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String buildUrl(String endpoint) {
    if (baseUrl.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    final base = _normalizeBaseUrl(baseUrl);
    final ep = endpoint.trim();
    if (ep.isEmpty) return base;
    if (ep.startsWith('/')) return '$base$ep';
    return '$base/$ep';
  }
  
  static Map<String, String> getAuthHeaders(String? token) {
    final headers = Map<String, String>.from(defaultHeaders);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
