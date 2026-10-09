import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../config.dart';
import '../utils/validation_helper.dart';

/// خدمة المصادقة المحدثة - متوافقة مع النظام المتكامل الجديد
class AuthService {
  static String get _baseUrl => ApiConfig.baseUrl;

  /// تسجيل مستخدم جديد
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? countryCode,
    bool? termsAccepted,
    bool? privacyAccepted,
    bool? marketingConsent,
    DateTime? birthDate,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/register');
    
    try {
      final Map<String, dynamic> requestBody = {
        'name': name,
        'password': password,
        'country_code': countryCode ?? '+966',
        'terms_accepted': termsAccepted ?? true,
        'privacy_accepted': privacyAccepted ?? true,
        'marketing_consent': marketingConsent ?? false,
      };

      // إضافة الهاتف إذا وُجد مع تنسيقه بصيغة E.164
      if (phone.isNotEmpty) {
        // تنسيق رقم الهاتف بصيغة E.164 لـ AWS Cognito
        String formattedPhone = phone.trim();
        
        // إزالة أي أحرف غير رقمية أولاً
        String digitsOnly = formattedPhone.replaceAll(RegExp(r'[^\d]'), '');
        
        // تنسيق الرقم العراقي
        if (digitsOnly.length == 10 && digitsOnly.startsWith('7')) {
          // رقم يبدأ بـ 7 ويحتوي على 10 أرقام: 7901234567
          formattedPhone = '+964$digitsOnly';
        }
        else if (digitsOnly.length == 11 && digitsOnly.startsWith('07')) {
          // رقم يبدأ بـ 07 ويحتوي على 11 رقم: 07901234567
          formattedPhone = '+964${digitsOnly.substring(1)}';
        }
        else if (digitsOnly.length == 13 && digitsOnly.startsWith('964')) {
          // رقم يبدأ بـ 964: 9647901234567
          formattedPhone = '+$digitsOnly';
        }
        else {
          // إذا لم يكن بالصيغة المتوقعة، حاول تنسيقه كرقم عراقي
          if (digitsOnly.length >= 9) {
            // أخذ آخر 9 أرقام كرقم الهاتف العراقي
            String phoneDigits = digitsOnly.substring(digitsOnly.length - 9);
            if (phoneDigits.startsWith('7') || phoneDigits.startsWith('8') || phoneDigits.startsWith('9')) {
              formattedPhone = '+964$phoneDigits';
            } else {
              // إذا لم يبدأ بـ 7، 8، أو 9، ارجع للرقم الأصلي
              formattedPhone = phone;
            }
          } else {
            formattedPhone = phone; // ارجع للرقم الأصلي إذا كان قصير جداً
          }
        }
        
        requestBody['phone'] = formattedPhone;
        developer.log('📱 Phone number formatted: $phone -> $formattedPhone', name: 'AUTH_SERVICE');
      }

      // إضافة البريد الإلكتروني إذا وُجد
      if (email.isNotEmpty) {
        requestBody['email'] = email;
      }

      // إضافة تاريخ الميلاد إذا وُجد
      if (birthDate != null) {
        requestBody['birth_date'] = birthDate.toIso8601String().split('T')[0];
      }

      developer.log('📡 Making request to: $url', name: 'AUTH_SERVICE');
      developer.log('📝 Request body: ${jsonEncode(requestBody)}', name: 'AUTH_SERVICE');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('Register Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إنشاء الحساب بنجاح",
            "user_id": responseData["user_id"],
            "requires_verification": responseData["requires_verification"] ?? false,
            "resend_verification": responseData["resend_verification"] ?? false,
            "email_updated": responseData["email_updated"] ?? false,
            "email": responseData["email"] ?? email,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "حدث خطأ أثناء التسجيل"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Register Error: $e', name: 'AUTH_SERVICE');
      developer.log('❌ Error type: ${e.runtimeType}', name: 'AUTH_SERVICE');
      
      String errorMessage = "خطأ في الاتصال: تحقق من الإنترنت وحاول مرة أخرى";
      
      if (e.toString().contains('HandshakeException') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('Connection failed')) {
        errorMessage = "خطأ في الاتصال الآمن: تحقق من إعدادات الشبكة";
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = "انتهت مهلة الاتصال: تحقق من سرعة الإنترنت";
      } else if (e.toString().contains('XMLHttpRequest')) {
        errorMessage = "خطأ في المتصفح: تحقق من إعدادات CORS";
      }
      
      return {
        "success": false,
        "error": errorMessage,
        "technical_error": e.toString(),
      };
    }
  }

