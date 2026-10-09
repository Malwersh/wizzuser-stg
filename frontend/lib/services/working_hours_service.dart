import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/working_hours_model.dart';
import '../config/api_config.dart';

class WorkingHoursService {
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  // جلب ساعات العمل لمطعم محدد - إرجاع جميع الأيام
  static Future<List<WorkingHoursModel>?> getAllBusinessWorkingHours(String businessId) async {
    try {
      if (kDebugMode) {
        print('🕒 جلب ساعات العمل للمطعم: $businessId');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/business/$businessId/working-hours'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('📊 Response Status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['workingHours'] != null) {
          final workingHoursList = data['workingHours'] as List;
          if (workingHoursList.isNotEmpty) {
            // تحويل جميع البيانات إلى WorkingHoursModel objects
            return workingHoursList.map<WorkingHoursModel>((item) {
              return WorkingHoursModel(
                businessId: businessId,
                weekday: item['weekday']?.toString() ?? '',
                opening: item['opening']?.toString() ?? '',
                closing: item['closing']?.toString() ?? '',
                isClosed: item['isClosed'] as bool? ?? 
                         (item['opening'] == 'closed' || item['closing'] == 'closed'),
                updatedAt: item['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
              );
            }).toList();
          }
        }
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ خطأ في getAllBusinessWorkingHours: $e');
      }
      return null;
    }
  }

  // جلب ساعات العمل لمطعم محدد - للتوافق مع الإصدارات السابقة (إرجاع اليوم الحالي فقط)
  static Future<WorkingHoursModel?> getBusinessWorkingHours(String businessId) async {
    try {
      final allHours = await getAllBusinessWorkingHours(businessId);
      if (allHours != null && allHours.isNotEmpty) {
        // البحث عن اليوم الحالي
        final now = DateTime.now();
        final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        final today = weekdays[now.weekday - 1];
        
        final todayHours = allHours.where((item) => 
            item.weekday.toLowerCase() == today.toLowerCase()).firstOrNull;
        
        return todayHours ?? allHours.first;
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ خطأ في getBusinessWorkingHours: $e');
      }
      return null;
    }
  }

  // تحديث ساعات العمل لمطعم محدد
  static Future<bool> updateBusinessWorkingHours(String businessId, WorkingHoursModel workingHours) async {
    try {
      if (kDebugMode) {
        print('📝 تحديث ساعات العمل للمطعم: $businessId');
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/business/$businessId/working-hours'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(workingHours.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('📊 Response Status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ خطأ في updateBusinessWorkingHours: $e');
      }
      return false;
    }
  }

  // فحص إذا كان المطعم مفتوح الآن
  static Future<bool> isBusinessOpen(String businessId) async {
    try {
      final workingHours = await getBusinessWorkingHours(businessId);
      if (workingHours == null) return false;
      
      // فحص إذا كان المطعم مغلق يدوياً
      if (workingHours.isClosed) return false;
      
      // فحص ساعات العمل
      final now = DateTime.now();
      final currentTime = now.hour * 60 + now.minute; // الوقت بالدقائق
      final openTime = _timeToMinutes(workingHours.opening);
      final closeTime = _timeToMinutes(workingHours.closing);
      
      if (closeTime < openTime) {
        // المطعم يعمل عبر منتصف الليل
        return currentTime >= openTime || currentTime <= closeTime;
      } else {
        // المطعم يعمل في نفس اليوم
        return currentTime >= openTime && currentTime <= closeTime;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ خطأ في isBusinessOpen: $e');
      }
      return false;
    }
  }

  // تحويل الوقت من نص إلى دقائق
  static int _timeToMinutes(String time) {
    try {
      final parts = time.split(':');
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      return hours * 60 + minutes;
    } catch (e) {
      return 0;
    }
  }
}

