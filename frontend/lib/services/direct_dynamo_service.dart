import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/business_model.dart';
import '../config/api_config.dart';

/// خدمة مؤقتة لاختبار الاتصال المباشر بـ DynamoDB
class DirectDynamoService {
  /// اختبار بسيط للحصول على business واحد
  static Future<Map<String, dynamic>?> testGetBusiness(String businessId) async {
    try {
      final urlString = ApiConfig.buildUrl('${ApiConfig.businessesEndpoint}/$businessId');
      debugPrint('🔄 اختبار الاتصال بـ: $urlString');
      
      final response = await http.get(
        Uri.parse(urlString),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('📡 Response Status: ${response.statusCode}');
      debugPrint('📡 Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint('❌ خطأ في الاستجابة: ${response.statusCode}');
        return null;
      }
      
    } catch (e) {
      debugPrint('❌ خطأ في الاتصال: $e');
      return null;
    }
  }
  
  /// اختبار الحصول على قائمة businesses مبسطة
  static Future<List<BusinessModel>> testGetBusinessList() async {
    try {
      debugPrint('🔄 اختبار الحصول على قائمة الأعمال...');
      
      // جرب اختبار business واحد أولاً
      final testBusiness = await testGetBusiness('1c5eeac7-7cad-4c0c-b5c7-a538951f8caa');
      
      if (testBusiness != null) {
        debugPrint('✅ تم الحصول على بيانات حقيقية!');
        // إنشاء business model من البيانات الحقيقية
        try {
          final business = BusinessModel.fromJson(testBusiness);
          return [business];
        } catch (e) {
          debugPrint('❌ خطأ في تحويل البيانات: $e');
        }
      }
      
      debugPrint('⚠️ لم يتم الحصول على بيانات حقيقية، استخدام بيانات تجريبية...');
      
      // في حالة الفشل، إرجاع بيانات تجريبية واحدة
      return [
        BusinessModel(
          id: 'test-1',
          businessName: 'مطعم الاختبار المباشر',
          address: 'بغداد، اختبار الاتصال',
          businessPhotoUrl: 'https://via.placeholder.com/300x200',
          businessType: 'restaurant',
          rating: 4.5,
          distance: '1.2 كم',
          deliveryFee: '5000',
          deliveryTime: '25 دقيقة',
          phone: '07901234567',
          email: 'test@example.com',
        ),
      ];
      
    } catch (e) {
      debugPrint('❌ خطأ عام في testGetBusinessList: $e');
      return [];
    }
  }
}

