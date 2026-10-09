/// Google Places API Configuration
/// 
/// Instructions:
/// 1. Get your API keys from: https://console.cloud.google.com
/// 2. Enable: Places API, Geocoding API, Maps SDK
/// 3. Replace the placeholder keys below with your actual keys

import '../config.dart' as app_config;

class GooglePlacesConfig {
  // 🔐 Android Key (للـ Maps SDK فقط)
  static const String androidKey = 'AIzaSyAuIntz4hC71DzPL5TP6iC43288PCgwWFs';
  
  // 🔐 iOS Key (للـ Maps SDK فقط)
  static const String iosKey = 'AIzaSyDNrm2dXXHg3KzOepDnAnmiJTTFsmjM7Bc';
  
  // 🔐 HTTP Key (للـ Places Autocomplete API - بدون قيود) ⭐
  static const String httpKey = 'AIzaSyDrvzgil3g2SwE8zl_44IGM35n7khAyoVI';
  
  /// Get the appropriate API key based on platform
  static String get apiKey {
    // For HTTP requests (Places Autocomplete), always use httpKey
    return httpKey;
  }
  
  /// Region Resolver API
  ///
  /// Primary: `--dart-define=REGION_RESOLVER_URL=...`
  /// Fallback: `API_URL` + `/api/region-lookup`
  static String get regionResolverUrl {
    const fromEnv = String.fromEnvironment('REGION_RESOLVER_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;

    var base = app_config.ApiConfig.baseUrl;
    if (base.isEmpty) return '';

    // Normalize base to avoid double slashes like /staging//api/...
    base = base.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    return '$base${app_config.ApiConfig.regionLookupEndpoint}';
  }
}
