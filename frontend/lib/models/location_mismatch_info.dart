import 'dart:math';

/// Model representing location mismatch information
/// نموذج معلومات عدم تطابق الموقع
class LocationMismatchInfo {
  /// Current GPS latitude
  /// دائرة العرض الحالية من GPS
  final double currentLatitude;

  /// Current GPS longitude
  /// خط الطول الحالي من GPS
  final double currentLongitude;

  /// Current location city name
  /// اسم المدينة للموقع الحالي
  final String currentCity;

  /// Current location region ID (if available)
  /// معرّف المنطقة للموقع الحالي
  final String? currentRegionId;

  /// Selected/active delivery address city
  /// اسم مدينة العنوان المختار
  final String selectedAddressCity;

  /// Selected address region ID
  /// معرّف منطقة العنوان المختار
  final String? selectedRegionId;

  /// Distance between current location and selected address (in kilometers)
  /// المسافة بين الموقع الحالي والعنوان المختار (بالكيلومتر)
  final double distance;

  /// Timestamp when mismatch was detected
  /// وقت اكتشاف عدم التطابق
  final DateTime detectedAt;

  LocationMismatchInfo({
    required this.currentLatitude,
    required this.currentLongitude,
    required this.currentCity,
    this.currentRegionId,
    required this.selectedAddressCity,
    this.selectedRegionId,
    required this.distance,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();

  /// Check if cities are different
  /// التحقق من اختلاف المدن
  bool get isDifferentCity {
    return currentCity.toLowerCase() != selectedAddressCity.toLowerCase();
  }

  /// Check if regions are different (if both available)
  /// التحقق من اختلاف المناطق
  bool get isDifferentRegion {
    if (currentRegionId == null || selectedRegionId == null) {
      return false;
    }
    return currentRegionId != selectedRegionId;
  }

  /// Check if distance exceeds threshold (default: 5 km)
  /// التحقق من تجاوز المسافة للحد المسموح
  bool exceedsDistanceThreshold([double thresholdKm = 5.0]) {
    return distance > thresholdKm;
  }

  /// Get severity level of mismatch
  /// الحصول على درجة خطورة عدم التطابق
  MismatchSeverity get severity {
    if (isDifferentCity) {
      return MismatchSeverity.critical;
    }
    if (distance > 10) {
      return MismatchSeverity.high;
    }
    if (distance > 5) {
      return MismatchSeverity.medium;
    }
    return MismatchSeverity.low;
  }

  /// Get user-friendly message about the mismatch
  /// الحصول على رسالة واضحة عن عدم التطابق
  String getMessage() {
    if (isDifferentCity) {
      return 'موقعك الحالي في $currentCity، لكن العنوان المختار في $selectedAddressCity';
    }
    if (distance > 10) {
      return 'أنت على بعد ${distance.toStringAsFixed(1)} كم من العنوان المختار';
    }
    if (distance > 5) {
      return 'موقعك الحالي بعيد قليلاً عن العنوان المختار (${distance.toStringAsFixed(1)} كم)';
    }
    return 'موقعك الحالي قريب من العنوان المختار';
  }

  /// Calculate distance between two geographic points using Haversine formula
  /// حساب المسافة بين نقطتين جغرافيتين باستخدام صيغة Haversine
  static double calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const earthRadiusKm = 6371.0; // Earth's radius in kilometers

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distance = earthRadiusKm * c;

    return distance;
  }

  /// Convert degrees to radians
  /// تحويل الدرجات إلى راديان
  static double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Convert to JSON
  /// تحويل إلى JSON
  Map<String, dynamic> toJson() {
    return {
      'currentLatitude': currentLatitude,
      'currentLongitude': currentLongitude,
      'currentCity': currentCity,
      'currentRegionId': currentRegionId,
      'selectedAddressCity': selectedAddressCity,
      'selectedRegionId': selectedRegionId,
      'distance': distance,
      'detectedAt': detectedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  /// إنشاء من JSON
  factory LocationMismatchInfo.fromJson(Map<String, dynamic> json) {
    return LocationMismatchInfo(
      currentLatitude: (json['currentLatitude'] as num).toDouble(),
      currentLongitude: (json['currentLongitude'] as num).toDouble(),
      currentCity: json['currentCity'] as String,
      currentRegionId: json['currentRegionId'] as String?,
      selectedAddressCity: json['selectedAddressCity'] as String,
      selectedRegionId: json['selectedRegionId'] as String?,
      distance: (json['distance'] as num).toDouble(),
      detectedAt: DateTime.parse(json['detectedAt'] as String),
    );
  }

  @override
  String toString() {
    return 'LocationMismatchInfo('
        'currentCity: $currentCity, '
        'selectedCity: $selectedAddressCity, '
        'distance: ${distance.toStringAsFixed(2)} km, '
        'severity: ${severity.name}'
        ')';
  }
}

/// Severity level of location mismatch
/// درجة خطورة عدم التطابق
enum MismatchSeverity {
  /// Low severity (< 5 km, same city)
  /// خطورة منخفضة
  low,

  /// Medium severity (5-10 km, same city)
  /// خطورة متوسطة
  medium,

  /// High severity (> 10 km, same city)
  /// خطورة عالية
  high,

  /// Critical severity (different cities)
  /// خطورة حرجة
  critical,
}