  /// تسجيل مستخدم جديد بالإيميل فقط
  static Future<Map<String, dynamic>> registerWithEmail({
    required String name,
    required String email,
    required String password,
    bool? termsAccepted,
    bool? privacyAccepted,
    bool? marketingConsent,
    DateTime? birthDate,
    String? gender,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/register');
    
    try {
      final Map<String, dynamic> requestBody = {
        'name': name,
        'email': email,
        'password': password,
        'registrationType': 'email',
        'termsAccepted': termsAccepted ?? true,
        'privacyAccepted': privacyAccepted ?? true,
        'marketingConsent': marketingConsent ?? false,
      };

      if (birthDate != null) {
        requestBody['birthDate'] = birthDate.toIso8601String().split('T')[0];
      }

      if (gender != null) {
        requestBody['gender'] = gender;
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('Register with Email Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إنشاء الحساب بنجاح",
            "tempUserId": responseData["tempUserId"],
            "emailVerificationRequired": responseData["emailVerificationRequired"] ?? true,
            "phoneVerificationRequired": responseData["phoneVerificationRequired"] ?? false,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "حدث خطأ أثناء التسجيل"
          };
        }
      } else if (response.statusCode == 409) {
        // حالة خاصة للحسابات المؤقتة أو المكررة بالإيميل
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['requiresVerification'] == true) {
          // المستخدم موجود ويحتاج للتحقق
          return {
            "success": false,
            "error": responseData["error"] ?? "يوجد حساب غير مؤكد",
            "requiresVerification": true,
            "tempUserId": responseData["tempUserId"],
            "phoneVerificationRequired": responseData["phoneVerificationRequired"] ?? false,
            "emailVerificationRequired": responseData["emailVerificationRequired"] ?? false,
            "message": responseData["message"] ?? "يرجى التحقق من بريدك الإلكتروني أو طلب إعادة إرسال رمز التحقق",
          };
        } else if (responseData['shouldLogin'] == true) {
          // حساب مسجل ومؤكد - توجيه لتسجيل الدخول
          return {
            "success": false,
            "error": responseData["error"] ?? "الحساب مسجل مسبقاً",
            "shouldLogin": true,
            "message": responseData["message"] ?? "يمكنك تسجيل الدخول باستخدام هذا البريد الإلكتروني"
          };
        } else {
          // حالة أخرى
          return {
            "success": false,
            "error": responseData["error"] ?? "الحساب مسجل مسبقاً"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('Register with Email Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال: تحقق من الإنترنت وحاول مرة أخرى"
      };
    }
  }

  /// تسجيل مستخدم جديد بالهاتف فقط
  static Future<Map<String, dynamic>> registerWithPhone({
    required String name,
    required String phone,
    required String password,
    String? countryCode,
    bool? termsAccepted,
    bool? privacyAccepted,
    bool? marketingConsent,
    DateTime? birthDate,
    String? gender,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/register');
    
    try {
      // تنسيق رقم الهاتف العراقي
      String formattedPhone = phone.trim();
      String digitsOnly = formattedPhone.replaceAll(RegExp(r'[^\d]'), '');
      
      if (digitsOnly.length == 10 && digitsOnly.startsWith('7')) {
        formattedPhone = '+964$digitsOnly';
      } else if (digitsOnly.length == 11 && digitsOnly.startsWith('07')) {
        formattedPhone = '+964${digitsOnly.substring(1)}';
      } else if (digitsOnly.length == 13 && digitsOnly.startsWith('964')) {
        formattedPhone = '+$digitsOnly';
      }

      final Map<String, dynamic> requestBody = {
        'name': name,
        'phone': formattedPhone,
        'password': password,
        'registrationType': 'phone',
        'countryCode': countryCode ?? '+964',
        'termsAccepted': termsAccepted ?? true,
        'privacyAccepted': privacyAccepted ?? true,
        'marketingConsent': marketingConsent ?? false,
      };

      if (birthDate != null) {
        requestBody['birthDate'] = birthDate.toIso8601String().split('T')[0];
      }

      if (gender != null) {
        requestBody['gender'] = gender;
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('Register with Phone Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إنشاء الحساب بنجاح",
            "tempUserId": responseData["tempUserId"],
            "phoneVerificationRequired": responseData["phoneVerificationRequired"] ?? true,
            "emailVerificationRequired": responseData["emailVerificationRequired"] ?? false,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "حدث خطأ أثناء التسجيل"
          };
        }
      } else if (response.statusCode == 409) {
        // حالة خاصة للحسابات المؤقتة أو المكررة
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['requiresVerification'] == true) {
          // المستخدم موجود ويحتاج للتحقق
          return {
            "success": false,
            "error": responseData["error"] ?? "يوجد حساب غير مؤكد",
            "requiresVerification": true,
            "tempUserId": responseData["tempUserId"],
            "phoneVerificationRequired": responseData["phoneVerificationRequired"] ?? false,
            "emailVerificationRequired": responseData["emailVerificationRequired"] ?? false,
            "message": responseData["message"], // إضافة رسالة النجاح
          };
        } else {
          // حساب مسجل مسبقاً
          return {
            "success": false,
            "error": responseData["error"] ?? "الحساب مسجل مسبقاً"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('Register with Phone Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال: تحقق من الإنترنت وحاول مرة أخرى"
      };
    }
  }

  /// تسجيل الدخول
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/login');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': username,  // تغيير من identifier إلى username
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      developer.log('Login Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "data": {
              "access_token": responseData["accessToken"] ?? responseData["tokens"]?["accessToken"] ?? 'temp_token',
              "id_token": responseData["idToken"] ?? responseData["tokens"]?["idToken"] ?? responseData["accessToken"] ?? 'temp_token',
              "refresh_token": responseData["refreshToken"] ?? responseData["tokens"]?["refreshToken"] ?? 'temp_token',
              "token_type": responseData["token_type"] ?? 'Bearer',
              "user": Map<String, dynamic>.from(responseData["user"] ?? {}),
              "user_id": responseData["user"]?["userId"],
            }
          };
        } else {
          // Forward all error information including verification requirements
          return {
            "success": false,
            "message": responseData["error"] ?? "حدث خطأ أثناء تسجيل الدخول",
            "requiresVerification": responseData["requiresVerification"],
            "emailVerificationRequired": responseData["emailVerificationRequired"],
            "phoneVerificationRequired": responseData["phoneVerificationRequired"],
            "tempUserId": responseData["tempUserId"],
          };
        }
      } else if (response.statusCode == 403) {
        // حالة خاصة للمستخدمين غير المؤكدين
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "حسابك غير مؤكد",
          "requiresVerification": responseData["requiresVerification"] ?? false,
          "emailVerificationRequired": responseData["emailVerificationRequired"] ?? false,
          "phoneVerificationRequired": responseData["phoneVerificationRequired"] ?? false,
          "tempUserId": responseData["tempUserId"],
          "error": responseData["error"], // إضافة error منفصل
        };
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}",
          "requiresVerification": responseData["requiresVerification"],
          "emailVerificationRequired": responseData["emailVerificationRequired"],
          "phoneVerificationRequired": responseData["phoneVerificationRequired"],
          "tempUserId": responseData["tempUserId"],
        };
      }
    } catch (e) {
      developer.log('Login Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "message": "خطأ في الاتصال: $e"
      };
    }
  }

  /// تسجيل الدخول بالإيميل
  static Future<Map<String, dynamic>> emailLogin({
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/email-login');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      developer.log('Email Login Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "data": {
              "access_token": responseData["accessToken"] ?? responseData["tokens"]?["accessToken"] ?? 'temp_token',
              "id_token": responseData["idToken"] ?? responseData["tokens"]?["idToken"] ?? responseData["accessToken"] ?? 'temp_token',
              "refresh_token": responseData["refreshToken"] ?? responseData["tokens"]?["refreshToken"] ?? 'temp_token',
              "token_type": "Bearer",
              "user": Map<String, dynamic>.from(responseData["user"] ?? {}),
              "user_id": responseData["user"]?["userId"],
            }
          };
        } else {
          return {
            "success": false,
            "message": responseData["error"] ?? "حدث خطأ أثناء تسجيل الدخول",
            "needsVerification": responseData["needsVerification"],
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}",
          "needsVerification": responseData["needsVerification"],
        };
      }
    } catch (e) {
      developer.log('Email Login Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "message": "خطأ في الاتصال: $e"
      };
    }
  }

  /// تسجيل الدخول برقم الهاتف
  static Future<Map<String, dynamic>> phoneLogin({
    required String phone,
    required String password,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/phone-login');
    
    try {
      developer.log('📱 تسجيل دخول بالهاتف: $phone', name: 'AUTH_SERVICE');
      
      // تنسيق رقم الهاتف باستخدام ValidationHelper
      String formattedPhone;
      if (ValidationHelper.isValidIraqiPhoneInput(phone)) {
        formattedPhone = ValidationHelper.convertToFullPhoneNumber(phone);
      } else {
        // للتوافق مع الطرق القديمة
        formattedPhone = phone;
        String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
        
        if (digitsOnly.length == 10 && digitsOnly.startsWith('7')) {
          formattedPhone = '+964$digitsOnly';
        } else if (digitsOnly.length == 11 && digitsOnly.startsWith('07')) {
          formattedPhone = '+964${digitsOnly.substring(1)}';
        } else if (digitsOnly.length == 13 && digitsOnly.startsWith('964')) {
          formattedPhone = '+$digitsOnly';
        }
      }

      developer.log('📱 رقم الهاتف المنسق: $phone -> $formattedPhone', name: 'AUTH_SERVICE');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'phone': formattedPhone,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      developer.log('Phone Login Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "data": {
              "access_token": responseData["accessToken"] ?? responseData["tokens"]?["accessToken"] ?? 'temp_token',
              "id_token": responseData["idToken"] ?? responseData["tokens"]?["idToken"] ?? responseData["accessToken"] ?? 'temp_token',
              "refresh_token": responseData["refreshToken"] ?? responseData["tokens"]?["refreshToken"] ?? 'temp_token',
              "token_type": "Bearer",
              "user": Map<String, dynamic>.from(responseData["user"] ?? {}),
              "user_id": responseData["user"]?["userId"],
            }
          };
        } else {
          return {
            "success": false,
            "message": responseData["error"] ?? "حدث خطأ أثناء تسجيل الدخول",
            "needsVerification": responseData["needsVerification"],
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}",
          "needsVerification": responseData["needsVerification"],
        };
      }
    } catch (e) {
      developer.log('Phone Login Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "message": "خطأ في الاتصال: $e"
      };
    }
  }

  /// تأكيد التسجيل - محدث للنظام المتكامل
  static Future<Map<String, dynamic>> confirmSignUp({
    required String username,
    required String confirmationCode,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/verify-email');
    
    try {
      developer.log('🔍 AuthService.confirmSignUp called with:', name: 'AUTH_SERVICE');
      developer.log('  - URL: $url', name: 'AUTH_SERVICE');
      developer.log('  - tempUserId: $username', name: 'AUTH_SERVICE');
      developer.log('  - code: $confirmationCode', name: 'AUTH_SERVICE');
      
      final requestBody = {
        'tempUserId': username,  // البريد الإلكتروني للتسجيل الجديد
        'code': confirmationCode,  // رمز التحقق
      };
      
      developer.log('  - Request Body: $requestBody', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('Confirm Response: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('Response Body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        developer.log('Parsed Response: $responseData', name: 'AUTH_SERVICE');
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم تأكيد الحساب بنجاح",
            "userId": responseData["userId"],
            "verified": true,
            "account_active": true,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "خطأ في تأكيد الحساب",
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        developer.log('Error Response: $responseData', name: 'AUTH_SERVICE');
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}",
          "error_code": responseData["error_code"]
        };
      }
    } catch (e) {
      developer.log('Confirm SignUp Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال: $e"
      };
    }
  }

  /// تأكيد التسجيل الآمن (النظام الجديد)
  static Future<Map<String, dynamic>> confirmSignUpSecure({
    required String tempUserId,
    required String confirmationCode,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/confirm-secure');
    
    try {
      developer.log('🔒 Secure Confirmation request for temp_user_id: $tempUserId', name: 'AUTH_SERVICE');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': tempUserId, // استخدام temp_user_id
          'confirmation_code': confirmationCode,
        }),
      ).timeout(const Duration(seconds: 15));

      developer.log('🔒 Secure Confirmation Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": true,
          "message": responseData["message"] ?? "تم تأكيد الحساب بنجاح",
          "user_id": responseData["user_id"], // معرف المستخدم الحقيقي
          "email_verified": responseData["email_verified"] ?? true,
        };
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في التحقق"
        };
      }
    } catch (e) {
      developer.log('🔒 Secure Confirmation Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال: تحقق من الإنترنت وحاول مرة أخرى"
      };
    }
  }

  /// تأكيد تغيير البريد الإلكتروني (تحديث البريد في قاعدة البيانات بعد التحقق من الرمز)
  static Future<Map<String, dynamic>> confirmEmailChange({
    required String userId,
    required String newEmail,
    required String confirmationCode,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/confirm-email-change');
    
    try {
      developer.log('📧 Confirming email change for user: $userId to: $newEmail', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'new_email': newEmail,
          'code': confirmationCode,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى');
        },
      );

      developer.log('📥 Confirm Email Change Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم تأكيد وتحديث البريد الإلكتروني بنجاح",
            "new_email": newEmail,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "خطأ في تأكيد تغيير البريد الإلكتروني"
          };
        }
      } else if (response.statusCode == 404) {
        // الـ API الجديد غير متاح، استخدم الطريقة القديمة
        throw Exception('API_NOT_AVAILABLE');
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Confirm Email Change Error: $e', name: 'AUTH_SERVICE');
      
      if (e.toString().contains('API_NOT_AVAILABLE')) {
        // رمي نفس الاستثناء للـ fallback
        rethrow;
      }
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('انتهت مهلة')) {
        errorMessage = "انتهت مهلة الاتصال - تحقق من الإنترنت وحاول مرة أخرى";
      } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        errorMessage = "مشكلة في الاتصال بالإنترنت - تحقق من الاتصال وحاول مرة أخرى";
      } else {
        errorMessage = "خطأ في الاتصال - يرجى المحاولة مرة أخرى";
      }
      
      return {
        "success": false,
        "error": errorMessage
      };
    }
  }

  /// إعادة إرسال رمز التأكيد
  static Future<Map<String, dynamic>> resendConfirmationCode({
    required String username,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/resend-code');
    
    try {
      developer.log('📤 Resending confirmation code for: $username', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': username,  // تحديث ليدعم email
        }),
      ).timeout(
        const Duration(seconds: 30), // زيادة timeout
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى');
        },
      );

      developer.log('📥 Resend Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData["success"] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إعادة إرسال رمز التأكيد"
          };
        } else {
          return {
            "success": false,
            "message": responseData["error"] ?? "فشل في إعادة الإرسال"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Resend Error: $e', name: 'AUTH_SERVICE');
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('انتهت مهلة')) {
        errorMessage = "انتهت مهلة الاتصال - تحقق من الإنترنت وحاول مرة أخرى";
      } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        errorMessage = "مشكلة في الاتصال بالإنترنت - تحقق من الاتصال وحاول مرة أخرى";
      } else {
        errorMessage = "خطأ في الاتصال - يرجى المحاولة مرة أخرى";
      }
      
      return {
        "success": false,
        "message": errorMessage
      };
    }
  }

  /// طلب إعادة تعيين كلمة المرور
  /// طلب إعادة تعيين كلمة المرور
  static Future<Map<String, dynamic>> requestPasswordReset({
    required String username,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/forgot-password');
    
    try {
      developer.log('🔐 AuthService.requestPasswordReset called with:', name: 'AUTH_SERVICE');
      developer.log('  - username: $username', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': username,
        }),
      ).timeout(const Duration(seconds: 15));

      developer.log('Password Reset Request Response: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('Response Body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": responseData["success"] ?? true,
          "message": responseData["message"] ?? "تم إرسال رمز الاستعادة",
          "resetToken": responseData["resetToken"], // For phone users
          "userType": responseData["userType"], // 'email' or 'phone'
        };
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "خطأ في الخادم"
        };
      }
    } catch (e) {
      developer.log('Password Reset Request Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "message": "خطأ في الاتصال: $e"
      };
    }
  }

  /// تأكيد إعادة تعيين كلمة المرور
  static Future<Map<String, dynamic>> confirmPasswordReset({
    required String username,
    required String confirmationCode,
    required String newPassword,
    String? resetToken, // Required for phone users
  }) async {
    final url = Uri.parse('$_baseUrl/auth/confirm-forgot-password');
    
    try {
      developer.log('🔐 AuthService.confirmPasswordReset called with:', name: 'AUTH_SERVICE');
      developer.log('  - username: $username', name: 'AUTH_SERVICE');
      developer.log('  - confirmationCode: $confirmationCode', name: 'AUTH_SERVICE');
      developer.log('  - resetToken: ${resetToken ?? 'null'}', name: 'AUTH_SERVICE');
      
      final requestBody = {
        'username': username,
        'confirmationCode': confirmationCode,
        'newPassword': newPassword,
      };
      
      // Add resetToken for phone users
      if (resetToken != null) {
        requestBody['resetToken'] = resetToken;
      }
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('Password Reset Confirmation Response: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('Response Body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": responseData["success"] ?? true,
          "message": responseData["message"] ?? "تم تغيير كلمة المرور بنجاح"
        };
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "خطأ في الخادم"
        };
      }
    } catch (e) {
      developer.log('Password Reset Confirmation Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "message": "خطأ في الاتصال: $e"
      };
    }
  }

  /// التحقق من صحة الخادم
  static Future<bool> checkServerHealth() async {
    try {
      final url = Uri.parse('$_baseUrl/health');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// تسجيل الخروج
  static Future<Map<String, dynamic>> logout() async {
    try {
      return {
        "success": true,
        "message": "تم تسجيل الخروج بنجاح"
      };
    } catch (e) {
      return {
        "success": false,
        "message": "خطأ في تسجيل الخروج: $e"
      };
    }
  }

  /// الحصول على ملف المستخدم
  static Future<Map<String, dynamic>> getUserProfile() async {
    try {
      return {
        "success": true,
        "data": {
          "user_id": "temp_user_id",
          "name": "المستخدم",
          "email": "user@example.com"
        }
      };
    } catch (e) {
      return {
        "success": false,
        "message": "خطأ في الحصول على بيانات المستخدم: $e"
      };
    }
  }

  /// تحديث ملف المستخدم
  static Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? email,
    String? phone,
    DateTime? birthDate,
  }) async {
    try {
      return {
        "success": true,
        "message": "تم تحديث الملف الشخصي بنجاح"
      };
    } catch (e) {
      return {
        "success": false,
        "message": "خطأ في تحديث الملف الشخصي: $e"
      };
    }
  }

  /// تغيير كلمة المرور
  static Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      return {
        "success": true,
        "message": "تم تغيير كلمة المرور بنجاح"
      };
    } catch (e) {
      return {
        "success": false,
        "message": "خطأ في تغيير كلمة المرور: $e"
      };
    }
  }

  /// حذف الحساب
  static Future<Map<String, dynamic>> deleteAccount({
    required String password,
  }) async {
    try {
      return {
        "success": true,
        "message": "تم حذف الحساب بنجاح"
      };
    } catch (e) {
      return {
        "success": false,
        "message": "خطأ في حذف الحساب: $e"
      };
    }
  }

  /// تحديث البريد الإلكتروني مع التحقق من كلمة المرور وإرسال رمز التحقق
  static Future<Map<String, dynamic>> changeEmailWithPasswordVerification({
    required String userId,
    required String newEmail,
    required String currentPassword,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/change-email-with-verification');
    
    try {
      developer.log('📧 Changing email for user: $userId to: $newEmail with password verification', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'new_email': newEmail,
          'current_password': currentPassword,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى');
        },
      );

      developer.log('📥 Change Email Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم تحديث البريد الإلكتروني وإرسال رمز تحقق جديد",
            "new_email": newEmail,
            "requires_verification": true,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "خطأ في تحديث البريد الإلكتروني"
          };
        }
      } else if (response.statusCode == 404) {
        // الـ API الجديد غير متاح، نرمي exception لاستخدام الـ fallback
        throw Exception('API not available - fallback to old API');
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Change Email Error: $e', name: 'AUTH_SERVICE');
      
      // إذا كان الخطأ في عدم وجود الـ API (404)، نرمي exception لنستخدم fallback
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        throw Exception('API not available - fallback to old API');
      }
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('انتهت مهلة')) {
        errorMessage = "انتهت مهلة الاتصال - تحقق من الإنترنت وحاول مرة أخرى";
      } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        errorMessage = "مشكلة في الاتصال بالإنترنت - تحقق من الاتصال وحاول مرة أخرى";
      } else {
        errorMessage = "خطأ في الاتصال - يرجى المحاولة مرة أخرى";
      }
      
      return {
        "success": false,
        "error": errorMessage
      };
    }
  }

  /// تحديث البريد الإلكتروني وإعادة إرسال رمز التحقق (للمستخدمين المؤقتين)
  static Future<Map<String, dynamic>> updateEmailAndResendCode({
    required String userId,
    required String newEmail,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/update-contact');
    
    try {
      developer.log('📧 Updating email for temp user: $userId to: $newEmail', name: 'AUTH_SERVICE');
      
      final response = await http.put(  // تغيير من POST إلى PUT حسب template.yaml
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'tempUserId': userId,  // تصحيح parameter name
          'newEmail': newEmail,   // تصحيح parameter name
        }),
      ).timeout(
        const Duration(seconds: 30), // زيادة timeout
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى');
        },
      );

      developer.log('📥 Update Email Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم تحديث البريد الإلكتروني وإرسال رمز تحقق جديد",
            "new_email": newEmail, // إرجاع البريد الجديد للتأكيد
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "خطأ في تحديث البريد الإلكتروني"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Update Email Error: $e', name: 'AUTH_SERVICE');
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('انتهت مهلة')) {
        errorMessage = "انتهت مهلة الاتصال - تحقق من الإنترنت وحاول مرة أخرى";
      } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        errorMessage = "مشكلة في الاتصال بالإنترنت - تحقق من الاتصال وحاول مرة أخرى";
      } else {
        errorMessage = "خطأ في الاتصال - يرجى المحاولة مرة أخرى";
      }
      
      return {
        "success": false,
        "error": errorMessage
      };
    }
  }

  /// تحديث البريد الإلكتروني للمستخدمين المسجلين بـ Cognito (إنشاء حساب جديد)
  static Future<Map<String, dynamic>> updateCognitoEmail({
    required String userId,
    required String newEmail,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/update-cognito-email');
    
    try {
      developer.log('📧 Updating Cognito email for user: $userId to: $newEmail', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'userId': userId,
          'newEmail': newEmail,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى');
        },
      );

      developer.log('📥 Update Cognito Email Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إرسال رمز التحقق إلى البريد الجديد",
            "newEmail": newEmail,
            "cognitoUserId": responseData["cognitoUserId"],
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "خطأ في إنشاء الحساب الجديد"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Update Cognito Email Error: $e', name: 'AUTH_SERVICE');
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('انتهت مهلة')) {
        errorMessage = "انتهت مهلة الاتصال - تحقق من الإنترنت وحاول مرة أخرى";
      } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        errorMessage = "مشكلة في الاتصال بالإنترنت - تحقق من الاتصال وحاول مرة أخرى";
      } else {
        errorMessage = "خطأ في الاتصال - يرجى المحاولة مرة أخرى";
      }
      
      return {
        "success": false,
        "error": errorMessage
      };
    }
  }

  /// إرسال رمز تحقق للبريد الجديد بدون تحديث البريد في قاعدة البيانات (API آمن)
  static Future<Map<String, dynamic>> sendVerificationCodeToNewEmail({
    required String userId,
    required String newEmail,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/send-verification-to-new-email');
    
    try {
      developer.log('📧 Sending verification code to new email: $newEmail for user: $userId', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'new_email': newEmail,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى');
        },
      );

      developer.log('📥 Send Verification Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إرسال رمز التحقق إلى البريد الجديد",
            "new_email": newEmail,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "خطأ في إرسال رمز التحقق"
          };
        }
      } else if (response.statusCode == 404) {
        // الـ API الجديد غير متاح، ارجع خطأ خاص للـ fallback
        throw Exception('API_NOT_AVAILABLE');
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Send Verification Error: $e', name: 'AUTH_SERVICE');
      
      if (e.toString().contains('API_NOT_AVAILABLE')) {
        // رمي نفس الاستثناء للـ fallback
        rethrow;
      }
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('انتهت مهلة')) {
        errorMessage = "انتهت مهلة الاتصال - تحقق من الإنترنت وحاول مرة أخرى";
      } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        errorMessage = "مشكلة في الاتصال بالإنترنت - تحقق من الاتصال وحاول مرة أخرى";
      } else {
        errorMessage = "خطأ في الاتصال - يرجى المحاولة مرة أخرى";
      }
      
      return {
        "success": false,
        "error": errorMessage
      };
    }
  }

  /// إعادة إرسال رمز التحقق للمستخدمين غير المؤكدين
  static Future<Map<String, dynamic>> resendCodeForUnconfirmedUser({
    required String email,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/resend-code');
    
    try {
      developer.log('📤 Resending verification code for: $email', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': email, // سيتم التعامل مع البريد الإلكتروني أو user_id في الباكند
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى');
        },
      );

      developer.log('📥 Resend Code Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData["success"] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إعادة إرسال رمز التحقق إلى بريدك الإلكتروني"
          };
        } else {
          return {
            "success": false,
            "message": responseData["error"] ?? "فشل في إعادة الإرسال"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "message": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ Resend Code Error: $e', name: 'AUTH_SERVICE');
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('انتهت مهلة')) {
        errorMessage = "انتهت مهلة الاتصال - تحقق من الإنترنت وحاول مرة أخرى";
      } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        errorMessage = "مشكلة في الاتصال بالإنترنت - تحقق من الاتصال وحاول مرة أخرى";
      } else {
        errorMessage = "خطأ في الاتصال - يرجى المحاولة مرة أخرى";
      }
      
      return {
        "success": false,
        "message": errorMessage
      };
    }
  }

  /// الحصول على user_id عن طريق البريد الإلكتروني للمستخدمين الموجودين
  static Future<Map<String, dynamic>> getUserIdByEmail({
    required String email,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/get-user-by-email');
    
    try {
      developer.log('📧 Looking up user_id for email: $email', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
        }),
      ).timeout(const Duration(seconds: 15));

      developer.log('📥 User lookup response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "user_id": responseData["user_id"],
            "email": responseData["email"],
            "email_verified": responseData["email_verified"],
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "لم يتم العثور على المستخدم"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('❌ User lookup error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال - يرجى المحاولة مرة أخرى"
      };
    }
  }

  /// 🔒 تسجيل مستخدم جديد بشكل آمن (النظام الجديد)
  /// تسجيل مستخدم جديد بالتنسيق الجديد المحدث
  static Future<Map<String, dynamic>> registerSecure({
    required String name,
    String? email,
    String? phone,
    required String password,
    String? countryCode,
    bool? termsAccepted,
    bool? privacyAccepted,
    bool? marketingConsent,
    DateTime? birthDate,
    String? gender,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/register');
    
    try {
      // تحديد نوع التسجيل بناءً على البيانات المتوفرة
      String registrationType;
      if (phone != null && phone.isNotEmpty) {
        registrationType = 'phone';
      } else if (email != null && email.isNotEmpty) {
        registrationType = 'email';
      } else {
        return {
          "success": false,
          "error": "يجب تقديم رقم الهاتف أو البريد الإلكتروني"
        };
      }

      final Map<String, dynamic> requestBody = {
        'name': name,
        'password': password,
        'registrationType': registrationType,
        'termsAccepted': termsAccepted ?? true,
        'privacyAccepted': privacyAccepted ?? true,
        'marketingConsent': marketingConsent ?? false,
      };

      // إضافة رقم الهاتف إذا كان التسجيل عن طريق الهاتف
      if (registrationType == 'phone' && phone != null && phone.isNotEmpty) {
        // تنسيق رقم الهاتف بصيغة E.164
        String formattedPhone = phone.trim();
        
        // إزالة أي أحرف غير رقمية أولاً
        String digitsOnly = formattedPhone.replaceAll(RegExp(r'[^\d]'), '');
        
        // تنسيق الرقم العراقي
        if (digitsOnly.length == 10 && digitsOnly.startsWith('7')) {
          // رقم يبدأ بـ 7 ويحتوي على 10 أرقام: 7901234567
          formattedPhone = '+964$digitsOnly';
        }
        else if (digitsOnly.length == 11 && digitsOnly.startsWith('07')) {
          // رقم يبدأ بـ 07 ويحتوي على 11 رقم: 07901234567
          formattedPhone = '+964${digitsOnly.substring(1)}';
        }
        else if (digitsOnly.length == 13 && digitsOnly.startsWith('964')) {
          // رقم يبدأ بـ 964: 9647901234567
          formattedPhone = '+$digitsOnly';
        }
        else {
          // إذا لم يكن بالصيغة المتوقعة، حاول تنسيقه كرقم عراقي
          if (digitsOnly.length >= 9) {
            // أخذ آخر 10 أرقام كرقم الهاتف العراقي (بما يتوافق مع الباك إند الجديد)
            String phoneDigits = digitsOnly.substring(digitsOnly.length - 10);
            if (phoneDigits.startsWith('7') || phoneDigits.startsWith('8') || phoneDigits.startsWith('9')) {
              formattedPhone = '+964$phoneDigits';
            } else {
              formattedPhone = phone;
            }
          } else {
            formattedPhone = phone;
          }
        }
        
        requestBody['phone'] = formattedPhone;
        requestBody['countryCode'] = countryCode ?? '+964';
        developer.log('📱 Phone registration: $phone -> $formattedPhone', name: 'AUTH_SERVICE');
      }

      // إضافة البريد الإلكتروني إذا كان التسجيل عن طريق الإيميل
      if (registrationType == 'email' && email != null && email.isNotEmpty) {
        requestBody['email'] = email;
        developer.log('📧 Email registration: $email', name: 'AUTH_SERVICE');
      }

      // إضافة الحقول الاختيارية
      if (birthDate != null) {
        requestBody['birthDate'] = birthDate.toIso8601String().split('T')[0];
      }

      if (gender != null) {
        requestBody['gender'] = gender;
      }

      developer.log('🔒 Registration request: ${jsonEncode(requestBody)}', name: 'AUTH_SERVICE');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('🔒 Registration Response: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('🔒 Response body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم إنشاء الحساب بنجاح",
            "tempUserId": responseData["tempUserId"],
            "phoneVerificationRequired": responseData["phoneVerificationRequired"] ?? false,
            "emailVerificationRequired": responseData["emailVerificationRequired"] ?? false,
            "requiresVerification": responseData["requiresVerification"] ?? false,
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "حدث خطأ أثناء التسجيل"
          };
        }
      } else if (response.statusCode == 409) {
        // حالة خاصة للحسابات المؤقتة أو المكررة
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['requiresVerification'] == true) {
          // المستخدم موجود ويحتاج للتحقق
          return {
            "success": false,
            "error": responseData["error"] ?? "يوجد حساب غير مؤكد",
            "requiresVerification": true,
            "tempUserId": responseData["tempUserId"],
            "phoneVerificationRequired": responseData["phoneVerificationRequired"] ?? false,
            "emailVerificationRequired": responseData["emailVerificationRequired"] ?? false,
          };
        } else {
          // حساب مسجل مسبقاً
          return {
            "success": false,
            "error": responseData["error"] ?? "الحساب مسجل مسبقاً"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('🔒 Registration Error: $e', name: 'AUTH_SERVICE');
      
      String errorMessage = "خطأ في الاتصال: تحقق من الإنترنت وحاول مرة أخرى";
      
      if (e.toString().contains('HandshakeException') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('Connection failed')) {
        errorMessage = "خطأ في الاتصال الآمن: تحقق من إعدادات الشبكة";
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = "انتهت مهلة الاتصال: تحقق من سرعة الإنترنت";
      } else if (e.toString().contains('XMLHttpRequest')) {
        errorMessage = "خطأ في المتصفح: تحقق من إعدادات CORS";
      }
      
      return {
        "success": false,
        "error": errorMessage,
        "technical_error": e.toString(),
      };
    }
  }

  /// إعادة إرسال رمز التحقق - محدث للنظام الجديد
  static Future<Map<String, dynamic>> resendVerificationCode({
    String? identifier, // البريد الإلكتروني أو رقم الهاتف (التنسيق الجديد)
    String? tempUserId, // معرف المستخدم المؤقت (للتوافق مع النظام القديم)
    String? type, // نوع التحقق (للتوافق مع النظام القديم)
  }) async {
    try {
      // Handle different parameter formats for backward compatibility
      if (tempUserId != null && type != null) {
        // Old format: tempUserId + type - use resend-verification endpoint
        final url = Uri.parse('$_baseUrl/auth/resend-code');
        
        developer.log('📱 AuthService.resendVerificationCode (old format) called with:', name: 'AUTH_SERVICE');
        developer.log('  - tempUserId: $tempUserId', name: 'AUTH_SERVICE');
        developer.log('  - type: $type', name: 'AUTH_SERVICE');
        
        final requestBody = {
          'tempUserId': tempUserId,
          'verificationType': type,
        };
        
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 15));

        developer.log('Resend Verification Response: ${response.statusCode}', name: 'AUTH_SERVICE');

        if (response.statusCode == 200) {
          final responseData = jsonDecode(utf8.decode(response.bodyBytes));
          
          if (responseData['success'] == true) {
            return {
              "success": true,
              "message": responseData["message"] ?? "تم إرسال رمز التحقق مرة أخرى",
            };
          } else {
            return {
              "success": false,
              "error": responseData["error"] ?? "فشل في إعادة إرسال الرمز"
            };
          }
        } else {
          final responseData = jsonDecode(utf8.decode(response.bodyBytes));
          return {
            "success": false,
            "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
          };
        }
      } else if (identifier != null) {
        // New format: للإيميل، لا نحتاج إعادة إرسال لأن Cognito يرسل تلقائياً
        // بدلاً من ذلك، ننصح المستخدم بالتحقق من البريد
        developer.log('🔄 Email verification: Cognito sends automatically', name: 'AUTH_SERVICE');
        
        return {
          "success": true,
          "message": "رمز التحقق تم إرساله تلقائياً إلى بريدك الإلكتروني. تحقق من صندوق الوارد والرسائل المهملة.",
        };
      } else {
        return {
          "success": false,
          "error": "معاملات غير صحيحة لإعادة إرسال رمز التحقق"
        };
      }
    } catch (e) {
      developer.log('Resend Verification Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال: $e"
      };
    }
  }

  /// تسجيل الدخول عبر Google
  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      developer.log('Starting Google Sign-In...', name: 'AUTH_SERVICE');
      
      // استدعاء API للتسجيل الاجتماعي
      final url = Uri.parse('$_baseUrl/auth/social');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'provider': 'google',
          'action': 'initiate_auth'
        }),
      );

      developer.log('Google Sign-In Response Status: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('Google Sign-In Response Body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true) {
          return {
            'success': true,
            'message': 'تم تسجيل الدخول عبر Google بنجاح',
            'provider': 'google',
            'auth_url': responseData['auth_url'], // رابط المصادقة
            'state': responseData['state'], // حالة الجلسة
            'user_id': responseData['user_id'],
            'user': responseData['user'],
          };
        } else {
          return {
            'success': false,
            'error': responseData['error'] ?? 'فشل في تسجيل الدخول عبر Google'
          };
        }
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'فشل في الاتصال بالخادم'
        };
      }
    } catch (e) {
      developer.log('Google Sign-In Error: $e', name: 'AUTH_SERVICE');
      return {
        'success': false,
        'error': 'فشل في تسجيل الدخول عبر Google: $e'
      };
    }
  }

  /// تسجيل الدخول عبر Facebook
  static Future<Map<String, dynamic>> signInWithFacebook() async {
    try {
      developer.log('Starting Facebook Sign-In...', name: 'AUTH_SERVICE');
      
      // استدعاء API للتسجيل الاجتماعي
      final url = Uri.parse('$_baseUrl/auth/social');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'provider': 'facebook',
          'action': 'initiate_auth'
        }),
      );

      developer.log('Facebook Sign-In Response Status: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('Facebook Sign-In Response Body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true) {
          return {
            'success': true,
            'message': 'تم تسجيل الدخول عبر Facebook بنجاح',
            'provider': 'facebook',
            'auth_url': responseData['auth_url'], // رابط المصادقة
            'state': responseData['state'], // حالة الجلسة
            'user_id': responseData['user_id'],
            'user': responseData['user'],
          };
        } else {
          return {
            'success': false,
            'error': responseData['error'] ?? 'فشل في تسجيل الدخول عبر Facebook'
          };
        }
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'فشل في الاتصال بالخادم'
        };
      }
    } catch (e) {
      developer.log('Facebook Sign-In Error: $e', name: 'AUTH_SERVICE');
      return {
        'success': false,
        'error': 'فشل في تسجيل الدخول عبر Facebook: $e'
      };
    }
  }

  /// إكمال تسجيل الدخول الاجتماعي بعد العودة من OAuth
  static Future<Map<String, dynamic>> completeSocialAuth({
    required String provider,
    required String code,
    required String state,
  }) async {
    try {
      developer.log('Completing social auth for $provider...', name: 'AUTH_SERVICE');
      
      final url = Uri.parse('$_baseUrl/auth/social/callback');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'provider': provider,
          'code': code,
          'state': state,
        }),
      );

      developer.log('Social Auth Completion Response Status: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('Social Auth Completion Response Body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true) {
          return {
            'success': true,
            'message': responseData['message'] ?? 'تم تسجيل الدخول بنجاح',
            'provider': provider,
            'user_id': responseData['user_id'],
            'access_token': responseData['access_token'],
            'refresh_token': responseData['refresh_token'],
            'id_token': responseData['id_token'],
            'user': responseData['user'],
            'identity_id': responseData['identity_id'],
            'credentials': responseData['credentials'],
          };
        } else {
          return {
            'success': false,
            'error': responseData['error'] ?? 'فشل في إكمال تسجيل الدخول'
          };
        }
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'فشل في الاتصال بالخادم'
        };
      }
    } catch (e) {
      developer.log('Social Auth Completion Error: $e', name: 'AUTH_SERVICE');
      return {
        'success': false,
        'error': 'فشل في إكمال تسجيل الدخول: $e'
      };
    }
  }

  /// تأكيد رقم الهاتف
  static Future<Map<String, dynamic>> verifyPhone({
    required String tempUserId,
    required String code,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/verify-phone');
    
    try {
      developer.log('📱 AuthService.verifyPhone called with:', name: 'AUTH_SERVICE');
      developer.log('  - tempUserId: $tempUserId', name: 'AUTH_SERVICE');
      developer.log('  - code: $code', name: 'AUTH_SERVICE');
      
      final requestBody = {
        'tempUserId': tempUserId,
        'code': code,
      };
      
      developer.log('  - Request Body: $requestBody', name: 'AUTH_SERVICE');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('Verify Phone Response: ${response.statusCode}', name: 'AUTH_SERVICE');
      developer.log('Response Body: ${response.body}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم التحقق من رقم الهاتف بنجاح",
            "userId": responseData["userId"],
            "accessToken": responseData["accessToken"],
            "refreshToken": responseData["refreshToken"],
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "رمز التحقق غير صحيح"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('Verify Phone Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال: $e"
      };
    }
  }

  /// تحديث رقم الهاتف وإرسال رمز تحقق جديد
  static Future<Map<String, dynamic>> updatePhoneNumber({
    required String tempUserId,
    required String newPhone,
    String? countryCode,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/auth/resend-code');
      
      developer.log('📱 AuthService.updatePhoneNumber called with:', name: 'AUTH_SERVICE');
      developer.log('  - tempUserId: $tempUserId', name: 'AUTH_SERVICE');
      developer.log('  - newPhone: $newPhone', name: 'AUTH_SERVICE');
      developer.log('  - countryCode: ${countryCode ?? '+964'}', name: 'AUTH_SERVICE');
      
      final requestBody = {
        'tempUserId': tempUserId,
        'verificationType': 'phone',
        'newPhone': newPhone,
        'countryCode': countryCode ?? '+964',
      };
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      developer.log('Update Phone Response: ${response.statusCode}', name: 'AUTH_SERVICE');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (responseData['success'] == true) {
          return {
            "success": true,
            "message": responseData["message"] ?? "تم تحديث رقم الهاتف وإرسال رمز التحقق الجديد",
          };
        } else {
          return {
            "success": false,
            "error": responseData["error"] ?? "فشل في تحديث رقم الهاتف"
          };
        }
      } else {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          "success": false,
          "error": responseData["error"] ?? "خطأ في الخادم: ${response.statusCode}"
        };
      }
    } catch (e) {
      developer.log('Update Phone Error: $e', name: 'AUTH_SERVICE');
      return {
        "success": false,
        "error": "خطأ في الاتصال: $e"
      };
    }
  }

  /// إرسال رمز التحقق للبريد الإلكتروني
  static Future<void> sendEmailVerificationCode(String email) async {
    // محاكاة إرسال رمز التحقق للبريد الإلكتروني
    await Future.delayed(const Duration(seconds: 1));
    developer.log('📧 تم إرسال رمز التحقق إلى: $email');
  }

  /// التحقق من رمز البريد الإلكتروني
  static Future<bool> verifyEmailCode(String email, String code) async {
    // محاكاة التحقق من الرمز
    await Future.delayed(const Duration(seconds: 1));
    // للاختبار، نقبل أي رمز مكون من 6 أرقام
    return code.length == 6 && RegExp(r'^\d+$').hasMatch(code);
  }

  /// إرسال رمز التحقق للهاتف
  static Future<void> sendPhoneVerificationCode(String phoneNumber) async {
    // محاكاة إرسال رمز التحقق للهاتف
    await Future.delayed(const Duration(seconds: 1));
    developer.log('📱 تم إرسال رمز التحقق إلى: $phoneNumber');
  }

  /// التحقق من رمز الهاتف
  static Future<bool> verifyPhoneCode(String phoneNumber, String code) async {
    // محاكاة التحقق من الرمز
    await Future.delayed(const Duration(seconds: 1));
    // للاختبار، نقبل أي رمز مكون من 6 أرقام
    return code.length == 6 && RegExp(r'^\d+$').hasMatch(code);
  }

  /// ✅ التحقق من البريد الإلكتروني (تسجيل جديد) عبر الباك-إند
  static Future<Map<String, dynamic>> verifyEmailRegistration({
    required String tempUserId,
    required String code,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/verify-email');

    try {
      developer.log(
        '📡 VerifyEmailRegistration POST $url (tempUserId=${tempUserId.isNotEmpty ? 'set' : 'empty'}, codeLength=${code.length})',
        name: 'AUTH_SERVICE',
      );
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'tempUserId': tempUserId,
              'code': code,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      developer.log(
        '📥 VerifyEmailRegistration response=${response.statusCode} bodyKeys=${responseData is Map ? responseData.keys.toList() : 'n/a'}',
        name: 'AUTH_SERVICE',
      );

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] == true,
          'message': responseData['message'],
          'userId': responseData['userId'],
          'verified': responseData['verified'],
          'error': responseData['error'],
        };
      }

      return {
        'success': false,
        'error': responseData['error'] ?? 'خطأ في الخادم: ${response.statusCode}',
        'technical_error': responseData,
      };
    } catch (e) {
      developer.log('Verify Email Error: $e', name: 'AUTH_SERVICE');
      return {
        'success': false,
        'error': 'خطأ في الاتصال: تحقق من الإنترنت وحاول مرة أخرى',
        'technical_error': e.toString(),
      };
    }
  }

  /// ✅ التحقق من رقم الهاتف (تسجيل جديد) عبر الباك-إند
  static Future<Map<String, dynamic>> verifyPhoneRegistration({
    required String tempUserId,
    required String code,
  }) async {
    final url = Uri.parse('$_baseUrl/auth/verify-phone');

    try {
      developer.log(
        '📡 VerifyPhoneRegistration POST $url (tempUserId=${tempUserId.isNotEmpty ? 'set' : 'empty'}, codeLength=${code.length})',
        name: 'AUTH_SERVICE',
      );
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'tempUserId': tempUserId,
              'code': code,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(utf8.decode(response.bodyBytes));

      developer.log(
        '📥 VerifyPhoneRegistration response=${response.statusCode} bodyKeys=${responseData is Map ? responseData.keys.toList() : 'n/a'}',
        name: 'AUTH_SERVICE',
      );

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] == true,
          'message': responseData['message'],
          'userId': responseData['userId'],
          'accessToken': responseData['accessToken'],
          'refreshToken': responseData['refreshToken'],
          'error': responseData['error'],
        };
      }

      return {
        'success': false,
        'error': responseData['error'] ?? 'خطأ في الخادم: ${response.statusCode}',
        'technical_error': responseData,
      };
    } catch (e) {
      developer.log('Verify Phone Error: $e', name: 'AUTH_SERVICE');
      return {
        'success': false,
        'error': 'خطأ في الاتصال: تحقق من الإنترنت وحاول مرة أخرى',
        'technical_error': e.toString(),
      };
    }
  }

  /// تسجيل مستخدم جديد مع معاملات مبسطة
  static Future<Map<String, dynamic>> registerSimple({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
  }) async {
    // استخدام الدالة الأساسية مع تمرير المعاملات المطلوبة
    return await registerSecure(
      name: fullName,
      email: email,
      phone: phoneNumber,
      password: password,
    );
  }
}
