import 'dart:io' show Platform;

class GoogleMapsConfig {
  // مفاتيح API للبيئات المختلفة
  static const String _developmentAndroidKey = 'AIzaSyBVWaKrjvy3MaE7SQ8Q9dDvKMY0Fzx6BUI';
  static const String _developmentIOSKey = 'AIzaSyBVWaKrjvy3MaE7SQ8Q9dDvKMY0Fzx6BUI';
  
  // مفاتيح الإنتاج (يجب الحصول عليها من Google Cloud Console)
  static const String _productionAndroidKey = 'YOUR_PRODUCTION_ANDROID_KEY';
  static const String _productionIOSKey = 'YOUR_PRODUCTION_IOS_KEY';

  // تحديد البيئة الحالية
  static bool get isProduction {
    return const bool.fromEnvironment('dart.vm.product', defaultValue: false);
  }

  // الحصول على المفتاح المناسب للنظام والبيئة
  static String get apiKey {
    if (Platform.isAndroid) {
      return isProduction ? _productionAndroidKey : _developmentAndroidKey;
    } else if (Platform.isIOS) {
      return isProduction ? _productionIOSKey : _developmentIOSKey;
    } else {
      return _developmentAndroidKey; // مفتاح افتراضي للويب أو منصات أخرى
    }
  }

  // إعدادات الخريطة الافتراضية
  static const double defaultZoom = 12.0;
  static const double detailZoom = 15.0;
  static const double maxZoom = 20.0;
  static const double minZoom = 5.0;

  // الموقع الافتراضي (بغداد)
  static const double defaultLatitude = 33.3128;
  static const double defaultLongitude = 44.3615;
  
  // إعدادات الموقع
  static const int locationTimeoutSeconds = 10;
  static const double locationAccuracyMeters = 100.0;
  
  // Colors for markers
  static const String restaurantMarkerColor = 'orange';
  static const String userLocationMarkerColor = 'blue';
  static const String selectedMarkerColor = 'red';

  // Validation
  static bool isValidApiKey(String key) {
    return key.isNotEmpty && 
           key != 'YOUR_API_KEY_HERE' && 
           key != 'ضع_مفتاحك_هنا' &&
           key.startsWith('AIza');
  }

  static void logConfigStatus() {
    // Google Maps Configuration logging removed for production
    // Platform: ${Platform.operatingSystem}
    // Environment: ${isProduction ? "Production" : "Development"}
    // API Key Valid: ${isValidApiKey(apiKey)}
    // API Key: ${apiKey.substring(0, 10)}...
  }
}
