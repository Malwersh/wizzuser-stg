// Note: Update this import path to match your project structure
// For now using dynamic type until proper import is resolved
// import 'package:foodapp_user/models/business_model.dart';

/// Model representing a response from restaurant fetching API
/// نموذج استجابة API جلب المطاعم
class RestaurantListResponse {
  /// List of businesses/restaurants
  /// قائمة المطاعم
  final List<dynamic> businesses;

  /// Current page number (0-based)
  /// رقم الصفحة الحالية
  final int page;

  /// Number of items in current page
  /// عدد العناصر في الصفحة الحالية
  final int count;

  /// Total number of businesses available
  /// العدد الكلي للمطاعم المتوفرة
  final int total;

  /// Whether there are more pages available
  /// هل يوجد صفحات إضافية
  final bool hasMore;

  /// Region ID for the fetched restaurants
  /// معرّف المنطقة للمطاعم المجلوبة
  final String? regionId;

  /// Region name in Arabic
  /// اسم المنطقة بالعربية
  final String? regionNameAr;

  /// Listing version from WhizzMerchants_RegionListings
  /// رقم إصدار القائمة (للتحديثات الفورية)
  final int? listingVersion;

  /// Timestamp when the data was fetched
  /// وقت جلب البيانات
  final DateTime fetchedAt;

  /// Whether restaurants are from neighbor regions
  /// هل المطاعم من مناطق مجاورة
  final bool includesNeighborRegions;

