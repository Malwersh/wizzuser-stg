import 'dart:developer' as developer;
// lib/models/working_hours_model.dart

class WorkingHoursModel {
  final String businessId;
  final String weekday;
  final String opening;
  final String closing;
  final String updatedAt;
  final bool isClosed; // 🔥 إضافة حقل isClosed

  WorkingHoursModel({
    required this.businessId,
    required this.weekday,
    required this.opening,
    required this.closing,
    required this.updatedAt,
    this.isClosed = false, // 🔥 افتراضياً غير مغلق
  });

  factory WorkingHoursModel.fromJson(Map<String, dynamic> json) {
    return WorkingHoursModel(
      businessId: json['business_id']?.toString() ?? '',
      weekday: json['weekday']?.toString() ?? '',
      opening: json['opening']?.toString() ?? '',
      closing: json['closing']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      isClosed: json['isClosed'] as bool? ?? false, // 🔥 قراءة حقل isClosed
    );
  }

  // Create from API response
  factory WorkingHoursModel.fromApiResponse(Map<String, dynamic> data) {
    // Extract working hours data from API response
    if (data['workingHours'] != null) {
      final workingHoursData = data['workingHours'] as Map<String, dynamic>;
      final businessId = data['businessId']?.toString() ?? '';
      
      // Get current day
      final now = DateTime.now();
      final currentWeekday = _getCurrentWeekdayStatic(now.weekday);
      
      return WorkingHoursModel(
        businessId: businessId,
        weekday: currentWeekday,
        opening: workingHoursData['opening']?.toString() ?? '',
        closing: workingHoursData['closing']?.toString() ?? '',
        updatedAt: data['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
        isClosed: workingHoursData['isClosed'] as bool? ?? false,
      );
    }
    
    return WorkingHoursModel.createDefault();
  }

  // Create default/empty working hours
  factory WorkingHoursModel.createDefault() {
    final now = DateTime.now();
    final currentWeekday = _getCurrentWeekdayStatic(now.weekday);
    
    return WorkingHoursModel(
      businessId: '',
      weekday: currentWeekday,
      opening: '',
      closing: '',
      updatedAt: now.toIso8601String(),
      isClosed: false,
    );
  }

  // Static helper method for weekday conversion
  static String _getCurrentWeekdayStatic(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Monday';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'weekday': weekday,
      'opening': opening,
      'closing': closing,
      'updated_at': updatedAt,
      'isClosed': isClosed, // 🔥 إضافة حقل isClosed للتصدير
    };
  }

  // تحويل اسم اليوم إلى العربية
  String get arabicWeekday {
    switch (weekday.toLowerCase()) {
      case 'sunday':
        return 'الأحد';
      case 'monday':
        return 'الاثنين';
      case 'tuesday':
        return 'الثلاثاء';
      case 'wednesday':
        return 'الأربعاء';
      case 'thursday':
        return 'الخميس';
      case 'friday':
        return 'الجمعة';
      case 'saturday':
        return 'السبت';
      default:
        return weekday;
    }
  }

  // تحويل الوقت إلى تنسيق 12 ساعة
  String get formattedOpening {
    return _formatTime(opening);
  }

  String get formattedClosing {
    return _formatTime(closing);
  }

  // عرض نص ساعات العمل لليوم
  String get dayScheduleText {
    // 🔥 فحص أولوية عالية: إذا كان مغلق صراحة (isClosed=true)
    if (isClosed) {
      return 'مغلق - اليوم عطلة';
    }
    
    if (!isWorkingDay) {
      return 'مغلق';
    }
    return '$formattedOpening - $formattedClosing';
  }

