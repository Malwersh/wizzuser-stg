import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'business_status_cache.dart';
import 'working_hours_service.dart';
import '../config/api_config.dart';

/// خدمة فحص توفر المطاعم بناءً على ساعات العمل وحالة قبول الطلبات
/// بدلاً من الاعتماد على WebSocket
class RestaurantAvailabilityService {
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  static RestaurantAvailabilityService? _instance;
  static RestaurantAvailabilityService get instance => 
      _instance ??= RestaurantAvailabilityService._();
  
  RestaurantAvailabilityService._();

  /// فحص توفر المطعم بناءً على ساعات العمل وحالة قبول الطلبات
  Future<RestaurantAvailabilityStatus> checkRestaurantAvailability(
    String businessId, {
    bool skipCache = false,
  }) async {
    try {
      developer.log('🔍 فحص توفر المطعم: $businessId (skipCache: $skipCache)');

      // التحقق من البيانات المؤقتة أولاً (إلا إذا طُلب تجاهل الـ cache)
      if (!skipCache) {
        final cachedStatus = await BusinessStatusCache.getCachedBusinessStatus(businessId);
        if (cachedStatus != null) {
          return RestaurantAvailabilityStatus.fromJson(cachedStatus);
        }
      }

      // جلب حالة قبول الطلبات من جدول المطاعم
      final acceptingOrders = await _getAcceptingOrdersStatus(businessId);
      
      // جلب ساعات العمل
      final workingHours = await _getWorkingHours(businessId);
      
      // تحديد اليوم الحالي
      final now = DateTime.now();
      final currentDay = _getCurrentDay(now);
      
      // فحص ساعات العمل لليوم الحالي
      final todaysHours = workingHours[currentDay];
      final isWithinWorkingHours = _isWithinWorkingHours(now, todaysHours);
      
      // تحديد حالة التوفر النهائية بالمنطق الجديد:
      // 1. إذا لم يكن يستقبل طلبات -> مشغول (غير متاح)
      // 2. إذا كان خارج ساعات العمل -> مغلق (غير متاح) 
      // 3. إذا كان يستقبل طلبات وضمن ساعات العمل -> متاح
      
      bool isAvailable;
      String reasonUnavailable = '';
      
      if (!acceptingOrders) {
        isAvailable = false;
        reasonUnavailable = 'مشغول';
      } else if (!isWithinWorkingHours) {
        isAvailable = false;
        reasonUnavailable = 'مغلق';
      } else {
        isAvailable = true;
        reasonUnavailable = '';
      }
      
      final status = RestaurantAvailabilityStatus(
        businessId: businessId,
        isAvailable: isAvailable,
        acceptingOrders: acceptingOrders,
        isWithinWorkingHours: isWithinWorkingHours,
        workingHours: workingHours,
        checkedAt: now,
        reasonUnavailable: reasonUnavailable,
      );

      // حفظ النتيجة في الذاكرة المؤقتة
      await BusinessStatusCache.cacheBusinessStatus(
        businessId, 
        status.toJson()
      );

      developer.log('✅ حالة المطعم $businessId: ${isAvailable ? "متاح" : "غير متاح"}');
      
      return status;
      
    } catch (e) {
      developer.log('❌ خطأ في فحص توفر المطعم $businessId: $e');
      
      // إرجاع حالة افتراضية في حالة الخطأ
      return RestaurantAvailabilityStatus(
        businessId: businessId,
        isAvailable: false,
        acceptingOrders: false,
        isWithinWorkingHours: false,
        workingHours: {},
        checkedAt: DateTime.now(),
        reasonUnavailable: 'حدث خطأ في فحص حالة المطعم',
      );
    }
  }

  /// جلب حالة قبول الطلبات من جدول المطاعم
  Future<bool> _getAcceptingOrdersStatus(String businessId) async {
    try {
      // استخدام endpoint صحيح - جلب المطعم من قائمة المطاعم
      final url = Uri.parse(ApiConfig.buildUrl(ApiConfig.businessesEndpoint)).replace(
        queryParameters: const {'limit': '1000'},
      );
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['businesses'] != null) {
          final businesses = data['businesses'] as List;
          
          // البحث عن المطعم المطلوب
          final business = businesses.firstWhere(
            (b) => b['business_id'] == businessId,
            orElse: () => null,
          );
          
          if (business != null) {
            // التحقق من وجود acceptingOrders field
            if (business.containsKey('acceptingOrders')) {
              final acceptingOrders = business['acceptingOrders'] ?? false;
              developer.log('✅ المطعم $businessId - acceptingOrders: $acceptingOrders');
              return acceptingOrders;
            }
            
            developer.log('⚠️ المطعم $businessId لا يحتوي على حقل acceptingOrders');
            return false;
          }
          
          developer.log('⚠️ المطعم $businessId غير موجود في قائمة المطاعم');
          return false;
        }
      }
      
