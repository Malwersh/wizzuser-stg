import 'address_save_attempt_319.dart';
import 'address_book_api_319.dart';
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
      debugPrint(
        '✅ API Service with optimizations initialized (Frontend-only mode)',
      );
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

  static Future<Map<String, dynamic>> login(
    String identifier,
    String password,
  ) async {
    final url = Uri.parse("$currentBaseUrl/auth/login");
    // للتشخيص
    // للتشخيص

    try {
      final requestBody = jsonEncode({
        "identifier": identifier,
        "password": password,
      });
      // للتشخيص

      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 10)); // مهلة زمنية
      // للتشخيص
      // للتشخيص

      final responseData = jsonDecode(
        utf8.decode(response.bodyBytes),
      ); // لحل مشكلة الترميز
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

        return {"success": false, "message": errorMessage};
      }
    } catch (e) {
      // للتشخيص
      if (e.toString().contains('SocketException')) {
        return {
          "success": false,
          "message":
              "تعذر الوصول إلى الخادم. تأكد من أن الخادم يعمل على البورت 8080",
        };
      } else if (e.toString().contains('TimeoutException')) {
        return {
          "success": false,
          "message": "انتهت مهلة الاتصال. تحقق من اتصال الإنترنت",
        };
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
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'email': email.isEmpty ? null : email,
              'password': password,
              'phone': phone,
            }),
          )
          .timeout(const Duration(seconds: 10)); // مهلة زمنية
      // للتشخيص
      // للتشخيص

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 201) {
        // Backend returns 201 for registration
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
              (errorMessage.contains("email") &&
                  errorMessage.contains("already"))) {
            errorMessage = "البريد الإلكتروني مستخدم مسبقاً";
          } else if (errorMessage.contains("رقم الهاتف مسجل مسبقاً") ||
              (errorMessage.contains("phone") &&
                  errorMessage.contains("already"))) {
            errorMessage = "رقم الهاتف مستخدم مسبقاً";
          } else {
            errorMessage = "بيانات غير صحيحة، حاول مرة أخرى";
          }
        }

        return {"success": false, "message": errorMessage};
      }
    } catch (e) {
      // للتشخيص
      if (e.toString().contains('SocketException')) {
        return {
          "success": false,
          "message":
              "تعذر الوصول إلى الخادم. تأكد من أن الخادم يعمل على البورت 8080",
        };
      } else if (e.toString().contains('TimeoutException')) {
        return {
          "success": false,
          "message": "انتهت مهلة الاتصال. تحقق من اتصال الإنترنت",
        };
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
          "message": responseData["message"] ?? "فشل في جلب الملف الشخصي",
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
    String? idempotencyKey,
    bool saveToAddressBook = true,
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

      if (idempotencyKey != null)
        requestData['idempotency_key'] = idempotencyKey;
      requestData['save_to_address_book'] = saveToAddressBook;
      if (detailedAddress?.trim().isNotEmpty == true)
        requestData['fullAddress'] = detailedAddress!.trim();
      final key = await AddressSaveAttempt319.key(
        userId,
        requestData,
        suggested: idempotencyKey,
      );
      requestData['idempotency_key'] = key;
      final result = await AddressBookApi319.instance.request(
        method: 'POST',
        owner: userId,
        token: token,
        body: requestData,
      );
      if (result['success'] == true)
        await AddressSaveAttempt319.confirmed(userId, requestData, key);
      if (SessionService.instance.currentUserId != userId)
        return {
          'success': false,
          'message': 'تغيّرت الجلسة. أعد تسجيل الدخول.',
        };
      return result;
    } catch (e) {
      print('💥 خطأ في addUserAddress: $e');
      return {
        "success": false,
        "message": "تعذر تأكيد حفظ العنوان. أعد المحاولة للتحقق من النتيجة.",
      };
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

      final result = await AddressBookApi319.instance.request(
        method: 'PUT',
        owner: userId,
        token: token,
        addressId: addressId,
        body: requestData,
      );
      if (SessionService.instance.currentUserId != userId)
        return {'success': false, 'message': 'تغيّرت الجلسة.'};
      return result;
    } catch (e) {
      return {"success": false, "message": "تعذر الاتصال بالخادم"};
    }
  }

  // حذف عنوان (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> deleteUserAddress({
    required String token,
    required String addressId,
  }) async {
    final id = SessionService.instance.currentUserId;
    if (id == null)
      return {'success': false, 'message': 'سجل الدخول لإدارة العناوين.'};
    return AddressBookApi319.instance.request(
      method: 'DELETE',
      owner: id,
      token: token,
      addressId: addressId,
    );
  }

  // تحديد عنوان كافتراضي (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> setDefaultAddress({
    required String token,
    required String addressId,
  }) async {
    final id = SessionService.instance.currentUserId;
    if (id == null)
      return {'success': false, 'message': 'سجل الدخول لإدارة العناوين.'};
    return AddressBookApi319.instance.request(
      method: 'PUT',
      owner: id,
      token: token,
      addressId: addressId,
      setDefault: true,
    );
  }

  // جلب عناوين المستخدم (متوافق مع خادم الإنتاج)
  static Future<Map<String, dynamic>> getUserAddresses(String token) async {
    final id = SessionService.instance.currentUserId;
    if (id == null)
      return {'success': false, 'message': 'سجل الدخول لإدارة العناوين.'};
    return AddressBookApi319.instance.request(
      method: 'GET',
      owner: id,
      token: token,
    );
  }

  // دالة لاختبار الاتصال بالخادم
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      final url = Uri.parse("$currentBaseUrl/");
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 || response.statusCode == 404) {
        return {"success": true, "message": "الخادم متصل ✅"};
      } else {
        return {
          "success": false,
          "message": "الخادم غير متاح (رمز: ${response.statusCode})",
        };
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
    final owner = SessionService.instance.currentUserId;
    if (owner == null)
      return {'success': false, 'message': 'سجل الدخول لإدارة العناوين.'};
    return AddressBookApi319.instance.request(
      method: 'GET',
      owner: owner,
      token: token,
      addressId: addressId,
    );
  }

  // Generic POST method for general API calls
  static Future<Map<String, dynamic>> post({
    required String endpoint,
    required Map<String, dynamic> data,
    String? token,
  }) async {
    final url = Uri.parse('$currentBaseUrl$endpoint');

    try {
      final Map<String, String> headers = {'Content-Type': 'application/json'};

      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
        print(
          '📡 POST $endpoint مع مصادقة - Token: ${token.substring(0, 20)}...',
        );
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
        return {"success": false, "message": errorMessage};
      }
    } catch (e) {
      print('🚨 خطأ في الاتصال: $e');
      return {"success": false, "message": "Connection error: $e"};
    }
  }
}