  String _formatTime(String time) {
    try {
      // فحص القيم الفارغة
      if (time.isEmpty) {
        return '--:--';
      }
      
      final parts = time.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        
        // فحص القيم غير المنطقية
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
          return '--:--';
        }
        
        if (hour == 0) {
          return '12:${minute.toString().padLeft(2, '0')} ص';
        } else if (hour < 12) {
          return '$hour:${minute.toString().padLeft(2, '0')} ص';
        } else if (hour == 12) {
          return '12:${minute.toString().padLeft(2, '0')} م';
        } else {
          return '${hour - 12}:${minute.toString().padLeft(2, '0')} م';
        }
      }
      return '--:--';
    } catch (e) {
      return '--:--';
    }
  }

  // فحص ما إذا كان المطعم مفتوح الآن
  bool get isOpenNow {
    // 🔥 فحص أولوية عالية: إذا كان مغلق صراحة (isClosed=true)
    if (isClosed) {
      return false;
    }
    
    // فحص القيم الفارغة أو غير الصحيحة
    if (opening.isEmpty || closing.isEmpty || 
        opening == '00:00' && closing == '00:00') {
      return false; // مغلق إذا لم تُحدد ساعات العمل
    }
    
    final now = DateTime.now();
    final currentWeekday = _getCurrentWeekday(now.weekday);
    
    if (weekday.toLowerCase() != currentWeekday.toLowerCase()) {
      return false;
    }
    
    return _isTimeInRange(now, opening, closing);
  }

  // فحص ما إذا كان اليوم مُعرَّف كيوم عمل
  bool get isWorkingDay {
    // 🔥 فحص أولوية عالية: إذا كان مغلق صراحة (isClosed=true)
    if (isClosed) {
      return false;
    }
    
    return opening.isNotEmpty && closing.isNotEmpty && 
           !(opening == '00:00' && closing == '00:00');
  }

  String _getCurrentWeekday(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Monday';
    }
  }

  bool _isTimeInRange(DateTime now, String openTime, String closeTime) {
    try {
      // فحص القيم الفارغة
      if (openTime.isEmpty || closeTime.isEmpty) {
        return false;
      }
      
      final openParts = openTime.split(':');
      final closeParts = closeTime.split(':');
      
      if (openParts.length < 2 || closeParts.length < 2) {
        return false; // مغلق إذا كان التنسيق غير صحيح
      }
      
      final openHour = int.parse(openParts[0]);
      final openMinute = int.parse(openParts[1]);
      final closeHour = int.parse(closeParts[0]);
      final closeMinute = int.parse(closeParts[1]);
      
      // فحص إضافي للقيم غير المنطقية
      if (openHour < 0 || openHour > 23 || closeHour < 0 || closeHour > 23 ||
          openMinute < 0 || openMinute > 59 || closeMinute < 0 || closeMinute > 59) {
        return false;
      }
      
      // إذا كان وقت الفتح والإغلاق متطابقين (00:00 - 00:00) يعني مغلق
      if (openHour == 0 && openMinute == 0 && closeHour == 0 && closeMinute == 0) {
        return false;
      }
      
      final currentHour = now.hour;
      final currentMinute = now.minute;
      
      final currentTimeInMinutes = currentHour * 60 + currentMinute;
      final openTimeInMinutes = openHour * 60 + openMinute;
      final closeTimeInMinutes = closeHour * 60 + closeMinute;
      
      // إذا كان وقت الإغلاق أقل من وقت الفتح، يعني أن المطعم يعمل عبر منتصف الليل
      if (closeTimeInMinutes < openTimeInMinutes) {
        return currentTimeInMinutes >= openTimeInMinutes || currentTimeInMinutes <= closeTimeInMinutes;
      } else {
        return currentTimeInMinutes >= openTimeInMinutes && currentTimeInMinutes <= closeTimeInMinutes;
      }
    } catch (e) {
      developer.log('خطأ في تحليل الوقت: $e');
      return false; // مغلق في حالة الخطأ لضمان الأمان
    }
  }
}

// كلاس لإدارة جميع ساعات العمل لمطعم واحد
class BusinessWorkingHours {
  final String businessId;
  final List<WorkingHoursModel> workingHours;

  BusinessWorkingHours({
    required this.businessId,
    required this.workingHours,
  });

  // فحص ما إذا كان المطعم مفتوح الآن
  bool get isOpenNow {
    // فحص إذا كانت قائمة ساعات العمل فارغة
    if (workingHours.isEmpty) {
      return false; // مغلق إذا لم تُحدد ساعات العمل نهائياً
    }
    
    final now = DateTime.now();
    final currentWeekday = _getCurrentWeekday(now.weekday);
    
    final todayHours = workingHours.where(
      (hours) => hours.weekday.toLowerCase() == currentWeekday.toLowerCase(),
    ).toList();
    
    // إذا لم يتم العثور على ساعات عمل لليوم الحالي
    if (todayHours.isEmpty) {
      return false; // مغلق إذا لم تُحدد ساعات العمل لهذا اليوم
    }
    
    return todayHours.first.isOpenNow;
  }