      developer.log('⚠️ فشل في جلب قائمة المطاعم: ${response.statusCode}');
      return false;
      
    } catch (e) {
      developer.log('❌ خطأ في جلب حالة قبول الطلبات: $e');
      return false;
    }
  }


  /// جلب ساعات العمل من جدول ساعات العمل - محسّن للحصول على جميع الأيام
  Future<Map<String, WorkingHours?>> _getWorkingHours(String businessId) async {
    try {
      // 🔥 استخدام الخدمة المحسّنة للحصول على جميع الأيام مع isClosed
      final allWorkingHours = await WorkingHoursService.getAllBusinessWorkingHours(businessId);
      
      if (allWorkingHours != null && allWorkingHours.isNotEmpty) {
        final Map<String, WorkingHours?> workingHours = {};
        
        // تحويل البيانات إلى خريطة مفهرسة بأيام الأسبوع
        for (final workingHoursModel in allWorkingHours) {
          final weekday = workingHoursModel.weekday;
          final opening = workingHoursModel.opening;
          final closing = workingHoursModel.closing;
          final isClosed = workingHoursModel.isClosed;
          
          developer.log('📅 يوم $weekday: فتح=$opening, إغلاق=$closing, مغلق=$isClosed');
          
          // إذا كان اليوم مغلق أو الأوقات فارغة/مغلقة
          if (isClosed || opening.isEmpty || closing.isEmpty || 
              opening == 'closed' || closing == 'closed' ||
              opening == 'none' || closing == 'none') {
            workingHours[weekday] = WorkingHours(
              opening: opening.isEmpty ? '00:00' : opening,
              closing: closing.isEmpty ? '00:00' : closing,
              isClosed: true, // 🔥 تحديد أن اليوم مغلق
            );
          } else {
            workingHours[weekday] = WorkingHours(
              opening: opening,
              closing: closing,
              isClosed: false, // 🔥 اليوم مفتوح
            );
          }
        }
        
        developer.log('✅ تم جلب ساعات العمل لجميع الأيام للمطعم: $businessId (${workingHours.length} أيام)');
        return workingHours;
      }
      
      developer.log('⚠️ لم يتم العثور على ساعات العمل للمطعم: $businessId');
      return {};
      
    } catch (e) {
      developer.log('❌ خطأ في جلب ساعات العمل: $e');
      // العودة إلى الطريقة القديمة في حالة الخطأ
      return await _getWorkingHoursLegacy(businessId);
    }
  }

  /// الطريقة القديمة لجلب ساعات العمل (احتياط)
  Future<Map<String, WorkingHours?>> _getWorkingHoursLegacy(String businessId) async {
    try {
      final url = Uri.parse('$_baseUrl/business/$businessId/working-hours');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['workingHours'] != null) {
          final workingHoursData = data['workingHours'] as List;
          final Map<String, WorkingHours?> workingHours = {};
          
          // تحويل البيانات إلى خريطة مفهرسة بأيام الأسبوع
          for (final item in workingHoursData) {
            final weekday = item['weekday'] as String;
            final opening = item['opening'] as String?;
            final closing = item['closing'] as String?;
            final isClosed = item['isClosed'] as bool? ?? false; // 🔥 قراءة حقل isClosed
            
            if (opening != null && closing != null) {
              workingHours[weekday] = WorkingHours(
                opening: opening,
                closing: closing,
                isClosed: isClosed, // 🔥 تمرير حقل isClosed
              );
            } else {
              workingHours[weekday] = null; // اليوم مغلق
            }
          }
          
          return workingHours;
        }
      }
      
      developer.log('⚠️ لم يتم العثور على ساعات العمل للمطعم: $businessId');
      return {};
      
    } catch (e) {
      developer.log('❌ خطأ في جلب ساعات العمل: $e');
      return {};
    }
  }

  /// تحديد اليوم الحالي بتنسيق النظام
  String _getCurrentDay(DateTime now) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 
      'Friday', 'Saturday', 'Sunday'
    ];
    return days[now.weekday - 1];
  }

  /// فحص إذا كان الوقت الحالي ضمن ساعات العمل
  bool _isWithinWorkingHours(DateTime now, WorkingHours? workingHours) {
    if (workingHours == null) {
      return false; // اليوم مغلق
    }

    // 🔥 فحص أولوية عالية: إذا كان اليوم مغلق بالكامل (isClosed=true)
    if (workingHours.isClosed == true) {
      developer.log('🚫 المطعم مغلق بالكامل اليوم (isClosed=true)');
      return false;
    }

    try {
      // تحويل أوقات الفتح والإغلاق إلى دقائق من بداية اليوم
      final openingMinutes = _timeStringToMinutes(workingHours.opening);
      final closingMinutes = _timeStringToMinutes(workingHours.closing);
      final currentMinutes = now.hour * 60 + now.minute;

      // التعامل مع الحالات التي يكون فيها وقت الإغلاق في اليوم التالي
      if (closingMinutes < openingMinutes) {
        // المطعم يعمل عبر منتصف الليل
        return currentMinutes >= openingMinutes || currentMinutes <= closingMinutes;
      } else {
        // المطعم يعمل في نفس اليوم
        return currentMinutes >= openingMinutes && currentMinutes <= closingMinutes;
      }
    } catch (e) {
      developer.log('❌ خطأ في فحص ساعات العمل: $e');
      return false;
    }
  }

  /// تحويل نص الوقت (HH:MM) إلى دقائق من بداية اليوم
  int _timeStringToMinutes(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) {
      throw ArgumentError('تنسيق وقت غير صحيح: $timeString');
    }
    
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    
    return hour * 60 + minute;
  }

  /// فحص توفر عدة مطاعم في نفس الوقت
  Future<Map<String, RestaurantAvailabilityStatus>> checkMultipleRestaurants(
    List<String> businessIds
  ) async {
    final Map<String, RestaurantAvailabilityStatus> results = {};
    
    // استخدام Future.wait للتحقق المتوازي
    final futures = businessIds.map((id) => checkRestaurantAvailability(id));
    final statuses = await Future.wait(futures);
    
    for (int i = 0; i < businessIds.length; i++) {
      results[businessIds[i]] = statuses[i];
    }
    
    return results;
  }
  
  /// مسح كاش المطعم عند تحديث ساعات العمل أو حالة المطعم
  Future<void> invalidateBusinessCache(String businessId) async {
    try {
      await BusinessStatusCache.clearCachedBusinessStatus(businessId);
      developer.log('🗑️ تم مسح كاش المطعم: $businessId');
    } catch (e) {
      developer.log('❌ خطأ في مسح كاش المطعم $businessId: $e');
    }
  }
  
  /// فرض إعادة فحص حالة المطعم (تجاهل الكاش)
  Future<RestaurantAvailabilityStatus> forceRefreshRestaurantStatus(String businessId) async {
    return await checkRestaurantAvailability(businessId, skipCache: true);
  }
}

