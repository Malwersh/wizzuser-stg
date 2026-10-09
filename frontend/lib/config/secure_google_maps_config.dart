import 'dart:io' show Platform;

/// خدمة إدارة مفاتيح Google Maps API بشكل آمن
/// يدعم بيئات مختلفة (تطوير، اختبار، إنتاج)
class SecureGoogleMapsConfig {
  
  // === إعدادات البيئات المختلفة ===
  
  static const Map<String, Map<String, String>> _apiKeys = {
    'development': {
      'android': 'AIzaSyAuIntz4hC71DzPL5TP6iC43288PCgwWFs', // من google_places_config
      'ios': 'AIzaSyDNrm2dXXHg3KzOepDnAnmiJTTFsmjM7Bc',     // من google_places_config
    },
    'staging': {
      'android': 'AIzaSyAuIntz4hC71DzPL5TP6iC43288PCgwWFs', // نفس المفاتيح مؤقتاً
      'ios': 'AIzaSyDNrm2dXXHg3KzOepDnAnmiJTTFsmjM7Bc',
    },
    'production': {
      'android': 'AIzaSyAuIntz4hC71DzPL5TP6iC43288PCgwWFs', // نفس المفاتيح مؤقتاً
      'ios': 'AIzaSyDNrm2dXXHg3KzOepDnAnmiJTTFsmjM7Bc',
    },
  };

  // === إعدادات الخريطة ===
  
  static const Map<String, double> _mapSettings = {
    'defaultZoom': 12.0,
    'detailZoom': 15.0,
    'maxZoom': 20.0,
    'minZoom': 5.0,
    'userLocationZoom': 16.0,
    'restaurantZoom': 14.0,
  };

  // === الإحداثيات الافتراضية ===
  
  static const Map<String, double> _defaultCoordinates = {
    'latitude': 33.3128,   // بغداد
    'longitude': 44.3615,  // بغداد
  };

  // === إعدادات الموقع ===
  
  static const Map<String, dynamic> _locationSettings = {
    'timeoutSeconds': 10,
    'accuracyMeters': 100.0,
    'distanceFilterMeters': 50.0,
    'enableBackgroundLocation': false,
  };

  // === Getters للبيئة الحالية ===

  /// تحديد البيئة الحالية
  static String get currentEnvironment {
    const environment = String.fromEnvironment('ENVIRONMENT', defaultValue: 'development');
    return environment.toLowerCase();
  }

  /// هل التطبيق في بيئة الإنتاج؟
  static bool get isProduction {
    return currentEnvironment == 'production';
  }

  /// هل التطبيق في بيئة التطوير؟
  static bool get isDevelopment {
    return currentEnvironment == 'development';
  }

  /// هل التطبيق في بيئة الاختبار؟
  static bool get isStaging {
    return currentEnvironment == 'staging';
  }

  // === Getters لمفاتيح API ===

  /// الحصول على مفتاح API المناسب للمنصة والبيئة الحالية
  static String get apiKey {
    final environment = currentEnvironment;
    final platform = Platform.isAndroid ? 'android' : 'ios';
    
    final key = _apiKeys[environment]?[platform] ?? _apiKeys['development']?[platform] ?? '';
    
    if (!isValidApiKey(key)) {
      throw Exception('مفتاح Google Maps API غير صحيح للبيئة: $environment والمنصة: $platform');
    }
    
    return key;
  }

  /// مفتاح Android للبيئة الحالية
  static String get androidApiKey {
    final environment = currentEnvironment;
    return _apiKeys[environment]?['android'] ?? _apiKeys['development']?['android'] ?? '';
  }

  /// مفتاح iOS للبيئة الحالية
  static String get iosApiKey {
    final environment = currentEnvironment;
    return _apiKeys[environment]?['ios'] ?? _apiKeys['development']?['ios'] ?? '';
  }

  // === Getters لإعدادات الخريطة ===

  static double get defaultZoom => _mapSettings['defaultZoom']!;
  static double get detailZoom => _mapSettings['detailZoom']!;
  static double get maxZoom => _mapSettings['maxZoom']!;
  static double get minZoom => _mapSettings['minZoom']!;
  static double get userLocationZoom => _mapSettings['userLocationZoom']!;
  static double get restaurantZoom => _mapSettings['restaurantZoom']!;

  // === Getters للإحداثيات ===

  static double get defaultLatitude => _defaultCoordinates['latitude']!;
  static double get defaultLongitude => _defaultCoordinates['longitude']!;

  // === Getters لإعدادات الموقع ===

