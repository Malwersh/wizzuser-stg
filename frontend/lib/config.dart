/// Configuration file for API endpoints and app settings
/// Updated for NEW Backend Infrastructure - Account 031857856164
class ApiConfig {
  // 🔄 NEW Base URL - Updated for new AWS Account
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    // IMPORTANT: no trailing slash; many endpoints start with '/'
    defaultValue: 'https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging',
  );
  
  // 🔄 NEW Cognito Configuration - Updated to match current backend
  static const String cognitoUserPoolId =
    String.fromEnvironment('COGNITO_USER_POOL_ID', defaultValue: 'us-east-1_TpyyrVkEE');
  static const String cognitoClientId =
    String.fromEnvironment('APP_CLIENT_ID', defaultValue: '4a9e8o3em311eq2rgckp0pd2s9');
  static const String cognitoRegion =
    String.fromEnvironment('COGNITO_REGION', defaultValue: 'us-east-1');
  
  // 🔄 NEW WebSocket URL
  static const String webSocketUrl =
    String.fromEnvironment('WEBSOCKET_URL', defaultValue: 'wss://igcrhwc84c.execute-api.us-east-1.amazonaws.com/staging');
  
  // Authentication endpoints
  static const String registerEndpoint = '/auth/register';
  static const String loginEndpoint = '/auth/login';
  static const String confirmSignUpEndpoint = '/auth/verify-email';
  static const String verifyPhoneEndpoint = '/auth/verify-phone';
  static const String resendCodeEndpoint = '/auth/resend-code';
  static const String refreshTokenEndpoint = '/auth/refresh';
  static const String logoutEndpoint = '/auth/logout';
  static const String forgotPasswordEndpoint = '/auth/forgot-password';
  static const String confirmForgotPasswordEndpoint = '/auth/confirm-forgot-password';
  
  // User endpoints
  static const String userProfileEndpoint = '/user/profile';
  static const String updateProfileEndpoint = '/user/update-profile';
  
  // Food and order endpoints
  static const String menuEndpoint = '/menu';
  static const String orderEndpoint = '/orders';
  static const String cartEndpoint = '/cart';
  
  // 🆕 Smart Delivery Address System - Region & Location APIs
  static const String regionLookupEndpoint = '/api/regions/find-by-coordinates';
  static const String getBusinessesByRegionEndpoint = '/api/businesses/by-region';
  static const String getNearbyBusinessesEndpoint = '/api/businesses/nearby';
  static const String businessesByRegionEndpoint = '/api/businesses';
  static const String nearbyBusinessesEndpoint = '/api/businesses/nearby';
  static const String checkDeliveryEndpoint = '/api/businesses'; // {businessId}/serves-address
  static const String checkDeliveryAvailabilityEndpoint = '/api/check-delivery';
  
  // 🆕 Version Check Endpoints (Real-time Updates)
  static const String checkMenuVersionEndpoint = '/api/check-menu-version';
  static const String checkListingVersionEndpoint = '/api/check-listing-version';
  static const String batchCheckVersionsEndpoint = '/api/batch-check-versions';
  
  // Other settings
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration cacheTimeout = Duration(minutes: 5);
  
  // Storage keys for SharedPreferences
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';
  static const String cartDataKey = 'cart_data';
  static const String sessionExpiryKey = 'session_expiry';
  
  // App configuration
  static const String appName = 'Food App';
  static const String appVersion = '1.0.0';
  
  // Debugging
  static const bool enableApiLogging = true;
  static const bool enableDebugMode = true;
}