/// فئة تمثل ساعات العمل
class WorkingHours {
  final String opening;
  final String closing;
  final bool isClosed; // 🔥 إضافة حقل isClosed

  const WorkingHours({
    required this.opening,
    required this.closing,
    this.isClosed = false, // افتراضياً غير مغلق
  });

  Map<String, dynamic> toJson() => {
    'opening': opening,
    'closing': closing,
    'isClosed': isClosed,
  };

  factory WorkingHours.fromJson(Map<String, dynamic> json) => WorkingHours(
    opening: json['opening'] as String,
    closing: json['closing'] as String,
    isClosed: json['isClosed'] as bool? ?? false,
  );
}

/// فئة تمثل حالة توفر المطعم
class RestaurantAvailabilityStatus {
  final String businessId;
  final bool isAvailable;
  final bool acceptingOrders;
  final bool isWithinWorkingHours;
  final Map<String, WorkingHours?> workingHours;
  final DateTime checkedAt;
  final String? reasonUnavailable;

  const RestaurantAvailabilityStatus({
    required this.businessId,
    required this.isAvailable,
    required this.acceptingOrders,
    required this.isWithinWorkingHours,
    required this.workingHours,
    required this.checkedAt,
    this.reasonUnavailable,
  });

  Map<String, dynamic> toJson() => {
    'businessId': businessId,
    'isAvailable': isAvailable,
    'acceptingOrders': acceptingOrders,
    'isWithinWorkingHours': isWithinWorkingHours,
    'workingHours': workingHours.map((key, value) => MapEntry(key, value?.toJson())),
    'checkedAt': checkedAt.millisecondsSinceEpoch,
    'reasonUnavailable': reasonUnavailable,
  };

  factory RestaurantAvailabilityStatus.fromJson(Map<String, dynamic> json) {
    final workingHoursMap = <String, WorkingHours?>{};
    if (json['workingHours'] != null) {
      (json['workingHours'] as Map<String, dynamic>).forEach((key, value) {
        workingHoursMap[key] = value != null ? WorkingHours.fromJson(value) : null;
      });
    }

    return RestaurantAvailabilityStatus(
      businessId: json['businessId'] as String,
      isAvailable: json['isAvailable'] as bool,
      acceptingOrders: json['acceptingOrders'] as bool,
      isWithinWorkingHours: json['isWithinWorkingHours'] as bool,
      workingHours: workingHoursMap,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(json['checkedAt'] as int),
      reasonUnavailable: json['reasonUnavailable'] as String?,
    );
  }
}
