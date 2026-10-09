import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class BusinessStatusService {
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  // جلب حالة المطعم
  static Future<Map<String, dynamic>?> getBusinessStatus(String businessId) async {
    try {
      if (kDebugMode) {
        print('🔍 جلب حالة المطعم: $businessId');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/business/$businessId/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('📊 Response Status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          return {
            'isOpen': data['isOpen'] ?? false,
            'isClosed': data['isClosed'] ?? false,
            'isTemporarilyClosed': data['isTemporarilyClosed'] ?? false,
            'openingTime': data['openingTime'],
            'closingTime': data['closingTime'],
            'message': data['message'],
            'lastUpdated': data['lastUpdated'],
          };
        }
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ خطأ في getBusinessStatus: $e');
      }
      return null;
    }
  }

  // تحديث حالة المطعم (مفتوح/مغلق)
  static Future<bool> updateBusinessStatus(String businessId, {
    bool? isOpen,
    bool? isClosed,
    bool? isTemporarilyClosed,
    String? message,
  }) async {
    try {
      if (kDebugMode) {
        print('📝 تحديث حالة المطعم: $businessId');
      }

      final Map<String, dynamic> body = {};
      if (isOpen != null) body['isOpen'] = isOpen;
      if (isClosed != null) body['isClosed'] = isClosed;
      if (isTemporarilyClosed != null) body['isTemporarilyClosed'] = isTemporarilyClosed;
      if (message != null) body['message'] = message;

      final response = await http.put(
        Uri.parse('$_baseUrl/business/$businessId/status'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
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
        print('❌ خطأ في updateBusinessStatus: $e');
      }
      return false;
    }
  }

  // فحص إذا كان المطعم متاح للطلبات
  static Future<bool> isBusinessAvailable(String businessId) async {
    try {
      final status = await getBusinessStatus(businessId);
      if (status == null) return false;
      
      return status['isOpen'] == true && 
             status['isClosed'] != true && 
             status['isTemporarilyClosed'] != true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ خطأ في isBusinessAvailable: $e');
      }
      return false;
    }
  }

  // إغلاق المطعم مؤقتاً
  static Future<bool> closeBusinessTemporarily(String businessId, String reason) async {
    return await updateBusinessStatus(
      businessId,
      isTemporarilyClosed: true,
      message: reason,
    );
  }

  // فتح المطعم
  static Future<bool> openBusiness(String businessId) async {
    return await updateBusinessStatus(
      businessId,
      isOpen: true,
      isClosed: false,
      isTemporarilyClosed: false,
      message: 'المطعم مفتوح ومتاح للطلبات',
    );
  }
}

