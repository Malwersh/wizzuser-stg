import 'dart:math';

/// حساب المسافة بين نقطتين جغرافيتين باستخدام صيغة Haversine
/// 
/// تُستخدم لحساب المسافة الحقيقية بين موقع المستخدم والمطعم
class DistanceCalculator {
  /// حساب المسافة بالكيلومترات بين نقطتين (latitude, longitude)
  /// 
  /// Parameters:
  /// - [lat1]: خط العرض للنقطة الأولى (المستخدم)
  /// - [lon1]: خط الطول للنقطة الأولى (المستخدم)
  /// - [lat2]: خط العرض للنقطة الثانية (المطعم)
  /// - [lon2]: خط الطول للنقطة الثانية (المطعم)
  /// 
  /// Returns: المسافة بالكيلومترات
  static double calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    // نصف قطر الأرض بالكيلومترات
    const double earthRadiusKm = 6371.0;
    
    // تحويل الدرجات إلى راديان
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    
    final double lat1Rad = _degreesToRadians(lat1);
    final double lat2Rad = _degreesToRadians(lat2);
    
    // صيغة Haversine
    final double a = (sin(dLat / 2) * sin(dLat / 2)) +
        (sin(dLon / 2) * sin(dLon / 2) * cos(lat1Rad) * cos(lat2Rad));
    
    final double c = 2 * asin(sqrt(a));
    
    // المسافة بالكيلومترات
    return earthRadiusKm * c;
  }
  
  /// تحويل الدرجات إلى راديان
  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }
  
  /// تنسيق المسافة للعرض (مع اختيار الوحدة المناسبة)
  /// 
  /// إذا كانت المسافة أقل من 1 كم، يتم عرضها بالمتر
  /// إذا كانت أكبر من أو تساوي 1 كم، يتم عرضها بالكيلومتر
  /// 
  /// Parameters:
  /// - [distanceInKm]: المسافة بالكيلومترات
  /// 
  /// Returns: النص المنسق للعرض (مثل: "500 م" أو "2.5 كم")
  static String formatDistance(double distanceInKm) {
    if (distanceInKm < 1.0) {
      // عرض بالمتر للمسافات القصيرة
      final int meters = (distanceInKm * 1000).round();
      return '$meters م';
    } else {
      // عرض بالكيلومتر للمسافات الطويلة
      return '${distanceInKm.toStringAsFixed(1)} كم';
    }
  }
  
  /// حساب المسافة وتنسيقها للعرض مباشرة
  /// 
  /// دالة مساعدة تجمع بين حساب المسافة وتنسيقها
  static String calculateAndFormatDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    final distance = calculateDistance(
      lat1: lat1,
      lon1: lon1,
      lat2: lat2,
      lon2: lon2,
    );
    
    return formatDistance(distance);
  }
}