  static int get locationTimeoutSeconds => _locationSettings['timeoutSeconds'];
  static double get locationAccuracyMeters => _locationSettings['accuracyMeters'];
  static double get distanceFilterMeters => _locationSettings['distanceFilterMeters'];
  static bool get enableBackgroundLocation => _locationSettings['enableBackgroundLocation'];

  // === دوال التحقق ===

  /// التحقق من صحة مفتاح API
  static bool isValidApiKey(String key) {
    return key.isNotEmpty && 
           key != 'YOUR_API_KEY_HERE' && 
           key != 'ضع_مفتاحك_هنا' &&
           key != 'YOUR_STAGING_ANDROID_KEY' &&
           key != 'YOUR_STAGING_IOS_KEY' &&
           key != 'YOUR_PRODUCTION_ANDROID_KEY' &&
           key != 'YOUR_PRODUCTION_IOS_KEY' &&
           key.startsWith('AIza');
  }

  /// التحقق من جاهزية الإعداد
  static bool get isConfigurationReady {
    try {
      final key = apiKey;
      return isValidApiKey(key);
    } catch (e) {
      return false;
    }
  }

  // === دوال المساعدة ===

  /// طباعة معلومات الإعداد الحالي (للتطوير فقط)
  static void logConfigurationStatus() {
    if (!isDevelopment) return; // فقط في بيئة التطوير
    
    // Google Maps Configuration Status logging removed for production
    // Environment: $currentEnvironment
    // Platform: ${Platform.operatingSystem}
    // API Key Valid: ${isValidApiKey(apiKey)}
    // Configuration Ready: $isConfigurationReady
    // Map Settings and Default Location details available in development mode only
  }

  /// الحصول على خريطة إعدادات كاملة
  static Map<String, dynamic> get fullConfiguration => {
    'environment': currentEnvironment,
    'platform': Platform.operatingSystem,
    'apiKey': isValidApiKey(apiKey) ? '${apiKey.substring(0, 10)}...' : 'Invalid',
    'isReady': isConfigurationReady,
    'mapSettings': _mapSettings,
    'defaultCoordinates': _defaultCoordinates,
    'locationSettings': _locationSettings,
  };

  // === دوال التحقق من الأخطاء ===

  /// التحقق من الأخطاء الشائعة وإرجاع قائمة بها
  static List<String> validateConfiguration() {
    final errors = <String>[];

    // التحقق من مفاتيح API
    if (!isValidApiKey(androidApiKey)) {
      errors.add('مفتاح Android API غير صحيح للبيئة: $currentEnvironment');
    }

    if (!isValidApiKey(iosApiKey)) {
      errors.add('مفتاح iOS API غير صحيح للبيئة: $currentEnvironment');
    }

    // التحقق من الإحداثيات
    if (defaultLatitude < -90 || defaultLatitude > 90) {
      errors.add('خط العرض الافتراضي غير صحيح: $defaultLatitude');
    }

    if (defaultLongitude < -180 || defaultLongitude > 180) {
      errors.add('خط الطول الافتراضي غير صحيح: $defaultLongitude');
    }

    // التحقق من إعدادات التكبير
    if (minZoom >= maxZoom) {
      errors.add('قيم التكبير غير منطقية: min=$minZoom, max=$maxZoom');
    }

    if (defaultZoom < minZoom || defaultZoom > maxZoom) {
      errors.add('التكبير الافتراضي خارج النطاق المسموح: $defaultZoom');
    }

    return errors;
  }

  /// طباعة تقرير شامل عن حالة الإعداد
  static void printConfigurationReport() {
    if (!isDevelopment) return;

    print('\n' + '=' * 50);
    print('📊 GOOGLE MAPS CONFIGURATION REPORT');
    print('=' * 50);

    logConfigurationStatus();

    final errors = validateConfiguration();
    if (errors.isNotEmpty) {
      print('\n❌ Configuration Errors:');
      for (int i = 0; i < errors.length; i++) {
        print('   ${i + 1}. ${errors[i]}');
      }
    } else {
      print('\n✅ Configuration is valid!');
    }

    print('\n💡 Next Steps:');
    if (errors.isNotEmpty) {
      print('   1. Fix the errors listed above');
      print('   2. Update API keys in Google Cloud Console');
      print('   3. Test the configuration again');
    } else {
      print('   1. Test maps functionality in the app');
      print('   2. Verify location permissions');
      print('   3. Check internet connectivity');
    }

    print('\n📚 For more help, see: GOOGLE_MAPS_SETUP_COMPLETE.md');
    print('=' * 50 + '\n');
  }
}