  // فحص ما إذا كان للمطعم ساعات عمل محددة
  bool get hasWorkingHours {
    if (workingHours.isEmpty) return false;
    
    // فحص إذا كان هناك على الأقل يوم واحد بساعات عمل صحيحة
    return workingHours.any((hours) => hours.isWorkingDay);
  }

  // الحصول على ساعات العمل لليوم الحالي
  WorkingHoursModel? get todayWorkingHours {
    if (workingHours.isEmpty) return null;
    
    final now = DateTime.now();
    final currentWeekday = _getCurrentWeekday(now.weekday);
    
    try {
      return workingHours.firstWhere(
        (hours) => hours.weekday.toLowerCase() == currentWeekday.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  // الحصول على النص الذي يظهر للمستخدم
  String get statusText {
    // فحص إذا لم تُحدد ساعات العمل نهائياً
    if (!hasWorkingHours) {
      return 'ساعات العمل غير محددة';
    }
    
    // 🔥 فحص أولوية عالية لحالة isClosed
    final todayHours = todayWorkingHours;
    if (todayHours != null && todayHours.isClosed) {
      return 'مغلق - اليوم عطلة';
    }
    
    if (isOpenNow) {
      if (todayHours != null && todayHours.isWorkingDay) {
        return 'مفتوح حتى ${todayHours.formattedClosing}';
      }
      return 'مفتوح';
    } else {
      // البحث عن وقت الفتح التالي
      final nextOpenTime = _getNextOpenTime();
      if (nextOpenTime != null) {
        return 'مغلق - يفتح $nextOpenTime';
      }
      return 'مغلق';
    }
  }

  String? _getNextOpenTime() {
    if (workingHours.isEmpty) return null;
    
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    
    // البحث في الأيام القادمة
    for (int i = 0; i < 7; i++) {
      final checkDay = (currentWeekday + i) % 7;
      final weekdayName = _getCurrentWeekday(checkDay == 0 ? 7 : checkDay);
      
      final dayHoursList = workingHours.where(
        (hours) => hours.weekday.toLowerCase() == weekdayName.toLowerCase(),
      ).toList();
      
      if (dayHoursList.isEmpty) continue;
      
      final dayHours = dayHoursList.first;
      
      // تجاهل الأيام المغلقة أو التي بها ساعات عمل غير صحيحة
      if (!dayHours.isWorkingDay) continue;
      
      if (i == 0) {
        // اليوم الحالي - تحقق من الوقت
        try {
          final openParts = dayHours.opening.split(':');
          if (openParts.length >= 2) {
            final openHour = int.parse(openParts[0]);
            final openMinute = int.parse(openParts[1]);
            
            if (now.hour < openHour || (now.hour == openHour && now.minute < openMinute)) {
              return 'اليوم ${dayHours.formattedOpening}';
            }
          }
        } catch (e) {
          // تجاهل الأخطاء في تحليل الوقت
          continue;
        }
      } else {
        // الأيام القادمة
        return '${dayHours.arabicWeekday} ${dayHours.formattedOpening}';
      }
    }
    
    return null;
  }

  String _getCurrentWeekday(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Monday';
    }
  }

  // ترتيب أيام الأسبوع بداية من الأحد
  List<WorkingHoursModel> get sortedWorkingHours {
    final weekdayOrder = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    
    final sortedList = <WorkingHoursModel>[];
    for (final day in weekdayOrder) {
      try {
        final dayHours = workingHours.firstWhere(
          (hours) => hours.weekday.toLowerCase() == day.toLowerCase(),
        );
        sortedList.add(dayHours);
      } catch (e) {
        // إذا لم يتم العثور على ساعات عمل لهذا اليوم، أضف يوم مغلق
        sortedList.add(WorkingHoursModel(
          businessId: businessId,
          weekday: day,
          opening: '', // قيمة فارغة تدل على عدم تحديد ساعات العمل
          closing: '', // قيمة فارغة تدل على عدم تحديد ساعات العمل
          updatedAt: '',
        ));
      }
    }
    
    return sortedList;
  }

  // الحصول على نص حالة المطعم مع لون مناسب
  Map<String, dynamic> get statusInfo {
    if (!hasWorkingHours) {
      return {
        'text': 'ساعات العمل غير محددة',
        'color': 'grey',
        'isOpen': false,
      };
    }
    
    if (isOpenNow) {
      return {
        'text': statusText,
        'color': 'green',
        'isOpen': true,
      };
    } else {
      return {
        'text': statusText,
        'color': 'red',
        'isOpen': false,
      };
    }
  }
}