  RestaurantListResponse({
    required this.businesses,
    required this.page,
    required this.count,
    required this.total,
    required this.hasMore,
    this.regionId,
    this.regionNameAr,
    this.listingVersion,
    DateTime? fetchedAt,
    this.includesNeighborRegions = false,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  /// Check if response is empty (no restaurants)
  /// التحقق من كون القائمة فارغة
  bool get isEmpty => businesses.isEmpty;

  /// Check if response has data
  /// التحقق من وجود بيانات
  bool get isNotEmpty => businesses.isNotEmpty;

  /// Get number of businesses in response
  /// الحصول على عدد المطاعم
  int get length => businesses.length;

  /// Check if this is the first page
  /// التحقق من كون هذه الصفحة الأولى
  bool get isFirstPage => page == 0;

  /// Calculate next page number
  /// حساب رقم الصفحة التالية
  int get nextPage => page + 1;

  /// Get pagination info as string
  /// الحصول على معلومات الترقيم كنص
  String get paginationInfo {
    final start = (page * count) + 1;
    final end = start + count - 1;
    return 'عرض $start-$end من $total';
  }

  /// Convert to JSON
  /// تحويل إلى JSON
  Map<String, dynamic> toJson() {
    return {
      'businesses': businesses,
      'page': page,
      'count': count,
      'total': total,
      'hasMore': hasMore,
      'regionId': regionId,
      'regionNameAr': regionNameAr,
      'listingVersion': listingVersion,
      'fetchedAt': fetchedAt.toIso8601String(),
      'includesNeighborRegions': includesNeighborRegions,
    };
  }

  /// Create from JSON
  /// إنشاء من JSON
  factory RestaurantListResponse.fromJson(Map<String, dynamic> json) {
    return RestaurantListResponse(
      businesses: (json['businesses'] as List<dynamic>)
          .map((item) => item as Map<String, dynamic>)
          .toList(),
      page: json['page'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
      regionId: json['regionId'] as String?,
      regionNameAr: json['regionNameAr'] as String?,
      listingVersion: json['listingVersion'] as int?,
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.parse(json['fetchedAt'] as String)
          : DateTime.now(),
      includesNeighborRegions:
          json['includesNeighborRegions'] as bool? ?? false,
    );
  }

  /// Create from API response data
  /// إنشاء من بيانات استجابة API
  factory RestaurantListResponse.fromApiResponse(Map<String, dynamic> data) {
    // Keep raw maps - will be converted to BusinessModel in the service layer or UI
    // نحتفظ بالـ maps الخام - سيتم تحويلها إلى BusinessModel في طبقة الخدمة أو واجهة المستخدم
    
    print('🔍🔍🔍 RestaurantListResponse.fromApiResponse - البداية');
    print('📦 data.keys: ${data.keys.join(", ")}');
    print('📊 عدد المطاعم في data[businesses]: ${(data['businesses'] as List<dynamic>?)?.length ?? 0}');
    
    final businesses = (data['businesses'] as List<dynamic>?)
            ?.map((item) =>
                item as Map<String, dynamic>)
            .toList() ??
        [];
    
    print('✅ تم استخراج ${businesses.length} مطعم');
    for (var i = 0; i < businesses.length; i++) {
      final name = businesses[i]['businessName'] ?? businesses[i]['business_name'] ?? 'غير معروف';
      final id = businesses[i]['businessId'] ?? businesses[i]['business_id'] ?? 'لا يوجد';
      print('   [$i] $name (ID: $id)');
      // 🔍 تفاصيل إضافية للمطعم
      print('      - isActive: ${businesses[i]['isActive']}');
      print('      - regionId: ${businesses[i]['regionId']}');
      final photoUrl = businesses[i]['businessPhotoUrl'];
      if (photoUrl != null && photoUrl.toString().length > 60) {
        print('      - businessPhotoUrl: ${photoUrl.toString().substring(0, 60)}...');
      } else {
        print('      - businessPhotoUrl: ${photoUrl ?? 'N/A'}');
      }
    }

    final pagination = data['pagination'] as Map<String, dynamic>?;
    final region = data['region'] as Map<String, dynamic>?;

    return RestaurantListResponse(
      businesses: businesses,
      page: pagination?['page'] as int? ?? 0,
      count: businesses.length,
      total: pagination?['total'] as int? ?? 0,
      hasMore: pagination?['hasMore'] as bool? ?? false,
      regionId: region?['region_id'] as String?,
      regionNameAr: region?['region_name_ar'] as String?,
      listingVersion: region?['listingVersion'] as int?,
      includesNeighborRegions: data['includesNeighborRegions'] as bool? ?? false,
    );
  }

  /// Create an empty response
  /// إنشاء استجابة فارغة
  factory RestaurantListResponse.empty({String? regionId}) {
    return RestaurantListResponse(
      businesses: [],
      page: 0,
      count: 0,
      total: 0,
      hasMore: false,
      regionId: regionId,
    );
  }

  /// Merge with another response (for pagination)
  /// دمج مع استجابة أخرى (للترقيم)
  RestaurantListResponse mergeWith(RestaurantListResponse other) {
    return RestaurantListResponse(
      businesses: [...businesses, ...other.businesses],
      page: other.page,
      count: businesses.length + other.businesses.length,
      total: other.total,
      hasMore: other.hasMore,
      regionId: regionId ?? other.regionId,
      regionNameAr: regionNameAr ?? other.regionNameAr,
      listingVersion: other.listingVersion ?? listingVersion,
      fetchedAt: other.fetchedAt,
      includesNeighborRegions:
          includesNeighborRegions || other.includesNeighborRegions,
    );
  }

  /// Create a copy with modified fields
  /// إنشاء نسخة مع تعديل بعض الحقول
  RestaurantListResponse copyWith({
    List<dynamic>? businesses,
    int? page,
    int? count,
    int? total,
    bool? hasMore,
    String? regionId,
    String? regionNameAr,
    int? listingVersion,
    DateTime? fetchedAt,
    bool? includesNeighborRegions,
  }) {
    return RestaurantListResponse(
      businesses: businesses ?? this.businesses,
      page: page ?? this.page,
      count: count ?? this.count,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      regionId: regionId ?? this.regionId,
      regionNameAr: regionNameAr ?? this.regionNameAr,
      listingVersion: listingVersion ?? this.listingVersion,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      includesNeighborRegions:
          includesNeighborRegions ?? this.includesNeighborRegions,
    );
  }

  @override
  String toString() {
    return 'RestaurantListResponse('
        'businesses: ${businesses.length}, '
        'page: $page, '
        'total: $total, '
        'hasMore: $hasMore, '
        'regionId: $regionId'
        ')';
  }
}
