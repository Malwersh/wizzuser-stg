import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:foodapp_user/services/session_service.dart';
import '../config/api_config.dart';
// import 'api_optimization_service.dart'; // Disabled for frontend-only mode
// import 'advanced_cache_service.dart'; // Disabled for frontend-only mode
// import 'enhanced_api_service.dart'; // Disabled for frontend-only mode

class ApiService {
  // خدمات التحسين - Disabled for frontend-only mode
  // static final AdvancedCacheService _cache = AdvancedCacheService();
  static bool _isInitialized = false;

  // تهيئة الخدمات
  static Future<void> init() async {
    if (!_isInitialized) {
      // await _cache.init();
      // await EnhancedApiService.initialize();
      _isInitialized = true;
      debugPrint('✅ API Service with optimizations initialized (Frontend-only mode)');
    }
  }

  // تحديد العنوان حسب النظام - للاتصال بخادم الإنتاج الفعلي (NEW BACKEND)
  static String get baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  // للتبديل بين خادم الاختبار وخادم الإنتاج أثناء التطوير
  static String get testServerUrl => baseUrl;

  // متغير للتحكم في استخدام خادم الاختبار أو الإنتاج
  static bool useTestServer = false; // تغيير إلى true لاستخدام خادم الاختبار

  // الحصول على URL الصحيح حسب الإعداد
  static String get currentBaseUrl {
    return useTestServer ? testServerUrl : baseUrl;
  }

  static Future<Map<String, dynamic>> login(String identifier, String password) async {
    final url = Uri.parse("$currentBaseUrl/auth/login");
// للتشخيص
// للتشخيص

    try {
      final requestBody = jsonEncode({"identifier": identifier, "password": password});
// للتشخيص

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: requestBody,
      ).timeout(const Duration(seconds: 10)); // مهلة زمنية
// للتشخيص
// للتشخيص

      final responseData = jsonDecode(utf8.decode(response.bodyBytes)); // لحل مشكلة الترميز
// للتشخيص

      if (response.statusCode == 200) {
        return {"success": true, "data": responseData};
      } else {
// للتشخيص
        
        // معالجة محسنة لرسائل الخطأ
        String errorMessage = "فشل تسجيل الدخول";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        // رسائل خاصة لأخطاء تسجيل الدخول
        if (response.statusCode == 401) {
          errorMessage = "المعلومات المدخلة خاطئة، حاول مرة أخرى";
        }
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
// للتشخيص
      if (e.toString().contains('SocketException')) {
        return {"success": false, "message": "تعذر الوصول إلى الخادم. تأكد من أن الخادم يعمل على البورت 8080"};
      } else if (e.toString().contains('TimeoutException')) {
        return {"success": false, "message": "انتهت مهلة الاتصال. تحقق من اتصال الإنترنت"};
      } else {
        return {"success": false, "message": "خطأ في الاتصال: $e"};
      }
    }
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    final url = Uri.parse('$currentBaseUrl/auth/register');
// للتشخيص
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email.isEmpty ? null : email,
          'password': password,
          'phone': phone,
        }),
      ).timeout(const Duration(seconds: 10)); // مهلة زمنية
// للتشخيص
// للتشخيص

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 201) { // Backend returns 201 for registration
        return {"success": true, "data": responseData};
      } else {
        // معالجة محسنة لرسائل الخطأ من الخادم
        String errorMessage = "حدث خطأ غير متوقع";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        // رسائل خاصة للأخطاء الشائعة
        if (response.statusCode == 400) {
          if (errorMessage.contains("البريد الإلكتروني مسجل مسبقاً") || 
              (errorMessage.contains("email") && errorMessage.contains("already"))) {
            errorMessage = "البريد الإلكتروني مستخدم مسبقاً";
          } else if (errorMessage.contains("رقم الهاتف مسجل مسبقاً") || 
                     (errorMessage.contains("phone") && errorMessage.contains("already"))) {
            errorMessage = "رقم الهاتف مستخدم مسبقاً";
          } else {
            errorMessage = "بيانات غير صحيحة، حاول مرة أخرى";
          }
        }
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
// للتشخيص
      if (e.toString().contains('SocketException')) {
        return {"success": false, "message": "تعذر الوصول إلى الخادم. تأكد من أن الخادم يعمل على البورت 8080"};
      } else if (e.toString().contains('TimeoutException')) {
        return {"success": false, "message": "انتهت مهلة الاتصال. تحقق من اتصال الإنترنت"};
      } else {
        return {"success": false, "message": "خطأ في التسجيل: $e"};
      }
    }
  }

  // جلب معلومات المستخدم
  static Future<Map<String, dynamic>> getUserProfile(String token) async {
    final url = Uri.parse('$currentBaseUrl/auth/me');
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        return {"success": true, "data": responseData};
      } else {
        return {
          "success": false,
          "message": responseData["message"] ?? "فشل في جلب الملف الشخصي"
        };
      }
    } catch (e) {
      return {"success": false, "message": "تعذر الاتصال بالخادم"};
    }
  }

  // تحديث معلومات المستخدم - TODO: Implement in backend
  static Future<Map<String, dynamic>> updateUserProfile({
    required String token,
    String? name,
    String? email,
    String? phone,
  }) async {
    // TODO: Add user profile update endpoint to backend
    return {"success": false, "message": "تحديث الملف الشخصي غير متاح حالياً"};
  }

  // جلب النقاط والكوبونات - TODO: Implement in backend  
  static Future<Map<String, dynamic>> getUserRewards(String token) async {
    // TODO: Add user rewards endpoint to backend
    return {"success": false, "message": "نظام المكافآت غير متاح حالياً"};
  }

  // إضافة عنوان جديد للمستخدم (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> addUserAddress({
    required String token,
    required String name,
    required String province, // Changed from governorate to province
    required String district,
    required String neighborhood,
    required String landmark,
    bool isDefault = false,
    String? detailedAddress,
    String? buildingNumber,
    String? floorNumber,
    String? apartmentNumber,
    String? phoneNumber,
    double? latitude,
    double? longitude,
    String? addressType,
    // 🆕 Region System Fields
    String? regionId,
    String? regionName,
    String? regionNameAr,
    int? regionLevel,
    bool? regionIsActive,
    double? deliveryFee,
    double? minimumOrder,
    double? maxDistanceKm,
    double? pricePerKm,
  }) async {
    print('🌐 بدء إضافة عنوان جديد...');
    print('📝 اسم العنوان: $name');
    print('📍 التفاصيل: $province - $district - $neighborhood');
    
    // Get user ID from session service  
    final userId = SessionService.instance.currentUserId;
    if (userId == null) {
      print('❌ لم يتم العثور على معرف المستخدم');
      return {"success": false, "message": "لم يتم العثور على معرف المستخدم"};
    }
    
    final url = Uri.parse('$currentBaseUrl/users/$userId/addresses'); // Fixed URL to match backend
    print('📡 URL: $url');
    print('🔑 Token: ${token.length > 20 ? token.substring(0, 20) + '...' : token}');
    print('🆔 User ID: $userId');
    
    try {
      final Map<String, dynamic> requestData = {
        'name': name,
        'province': province, // Fixed field name
        'district': district,
        'neighborhood': neighborhood,
        'landmark': landmark,
        'is_default': isDefault,
      };
      
      // إضافة الحقول الاختيارية إذا كانت متوفرة
      if (detailedAddress != null && detailedAddress.isNotEmpty) {
        requestData['detailed_address'] = detailedAddress;
      }
      if (buildingNumber != null && buildingNumber.isNotEmpty) {
        requestData['building_number'] = buildingNumber;
      }
      if (floorNumber != null && floorNumber.isNotEmpty) {
        requestData['floor_number'] = floorNumber;
      }
      if (apartmentNumber != null && apartmentNumber.isNotEmpty) {
        requestData['apartment_number'] = apartmentNumber;
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        requestData['phone_number'] = phoneNumber;
      }
      if (latitude != null) {
        requestData['latitude'] = latitude;
      }
      if (longitude != null) {
        requestData['longitude'] = longitude;
      }
      if (addressType != null && addressType.isNotEmpty) {
        requestData['address_type'] = addressType;
      }
      
      // 🆕 Region System Fields
      if (regionId != null && regionId.isNotEmpty) {
        requestData['region_id'] = regionId;
      }
      if (regionName != null && regionName.isNotEmpty) {
        requestData['region_name'] = regionName;
      }
      if (regionNameAr != null && regionNameAr.isNotEmpty) {
        requestData['region_name_ar'] = regionNameAr;
      }
      if (regionLevel != null) {
        requestData['region_level'] = regionLevel;
      }
      if (regionIsActive != null) {
        requestData['region_is_active'] = regionIsActive;
      }
      if (deliveryFee != null) {
        requestData['delivery_fee'] = deliveryFee;
      }
      if (minimumOrder != null) {
        requestData['minimum_order'] = minimumOrder;
      }
      if (maxDistanceKm != null) {
        requestData['max_distance_km'] = maxDistanceKm;
      }
      if (pricePerKm != null) {
        requestData['price_per_km'] = pricePerKm;
      }
      
      final requestBody = jsonEncode(requestData);
      print('📋 Request Body: $requestBody');
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 201) { // Backend returns 201 for creation
        return {"success": true, "data": responseData};
      } else {
        // معالجة محسنة لرسائل الخطأ
        String errorMessage = "فشل في إضافة العنوان";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        print('❌ فشل في إضافة العنوان: $errorMessage');
        print('📄 تفاصيل الاستجابة: $responseData');
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
      print('💥 خطأ في addUserAddress: $e');
      return {"success": false, "message": "خطأ في الاتصال: $e"};
    }
  }

  // تحديث عنوان موجود (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> updateUserAddress({
    required String token,
    required String addressId,
    required String name,
    required String province, // Changed from governorate to province
    required String district,
    required String neighborhood,
    required String landmark,
    bool isDefault = false,
    String? detailedAddress,
    String? buildingNumber,
    String? floorNumber,
    String? apartmentNumber,
    String? phoneNumber,
    double? latitude,
    double? longitude,
    String? addressType,
  }) async {
    // Get user ID from session service  
    final userId = SessionService.instance.currentUserId;
    if (userId == null) {
      return {"success": false, "message": "لم يتم العثور على معرف المستخدم"};
    }
    
    final url = Uri.parse('$currentBaseUrl/users/$userId/addresses/$addressId'); // Fixed URL to match backend
try {
      final Map<String, dynamic> requestData = {
        'name': name,
        'province': province, // Fixed field name
        'district': district,
        'neighborhood': neighborhood,
        'landmark': landmark,
        'is_default': isDefault,
      };
      
      // إضافة الحقول الاختيارية إذا كانت متوفرة
      if (detailedAddress != null && detailedAddress.isNotEmpty) {
        requestData['detailed_address'] = detailedAddress;
      }
      if (buildingNumber != null && buildingNumber.isNotEmpty) {
        requestData['building_number'] = buildingNumber;
      }
      if (floorNumber != null && floorNumber.isNotEmpty) {
        requestData['floor_number'] = floorNumber;
      }
      if (apartmentNumber != null && apartmentNumber.isNotEmpty) {
        requestData['apartment_number'] = apartmentNumber;
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        requestData['phone_number'] = phoneNumber;
      }
      if (latitude != null) {
        requestData['latitude'] = latitude;
      }
      if (longitude != null) {
        requestData['longitude'] = longitude;
      }
      if (addressType != null && addressType.isNotEmpty) {
        requestData['address_type'] = addressType;
      }
      
      final requestBody = jsonEncode(requestData);
final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        return {"success": true, "data": responseData};
      } else {
        String errorMessage = "فشل في تحديث العنوان";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
return {"success": false, "message": "تعذر الاتصال بالخادم"};
    }
  }

  // حذف عنوان (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> deleteUserAddress({
    required String token,
    required String addressId,
  }) async {
    // Get user ID from session service  
    final userId = SessionService.instance.currentUserId;
    if (userId == null) {
      return {"success": false, "message": "لم يتم العثور على معرف المستخدم"};
    }
    
    final url = Uri.parse('$currentBaseUrl/users/$userId/addresses/$addressId'); // Fixed URL to match backend
try {
      final response = await http.delete(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 204) { // Backend returns 204 for successful deletion
        return {"success": true, "data": {"message": "تم حذف العنوان بنجاح"}};
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        String errorMessage = "فشل في حذف العنوان";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
return {"success": false, "message": "تعذر الاتصال بالخادم"};
    }
  }

  // تحديد عنوان كافتراضي (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> setDefaultAddress({
    required String token,
    required String addressId,
  }) async {
    // Get user ID from session service  
    final userId = SessionService.instance.currentUserId;
    if (userId == null) {
      return {"success": false, "message": "لم يتم العثور على معرف المستخدم"};
    }
    
    final url = Uri.parse('$currentBaseUrl/users/$userId/addresses/$addressId/set-default'); // Fixed endpoint to match backend
try {
      final response = await http.put( // Backend uses PUT for set-default
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        return {"success": true, "data": responseData};
      } else {
        String errorMessage = "فشل في تحديد العنوان الافتراضي";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
return {"success": false, "message": "تعذر الاتصال بالخادم"};
    }
  }

  // جلب عناوين المستخدم (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> getUserAddresses(String token) async {
    print('🌐 بدء استدعاء getUserAddresses API...');
    
    // 🔧 تشخيص شامل لمعرف المستخدم
    final sessionService = SessionService.instance;
    print('🔍 Session Service Status:');
    print('   - isLoggedIn: ${sessionService.isLoggedIn}');
    print('   - isGuest: ${sessionService.isGuest}');
    print('   - currentUserId: ${sessionService.currentUserId}');
    print('   - currentUser: ${sessionService.currentUser}');
    
    // محاولة الحصول على userId من مصادر متعددة
    String? userId = sessionService.currentUserId;
    
    if (userId == null || userId.isEmpty) {
      // محاولة من currentUser
      final currentUser = sessionService.currentUser;
      if (currentUser != null) {
        userId = currentUser['userId'] ?? currentUser['user_id'] ?? currentUser['email'];
        print('📋 تم استخراج userId من currentUser: $userId');
      }
    }
    
    if (userId == null || userId.isEmpty) {
      print('❌ لم يتم العثور على معرف المستخدم في أي مصدر');
      print('🔍 تفاصيل SessionService للتشخيص:');
      print('   - AccessToken: ${sessionService.accessToken != null ? "موجود" : "غير موجود"}');
      print('   - IdToken: ${sessionService.idToken != null ? "موجود" : "غير موجود"}');
      return {"success": false, "message": "لم يتم العثور على معرف المستخدم - يرجى إعادة تسجيل الدخول"};
    }
    
    final url = Uri.parse('$currentBaseUrl/users/$userId/addresses');
    print('📡 URL: $url');
    print('🔑 Token: ${token.length > 20 ? token.substring(0, 20) + '...' : token}');
    print('🆔 User ID: $userId');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Raw Response: ${response.body}');
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        print('📋 تفاصيل الاستجابة: $responseData');
        
        // تحديد عدد العناوين بناءً على هيكل البيانات
        int addressCount = 0;
        if (responseData['addresses'] != null && responseData['addresses'] is List) {
          addressCount = (responseData['addresses'] as List).length;
        } else if (responseData['data'] != null) {
          if (responseData['data']['addresses'] != null && responseData['data']['addresses'] is List) {
            addressCount = (responseData['data']['addresses'] as List).length;
          }
        }
        
        print('📍 عدد العناوين: $addressCount');
        return {"success": true, "data": responseData};
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        print('❌ فشل استدعاء API - Status: ${response.statusCode}');
        print('📝 Response: ${response.body}');
        
        // معالجة محسنة لرسائل الخطأ
        String errorMessage = "فشل في جلب العناوين";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
      print('💥 خطأ في الاتصال: $e');
      return {"success": false, "message": "تعذر الاتصال بالخادم"};
    }
  }

  // دالة لاختبار الاتصال بالخادم
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      final url = Uri.parse("$currentBaseUrl/");
final response = await http.get(url).timeout(const Duration(seconds: 5));
if (response.statusCode == 200 || response.statusCode == 404) {
        return {"success": true, "message": "الخادم متصل ✅"};
      } else {
        return {"success": false, "message": "الخادم غير متاح (رمز: ${response.statusCode})"};
      }
    } catch (e) {
      return {"success": false, "message": "تعذر الوصول إلى الخادم: $e"};
    }
  }

  // الحصول على عنوان محدد
  static Future<Map<String, dynamic>> getAddress({
    required String token,
    required String addressId,
  }) async {
    // Get user ID from session service  
    final userId = SessionService.instance.currentUserId;
    if (userId == null) {
      return {"success": false, "message": "لم يتم العثور على معرف المستخدم"};
    }
    
    final url = Uri.parse('$currentBaseUrl/users/$userId/addresses/$addressId'); // Fixed URL to match backend
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        return {"success": true, "data": responseData};
      } else {
        String errorMessage = "فشل في جلب العنوان";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
      return {"success": false, "message": "تعذر الاتصال بالخادم"};
    }
  }

  // Generic POST method for general API calls
  static Future<Map<String, dynamic>> post({
    required String endpoint,
    required Map<String, dynamic> data,
    String? token,
  }) async {
    final url = Uri.parse('$currentBaseUrl$endpoint');
    
    try {
      final Map<String, String> headers = {
        'Content-Type': 'application/json',
      };
      
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
        print('📡 POST $endpoint مع مصادقة - Token: ${token.substring(0, 20)}...');
      } else {
        print('📡 POST $endpoint بدون مصادقة');
      }
      
      print('🌐 URL: $url');
      print('📤 البيانات: $data');
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(data),
      );

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Raw Response: ${response.body}');
      
      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {"success": true, "data": responseData};
      } else {
        String errorMessage = "Request failed";
        
        if (responseData.containsKey("message")) {
          errorMessage = responseData["message"];
        } else if (responseData.containsKey("detail")) {
          errorMessage = responseData["detail"];
        }
        
        print('❌ فشل الطلب - الخطأ: $errorMessage');
        return {
          "success": false,
          "message": errorMessage
        };
      }
    } catch (e) {
      print('🚨 خطأ في الاتصال: $e');
      return {"success": false, "message": "Connection error: $e"};
    }
  }
}
