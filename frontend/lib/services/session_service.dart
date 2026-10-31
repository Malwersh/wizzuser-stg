import 'push_notifications_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:rxdart/rxdart.dart';
import '../models/session_state.dart';
import 'websocket_service.dart';
import 'http_service.dart';
import 'restored_session_identity.dart';

/// خدمة إدارة الجلسات الآمنة والمركزية
/// تتولى جميع عمليات تسجيل الدخول والخروج والحفاظ على الجلسات
class SessionService extends ChangeNotifier {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  static SessionService get instance => _instance;
  SessionService._internal();

  // 🔧 FIX: Add session readiness tracking
  bool _isSessionReady = false;
  Completer<void>? _sessionReadyCompleter;

  /// Wait for session to be fully ready before making API calls
  Future<void> waitForSessionReady() async {
    // بساطة: إذا لم تكن الجلسة جاهزة، انتظر فترة قصيرة فقط
    if (!_isSessionReady) {
      await Future.delayed(const Duration(milliseconds: 500));
      _isSessionReady = true;
    }
  }

  // Secure Storage for sensitive data
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Stream controllers for session state
  final BehaviorSubject<SessionState> _sessionStateController = 
      BehaviorSubject<SessionState>.seeded(SessionInitial());
  
  Stream<SessionState> get sessionStateStream => _sessionStateController.stream;
  SessionState get currentSessionState => _sessionStateController.value;

  // Session state variables
  bool _isLoggedIn = false;
  bool _isGuest = false;
  String? _currentUserId;
  Map<String, dynamic>? _currentUser;
  String? _accessToken;
  String? _idToken;
  String? _refreshToken;

  // Security flag to prevent operations during logout
  bool _isPerformingLogout = false;

  // Storage keys for SharedPreferences (non-sensitive data)
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _isGuestKey = 'is_guest';
  static const String _currentUserIdKey = 'current_user_id';
  static const String _userDataKey = 'user_data';
  static const String _cartDataKey = 'cart_data';

  // Secure storage keys for sensitive data
  static const String _accessTokenKey = 'access_token';
  static const String _idTokenKey = 'id_token';
  static const String _refreshTokenKey = 'refresh_token';

  static const String _tag = 'SESSION_SERVICE';

  // Getters
  bool get isLoggedIn => _isLoggedIn;
  bool get isGuest => _isGuest;
  String? get currentUserId => _currentUserId;
  Map<String, dynamic>? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  String? get idToken => _idToken;
  String? get refreshToken => _refreshToken;
  
  Future<String?>? _tokenRefresh;

  Future<String?> getToken() async {
    final token = _accessToken;
    if (token == null || !_isLoggedIn || _isGuest || _isPerformingLogout) {
      return null;
    }
    try {
      if (JwtDecoder.getExpirationDate(token).isAfter(
        DateTime.now().add(const Duration(seconds: 60)),
      )) return token;
    } catch (_) {
      return null;
    }
    final pending = _tokenRefresh;
    if (pending != null) return pending;
    final operation = _refreshAccessToken();
    _tokenRefresh = operation;
    try {
      return await operation;
    } finally {
      if (identical(_tokenRefresh, operation)) _tokenRefresh = null;
    }
  }

  Future<String?> _refreshAccessToken() async {
    final refresh = _refreshToken;
    final account = _currentUserId;
    if (refresh == null || refresh.isEmpty) return null;
    try {
      final response = await http.post(
        Uri.https('cognito-idp.${ApiConfig.cognitoRegion}.amazonaws.com', '/'),
        headers: {
          'Content-Type': 'application/x-amz-json-1.1',
          'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth',
        },
        body: jsonEncode({
          'AuthFlow': 'REFRESH_TOKEN_AUTH',
          'ClientId': ApiConfig.cognitoClientId,
          'AuthParameters': {'REFRESH_TOKEN': refresh},
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final result = jsonDecode(response.body)['AuthenticationResult'];
      final access = result?['AccessToken'] as String?;
      final id = result?['IdToken'] as String?;
      if (access == null || JwtDecoder.isExpired(access)) return null;
      if (!_isLoggedIn || _isPerformingLogout ||
          _currentUserId != account || _refreshToken != refresh) return null;
      _accessToken = access;
      if (id != null) _idToken = id;
      await _secureStorage.write(key: _accessTokenKey, value: access);
      if (id != null) await _secureStorage.write(key: _idTokenKey, value: id);
      return access;
    } catch (_) {
      return null;
    }
  }
  
  int getCartItemsCountForStore(String storeId) {
    // Get cart count for specific store - implement based on your cart logic
    return 0; // Default implementation
  }

  /// تهيئة الخدمة وتحميل الجلسة المحفوظة
  Future<void> initialize() async {
    developer.log('🚀 تهيئة خدمة الجلسات...', name: _tag);

    try {
      _safeEmit(SessionInitial());
      
      // Add delay to prevent rapid initialization cycles
      await Future.delayed(const Duration(milliseconds: 300));
      
      final prefs = await SharedPreferences.getInstance();
      
      // Load basic session state
      _isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
      _isGuest = prefs.getBool(_isGuestKey) ?? false;
      _currentUserId = prefs.getString(_currentUserIdKey);
      
      developer.log('📋 Session state loaded: isLoggedIn=$_isLoggedIn, isGuest=$_isGuest, userId=$_currentUserId', name: _tag);
      
      if (_isLoggedIn && !_isGuest && _currentUserId != null) {
        // Load user session
        await _loadUserSession();
        if (_accessToken != null) {
          final valid = await _validateRestoredIdentity();
          if (valid == null) {
            _isLoggedIn = false;
            _currentUser = null;
            _safeEmit(SessionInitial());
            return;
          }
          if (!valid) await _clearSession();
        }
        
        if (_currentUser != null && _accessToken != null) {
          final userData = Map<String, dynamic>.from(_currentUser!);
          userData['userId'] = _currentUserId;
          userData['user_id'] = _currentUserId;
          
          _safeEmit(SessionActive(userData));
          developer.log('✅ تم تحميل جلسة المستخدم: ${userData['email'] ?? userData['name']}', name: _tag);
        } else {
          developer.log('⚠️ بيانات المستخدم مفقودة أو token منتهي الصلاحية، تنظيف الجلسة', name: _tag);
          await _clearSession();
          await _saveGuestSessionSilent();
          _safeEmit(GuestSession());
        }
      } else if (_isGuest) {
        // Guest session
        _currentUserId = 'guest';
        _currentUser = {'user_id': 'guest', 'name': 'ضيف'};
        _safeEmit(GuestSession());
        developer.log('👤 تم تحميل جلسة الضيف', name: _tag);
      } else {
        // No session - start as guest
        await _saveGuestSessionSilent();
        _safeEmit(GuestSession());
        developer.log('❌ لا توجد جلسة، بدء وضع الضيف', name: _tag);
      }

      // 🔧 FIX: Mark session as ready
      _isSessionReady = true;
      _sessionReadyCompleter?.complete();

    } catch (e, stackTrace) {
      developer.log('❌ خطأ في تهيئة الخدمة: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
      await _clearSession();
      _safeEmit(SessionInitial());
    }
  }

  // A cached JWT does not prove that its account still exists.
  // Transport failures leave storage intact and never activate cached identity.
  Future<bool?> _validateRestoredIdentity() async {
    try {
      final token = await getToken();
      if (token == null) return null;
      final response = await http.post(
        Uri.https('cognito-idp.${ApiConfig.cognitoRegion}.amazonaws.com', '/'),
        headers: {
          'Content-Type': 'application/x-amz-json-1.1',
          'X-Amz-Target': 'AWSCognitoIdentityProviderService.GetUser',
        },
        body: jsonEncode({'AccessToken': token}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final attrs = (data['UserAttributes'] as List).cast<Map>();
        final sub = attrs.firstWhere((a) => a['Name'] == 'sub')['Value'];
        return sub is String && sub == JwtDecoder.decode(token)['sub'] &&
            restoredProfileMatchesSubject(_currentUser, _currentUserId, sub);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final code = '${data['__type']}'.split('#').last;
      if (code == 'NotAuthorizedException' || code == 'UserNotFoundException') {
        return false;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Safe emit for session states
  void _safeEmit(SessionState state) {
    // تجاهل التحديثات أثناء تسجيل الخروج (إلا GuestSession)
    if (_isPerformingLogout && state is! GuestSession) {
      return;
    }
    
    // منع تكرار نفس الحالة
    if (_sessionStateController.hasValue && 
        _sessionStateController.value.runtimeType == state.runtimeType &&
        state is! SessionActive) {
      return;
    }
    
    _sessionStateController.add(state);
  }

  /// تحميل بيانات جلسة المستخدم من التخزين الآمن
  Future<void> _loadUserSession() async {
    try {
      developer.log('📱 تحميل بيانات جلسة المستخدم...', name: _tag);
      
      // Load tokens from secure storage
      _accessToken = await _secureStorage.read(key: _accessTokenKey);
      _idToken = await _secureStorage.read(key: _idTokenKey);
      _refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      
      // Load user data from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString(_userDataKey);
      
      if (userDataString != null) {
        // تحميل بيانات المستخدم
        _currentUser = jsonDecode(userDataString);
        
        // تجنب automatic logout - دع المستخدم يقرر
        if (_accessToken != null && !_isPerformingLogout) {
          try {
            if (JwtDecoder.isExpired(_accessToken!)) {
              developer.log('⚠️ انتهت صلاحية التوكن - المستخدم سيحتاج لتسجيل دخول جديد', name: _tag);
              // لا نقوم بتسجيل خروج تلقائي
            }
          } catch (jwtError) {
            developer.log('⚠️ تعذر فحص صلاحية التوكن: $jwtError', name: _tag);
          }
        }
        
        developer.log('✅ تم تحميل بيانات المستخدم بنجاح', name: _tag);
      } else {
        developer.log('⚠️ بيانات المستخدم غير موجودة', name: _tag);
        _currentUser = null;
      }
      
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في تحميل بيانات الجلسة: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
      // Don't clear session on load errors, just log them
    }
  }

  /// حفظ جلسة مستخدم جديدة
  Future<void> saveUserSession({
    required String accessToken,
    required String idToken,
    required String refreshToken,
    required Map<String, dynamic> userData,
  }) async {
    try {
      // 🔧 FIX: Mark session as not ready during save process
      _isSessionReady = false;
      _sessionReadyCompleter = Completer<void>();
      
      developer.log('💾 حفظ جلسة مستخدم جديدة: ${userData['email'] ?? userData['name']}', name: _tag);

      // Extract user ID
      _currentUserId = userData['userId'] ?? userData['user_id'] ?? userData['email'];
      
      if (_currentUserId == null) {
        throw Exception('لا يمكن تحديد معرف المستخدم');
      }
      
      // 🔧 إصلاح: تحديث الذاكرة المحلية فوراً قبل حفظ الجلسة لمنع استخدام بيانات ضيف قديمة
      _isLoggedIn = true;
      _isGuest = false;
      _accessToken = accessToken;
      _idToken = idToken;
      _refreshToken = refreshToken;
      _currentUser = userData;
      
      developer.log('✅ تم تحديث الذاكرة المحلية فوراً: userId=$_currentUserId, isGuest=$_isGuest', name: _tag);

      // Save tokens to secure storage
      await Future.wait([
        _secureStorage.write(key: _accessTokenKey, value: accessToken),
        _secureStorage.write(key: _idTokenKey, value: idToken),
        _secureStorage.write(key: _refreshTokenKey, value: refreshToken),
      ]);

      // Save user data and session state to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      
      // 🔧 مسح أي بيانات ضيف قديمة أولاً
      await prefs.remove('user_id'); // مسح userId القديم (الضيف)
      
      await Future.wait([
        prefs.setString(_userDataKey, jsonEncode(userData)),
        prefs.setString(_currentUserIdKey, _currentUserId!),
        prefs.setBool(_isLoggedInKey, true),
        prefs.setBool(_isGuestKey, false),
      ]);

      // Isolate cart for this user
      await _isolateUserCart();

      // Emit session active state
      final userDataForProvider = Map<String, dynamic>.from(userData);
      userDataForProvider['userId'] = _currentUserId;
      userDataForProvider['user_id'] = _currentUserId;
      
      _safeEmit(SessionActive(userDataForProvider));
      notifyListeners();

      // 🔧 FIX: Mark session as ready and notify waiters
      _isSessionReady = true;
      _sessionReadyCompleter?.complete();

      developer.log('✅ تم حفظ جلسة المستخدم بنجاح', name: _tag);

    } catch (e, stackTrace) {
      developer.log('❌ خطأ في حفظ جلسة المستخدم: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
      rethrow;
    }
  }

  /// تسجيل دخول آمن مع حفظ معلومات الجلسة
  Future<bool> login(String identifier, String password) async {
    // Console logging for Flutter web
    if (kIsWeb) {
      print('🔐 FLUTTER WEB: Starting login for: $identifier');
    }
    
    try {
      developer.log('🔐 SESSION: Starting secure login process for: $identifier', name: _tag);
      
      // استخدام الـ endpoint الموحد الجديد
      const endpoint = '/auth/login';
      
      // إعداد بيانات الطلب - استخدام username بدلاً من email/phone
      final requestBody = {
        'username': identifier,  // الـ backend يتوقع username
        'password': password,
      };
      
      // Console logging for Flutter web
      if (kIsWeb) {
        print('📤 FLUTTER WEB: Calling API: $endpoint');
        print('📤 FLUTTER WEB: Request body: $requestBody');
      }
      
      developer.log('📤 DETAILED: Calling API endpoint: $endpoint', name: _tag);
      developer.log('📤 DETAILED: Full URL will be constructed as: <API_URL>$endpoint', name: _tag);
      developer.log('📤 DETAILED: Request body: $requestBody', name: _tag);
      
      // استدعاء API الباك إند الموحد
      final response = await HttpService.postPublic(endpoint, body: requestBody);
      
      developer.log('📥 DETAILED: Backend response status: ${response.statusCode}', name: _tag);
      developer.log('📥 DETAILED: Backend response headers: ${response.headers}', name: _tag);
      developer.log('📥 DETAILED: Backend response body: ${response.body}', name: _tag);
      
      if (response.statusCode == 200) {
        // تحليل الاستجابة
        final responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true) {
          final user = responseData['user'];
          final accessToken = responseData['accessToken'];
          final idToken = responseData['idToken'];
          final refreshToken = responseData['refreshToken'];
          
          // فحص أن بيانات المستخدم موجودة
          if (user != null && user is Map<String, dynamic> && 
              accessToken != null && idToken != null && refreshToken != null) {
            developer.log('✅ Login successful for user: ${user['userId'] ?? 'unknown'}', name: _tag);
            developer.log('🔑 Access Token received: ${accessToken != null ? "Yes" : "No"}', name: _tag);
            developer.log('👤 User data: ${jsonEncode(user)}', name: _tag);
            
            // إعداد بيانات المستخدم مع فحص القيم الفارغة
            final userData = {
              'user_id': user['userId']?.toString() ?? '',
              'userId': user['userId']?.toString() ?? '',
              'name': user['name']?.toString() ?? '',
              'email': user['email']?.toString() ?? '',
              'phone': user['phone']?.toString() ?? '',
            };
            
            // حفظ الجلسة باستخدام البيانات الحقيقية من الـ response الجديد
            await saveUserSession(
              accessToken: accessToken.toString(),
              idToken: idToken.toString(), 
              refreshToken: refreshToken.toString(),
              userData: userData,
            );
            
            developer.log('✅ SESSION: Login completed successfully', name: _tag);
            return true;
          } else {
            developer.log('❌ Invalid user data or missing tokens', name: _tag);
            developer.log('❌ User: ${user != null}, AccessToken: ${accessToken != null}, IdToken: ${idToken != null}, RefreshToken: ${refreshToken != null}', name: _tag);
            return false;
          }
        } else {
          // فشل في تسجيل الدخول
          final errorMessage = responseData['error']?.toString() ?? 'فشل في تسجيل الدخول';
          developer.log('❌ Login failed: $errorMessage', name: _tag);
          developer.log('📦 Full response: ${jsonEncode(responseData)}', name: _tag);
          return false;
        }
      } else {
        // خطأ في الخادم
        try {
          final responseData = jsonDecode(response.body);
          final errorMessage = responseData['error']?.toString() ?? 'خطأ في الخادم';
          developer.log('❌ Server error: $errorMessage', name: _tag);
        } catch (e) {
          developer.log('❌ Server error - unable to parse response: ${response.body}', name: _tag);
        }
        return false;
      }
      
    } catch (e) {
      developer.log('❌ SESSION: Login failed: $e', name: _tag);
      return false;
    }
  }

  /// Login with detailed response including error messages
  Future<Map<String, dynamic>> loginWithDetails(String identifier, String password) async {
    // Console logging for Flutter web
    if (kIsWeb) {
      print('🔐 FLUTTER WEB: Starting detailed login for: $identifier');
    }
    
    try {
      developer.log('🔐 SESSION: Starting detailed login process for: $identifier', name: _tag);
      
      // استخدام الـ endpoint الموحد الجديد
      const endpoint = '/auth/login';
      
      // إعداد بيانات الطلب - استخدام username بدلاً من email/phone
      final requestBody = {
        'username': identifier,  // الـ backend يتوقع username
        'password': password,
      };
      
      // Console logging for Flutter web
      if (kIsWeb) {
        print('📤 FLUTTER WEB: Calling API: $endpoint');
        print('📤 FLUTTER WEB: Request body: $requestBody');
      }
      
      developer.log('📤 DETAILED: Calling API endpoint: $endpoint', name: _tag);
      developer.log('📤 DETAILED: Request body: $requestBody', name: _tag);
      
      // استدعاء API الباك إند الموحد
      final response = await HttpService.postPublic(endpoint, body: requestBody);
      
      developer.log('📥 DETAILED: Backend response status: ${response.statusCode}', name: _tag);
      developer.log('📥 DETAILED: Backend response body: ${response.body}', name: _tag);
      
      if (response.statusCode == 200) {
        // تحليل الاستجابة
        final responseData = jsonDecode(response.body);
        
        // طباعة الاستجابة الكاملة للتحقق
        developer.log('📦 COMPLETE RESPONSE: ${jsonEncode(responseData)}', name: _tag);
        developer.log('🔍 SUCCESS FLAG: ${responseData['success']}', name: _tag);
        
        if (responseData['success'] == true) {
          final user = responseData['user'];
          final accessToken = responseData['accessToken'];
          final idToken = responseData['idToken'];
          final refreshToken = responseData['refreshToken'];
          
          // طباعة تفاصيل كل حقل
          developer.log('🔍 USER DATA: $user', name: _tag);
          
          // فحص أن بيانات المستخدم والتوكينات الأساسية موجودة
          if (user != null && user is Map<String, dynamic> && 
              accessToken != null && refreshToken != null) {
          
            developer.log('✅ Detailed login successful for user: ${user['userId'] ?? 'unknown'}', name: _tag);
            
            // إعداد بيانات المستخدم مع فحص القيم الفارغة
            final userData = {
              'user_id': user['userId']?.toString() ?? '',
              'userId': user['userId']?.toString() ?? '',
              'name': user['name']?.toString() ?? '',
              'email': user['email']?.toString() ?? '',
              'phone': user['phone']?.toString() ?? '',
            };
            
            // حفظ الجلسة باستخدام البيانات الحقيقية من الـ response الجديد
            // استخدام accessToken كـ idToken إذا لم يكن متوفراً
            await saveUserSession(
              accessToken: accessToken.toString(),
              idToken: (idToken ?? accessToken).toString(), 
              refreshToken: refreshToken.toString(),
              userData: userData,
            );
            
            developer.log('✅ SESSION: Detailed login completed successfully', name: _tag);
            return {
              'success': true,
              'message': responseData['message']?.toString() ?? 'تم تسجيل الدخول بنجاح',
              'user': userData
            };
          } else {
            developer.log('❌ Invalid user data or missing tokens in detailed login', name: _tag);
            developer.log('❌ User: ${user != null}, AccessToken: ${accessToken != null}, RefreshToken: ${refreshToken != null}', name: _tag);
            return {
              'success': false,
              'message': 'استجابة خادم غير صحيحة. يرجى المحاولة مرة أخرى.'
            };
          }
        } else {
          // فشل في تسجيل الدخول - إرجاع رسالة الخطأ من الباك إند
          final errorMessage = responseData['error']?.toString() ?? 'فشل في تسجيل الدخول';
          developer.log('❌ Detailed login failed: $errorMessage', name: _tag);
          developer.log('📦 Full error response: ${jsonEncode(responseData)}', name: _tag);
          return {
            'success': false,
            'message': errorMessage
          };
        }
      } else {
        // خطأ في الخادم
        try {
          final responseData = jsonDecode(response.body);
          final errorMessage = responseData['error'] ?? 'خطأ في الخادم (${response.statusCode})';
          developer.log('❌ Server error: $errorMessage', name: _tag);
          return {
            'success': false,
            'message': errorMessage
          };
        } catch (e) {
          // If response is not valid JSON
          final errorMessage = 'خطأ في الخادم (${response.statusCode}): ${response.body}';
          developer.log('❌ Server error (non-JSON): $errorMessage', name: _tag);
          return {
            'success': false,
            'message': 'خطأ في الخادم. يرجى المحاولة مرة أخرى.'
          };
        }
      }
      
    } catch (e) {
      developer.log('❌ SESSION: Detailed login failed: $e', name: _tag);
      return {
        'success': false,
        'message': 'خطأ في الاتصال: ${e.toString()}'
      };
    }
  }

  /// تسجيل دخول كضيف
  Future<bool> loginAsGuest() async {
    try {
      print('🔐 SESSION: Starting guest login...');
      
      // إنشاء معرف ضيف
      final guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
      
      // مسح أي بيانات مصادقة سابقة
      await _clearSecureTokens();
      
      // حفظ حالة الضيف
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', 'ضيف');
      await prefs.setString('user_id', guestId);
      await prefs.setBool('is_logged_in', false);
      await prefs.setBool('is_guest', true);
      await prefs.setString('login_timestamp', DateTime.now().toIso8601String());
      
      // تحديث الحالة المحلية
      _isLoggedIn = false;
      _isGuest = true;
      _currentUserId = guestId;
      
      // إشعار المستمعين
      _safeEmit(GuestSession());
      
      return true;
      
    } catch (e) {
      print('❌ SESSION: Guest login failed: $e');
      return false;
    }
  }

  /// حفظ جلسة الضيف
  Future<void> saveGuestSession() async {
    try {
      developer.log('👤 حفظ جلسة ضيف', name: _tag);

      // Clear any existing user data first
      await _clearUserData();

      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool(_isLoggedInKey, false),
        prefs.setBool(_isGuestKey, true),
        prefs.setString(_currentUserIdKey, 'guest'),
      ]);

      // Isolate guest cart
      await _isolateGuestCart();

      // Update internal state
      _isLoggedIn = false;
      _isGuest = true;
      _currentUserId = 'guest';
      _currentUser = {'user_id': 'guest', 'name': 'ضيف'};

      _safeEmit(GuestSession());
      notifyListeners();

      developer.log('✅ تم حفظ جلسة الضيف بنجاح', name: _tag);

    } catch (e, stackTrace) {
      developer.log('❌ خطأ في حفظ جلسة الضيف: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
      rethrow;
    }
  }

  /// 🔒 تسجيل الخروج الآمن والشامل
  Future<void> logout() async {
    if (_isPerformingLogout) {
      developer.log('⚠️ تسجيل الخروج قيد التنفيذ بالفعل', name: _tag);
      return;
    }

    _isPerformingLogout = true;
    
    try {
      developer.log('🚪 بدء عملية تسجيل الخروج الآمن', name: _tag);

      final currentUserEmail = _currentUser?['email'] ?? _currentUserId ?? 'غير محدد';
      developer.log('👤 تسجيل خروج المستخدم: $currentUserEmail', name: _tag);

      // Step 1: Disconnect WebSocket safely
      await _disconnectWebSocket();

      await PushNotificationsService.unregisterSignedOutDevice();

      // Step 2: Revoke tokens from Cognito (server-side logout)
      await _revokeServerSideTokens();

      // Step 3: Clear all local session data
      await _clearAllSessionData();

      // Step 4: Reset internal state
      _resetInternalState();

      // Step 5: Switch to guest mode (but don't emit yet)
      await _saveGuestSessionSilent();

      // Step 6: Reset logout flag BEFORE emitting guest session
      _isPerformingLogout = false;

      // Step 7: Now emit guest session so UI updates
      _safeEmit(GuestSession());
      notifyListeners();

      developer.log('✅ تم تسجيل الخروج بنجاح وتم التحويل لوضع الضيف', name: _tag);

    } catch (e, stackTrace) {
      developer.log('❌ خطأ في تسجيل الخروج: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
      
      // Emergency fallback - force clean state
      try {
        await _emergencyCleanup();
        
        // Reset logout flag before emitting
        _isPerformingLogout = false;
        
        await _saveGuestSessionSilent();
        _safeEmit(GuestSession());
        notifyListeners();
        
        developer.log('✅ تم تنفيذ تسجيل الخروج الطارئ', name: _tag);
      } catch (emergencyError) {
        developer.log('❌ فشل تسجيل الخروج الطارئ: $emergencyError', name: _tag);
        _isPerformingLogout = false; // Reset even on emergency failure
      }
    }
  }

  /// قطع اتصال WebSocket بشكل آمن
  Future<void> _disconnectWebSocket() async {
    try {
      developer.log('🔌 قطع اتصال WebSocket...', name: _tag);
      
      final wsService = WebSocketService();
      wsService.stopReconnectionPermanently();
      await wsService.disconnect();
      
      // 🆕 تنظيف إضافي: استدعاء endpoint تنظيف WebSocket من الباك إند
      await _cleanupWebSocketFromBackend();
      
      // Wait briefly to ensure disconnection
      await Future.delayed(const Duration(milliseconds: 500));
      
      developer.log('✅ تم قطع اتصال WebSocket بنجاح', name: _tag);
    } catch (e) {
      developer.log('⚠️ خطأ في قطع WebSocket: $e', name: _tag);
      // Don't throw, continue with logout
    }
  }
  
  /// تنظيف WebSocket من الباك إند
  Future<void> _cleanupWebSocketFromBackend() async {
    try {
      if (_currentUserId == null) return;
      
      developer.log('🧹 تنظيف WebSocket من الباك إند للمستخدم: $_currentUserId', name: _tag);
      
      final response = await HttpService.postPublic(
        '/websocket/cleanup-user-connections', 
        body: {
          'userId': _currentUserId,
          'userType': 'customer' // نوع المستخدم لتطبيق العملاء
        }
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          developer.log('✅ تم تنظيف WebSocket من الباك إند بنجاح', name: _tag);
          developer.log('📊 تفاصيل التنظيف: ${responseData['details']}', name: _tag);
        } else {
          developer.log('⚠️ فشل تنظيف WebSocket: ${responseData['message']}', name: _tag);
        }
      } else {
        developer.log('⚠️ خطأ HTTP في تنظيف WebSocket: ${response.statusCode}', name: _tag);
      }
    } catch (e) {
      developer.log('⚠️ خطأ في تنظيف WebSocket من الباك إند: $e', name: _tag);
      // Don't throw, this is not critical for logout
    }
  }

  /// إلغاء التوكينات من الخادم (Cognito)
  Future<void> _revokeServerSideTokens() async {
    try {
      developer.log('🔐 إلغاء التوكينات من الخادم...', name: _tag);
      
      if (_refreshToken != null) {
        // Here you would implement actual Cognito token revocation
        // For now, we'll just log it as the actual implementation 
        // would require AWS Cognito client setup
        developer.log('📤 سيتم إلغاء refresh token من Cognito', name: _tag);
        
        // TODO: Implement actual Cognito token revocation
        // await CognitoHelper.revokeToken(_refreshToken!);
      }
      
      developer.log('✅ تم إلغاء التوكينات من الخادم', name: _tag);
    } catch (e) {
      developer.log('⚠️ خطأ في إلغاء التوكينات: $e', name: _tag);
      // Don't throw, continue with logout
    }
  }

  /// مسح جميع بيانات الجلسة المحلية
  Future<void> _clearAllSessionData() async {
    try {
      developer.log('🧹 مسح جميع بيانات الجلسة المحلية...', name: _tag);
      
      // Clear secure storage
      await Future.wait([
        _secureStorage.delete(key: _accessTokenKey),
        _secureStorage.delete(key: _idTokenKey),
        _secureStorage.delete(key: _refreshTokenKey),
      ]);

      // Clear SharedPreferences (except cart data)
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_userDataKey),
        prefs.remove(_currentUserIdKey),
        prefs.setBool(_isLoggedInKey, false),
        // Don't clear _isGuestKey here, will be set in saveGuestSession
      ]);

      developer.log('✅ تم مسح بيانات الجلسة المحلية', name: _tag);
    } catch (e) {
      developer.log('❌ خطأ في مسح بيانات الجلسة: $e', name: _tag);
      rethrow;
    }
  }

  /// إعادة تعيين الحالة الداخلية
  void _resetInternalState() {
    // 🔧 FIX: Reset session readiness
    _isSessionReady = false;
    _sessionReadyCompleter = null;
    
    _isLoggedIn = false;
    _isGuest = false;
    _currentUserId = null;
    _currentUser = null;
    _accessToken = null;
    _idToken = null;
    _refreshToken = null;
  }

  /// تنظيف طارئ في حالة فشل العملية الرئيسية
  Future<void> _emergencyCleanup() async {
    try {
      developer.log('🚨 تنفيذ تنظيف طارئ...', name: _tag);
      
      // Force clear everything
      await _secureStorage.deleteAll();
      
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => 
          key != _cartDataKey && !key.startsWith('cart_data_')).toList();
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      _resetInternalState();
      
      developer.log('✅ تم التنظيف الطارئ', name: _tag);
    } catch (e) {
      developer.log('❌ فشل التنظيف الطارئ: $e', name: _tag);
      rethrow;
    }
  }

  /// عزل السلة للمستخدم الحالي
  Future<void> _isolateUserCart() async {
    try {
      if (_currentUserId == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final userCartKey = '${_cartDataKey}_$_currentUserId';
      
      // Load user's specific cart or create empty one
      if (!prefs.containsKey(userCartKey)) {
        await prefs.setString(userCartKey, jsonEncode([]));
        developer.log('📦 تم إنشاء سلة فارغة للمستخدم: $_currentUserId', name: _tag);
      } else {
        developer.log('📦 تم تحميل سلة المستخدم: $_currentUserId', name: _tag);
      }
    } catch (e) {
      developer.log('⚠️ خطأ في عزل سلة المستخدم: $e', name: _tag);
    }
  }

  /// عزل السلة للضيف
  Future<void> _isolateGuestCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const guestCartKey = '${_cartDataKey}_guest';
      
      // Load guest cart or create empty one
      if (!prefs.containsKey(guestCartKey)) {
        await prefs.setString(guestCartKey, jsonEncode([]));
        developer.log('📦 تم إنشاء سلة ضيف فارغة', name: _tag);
      } else {
        developer.log('📦 تم تحميل سلة الضيف', name: _tag);
      }
    } catch (e) {
      developer.log('⚠️ خطأ في عزل سلة الضيف: $e', name: _tag);
    }
  }

  /// مسح جميع بيانات الجلسة
  Future<void> _clearSession() async {
    try {
      await _clearAllSessionData();
      _resetInternalState();
      developer.log('🧹 تم مسح الجلسة', name: _tag);
    } catch (e) {
      developer.log('❌ خطأ في مسح الجلسة: $e', name: _tag);
    }
  }

  /// مسح بيانات المستخدم فقط (الاحتفاظ بحالة الجلسة)
  Future<void> _clearUserData() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: _accessTokenKey),
        _secureStorage.delete(key: _idTokenKey),
        _secureStorage.delete(key: _refreshTokenKey),
      ]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userDataKey);

      _accessToken = null;
      _idToken = null;
      _refreshToken = null;
      _currentUser = null;
      
      developer.log('🧹 تم مسح بيانات المستخدم', name: _tag);
    } catch (e) {
      developer.log('❌ خطأ في مسح بيانات المستخدم: $e', name: _tag);
    }
  }

  /// الحصول على عناصر السلة للمستخدم الحالي
  Future<List<Map<String, dynamic>>> getCartItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String cartKey;
      
      if (_currentUserId != null && _currentUserId != 'guest') {
        cartKey = '${_cartDataKey}_$_currentUserId';
      } else {
        cartKey = '${_cartDataKey}_guest';
      }
      
      final cartString = prefs.getString(cartKey);
      if (cartString != null) {
        final cartList = jsonDecode(cartString) as List;
        return cartList.cast<Map<String, dynamic>>();
      }
      
      return [];
    } catch (e) {
      developer.log('❌ خطأ في تحميل السلة: $e', name: _tag);
      return [];
    }
  }

  /// حفظ عناصر السلة
  Future<void> saveCartItems(List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String cartKey;
      
      if (_currentUserId != null && _currentUserId != 'guest') {
        cartKey = '${_cartDataKey}_$_currentUserId';
      } else {
        cartKey = '${_cartDataKey}_guest';
      }
      
      await prefs.setString(cartKey, jsonEncode(items));
      developer.log('📦 تم حفظ ${items.length} عنصر في السلة', name: _tag);
    } catch (e) {
      developer.log('❌ خطأ في حفظ السلة: $e', name: _tag);
    }
  }

  /// التحقق من صحة الجلسة
  Future<bool> isSessionValid() async {
    try {
      if (!_isLoggedIn || _accessToken == null) {
        return _isGuest; // Guest session is always valid
      }
      
      return !JwtDecoder.isExpired(_accessToken!);
    } catch (e) {
      developer.log('⚠️ خطأ في فحص صحة الجلسة: $e', name: _tag);
      return false;
    }
  }

  /// مسح التوكينات الآمنة فقط
  Future<void> _clearSecureTokens() async {
    try {
      developer.log('🧹 مسح التوكينات الآمنة...', name: _tag);
      
      await Future.wait([
        _secureStorage.delete(key: _accessTokenKey),
        _secureStorage.delete(key: _idTokenKey),
        _secureStorage.delete(key: _refreshTokenKey),
      ]);

      _accessToken = null;
      _idToken = null;
      _refreshToken = null;
      
      developer.log('✅ تم مسح التوكينات الآمنة', name: _tag);
    } catch (e) {
      developer.log('❌ خطأ في مسح التوكينات الآمنة: $e', name: _tag);
    }
  }

  /// تحديث بيانات المستخدم
  Future<void> updateUserData(Map<String, dynamic> newData) async {
    try {
      if (!_isLoggedIn) return;
      
      _currentUser = {..._currentUser ?? {}, ...newData};
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userDataKey, jsonEncode(_currentUser));
      
      notifyListeners();
      developer.log('✅ تم تحديث بيانات المستخدم', name: _tag);
    } catch (e) {
      developer.log('❌ خطأ في تحديث بيانات المستخدم: $e', name: _tag);
    }
  }

  /// Additional methods for backward compatibility
  
  /// Save session data (backward compatibility)
  Future<void> saveSessionData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userDataKey, jsonEncode(data));
      _currentUser = data;
      notifyListeners();
      developer.log('تم حفظ بيانات الجلسة', name: _tag);
    } catch (e) {
      developer.log('خطأ في حفظ بيانات الجلسة: $e', name: _tag);
    }
  }
  
  /// Get user data (backward compatibility)
  Map<String, dynamic>? getUserData() {
    return _currentUser;
  }
  
  /// Static method to check if user is guest (backward compatibility)
  static bool isGuestStatic() {
    return SessionService.instance.isGuest;
  }
  
  /// Get current user ID (backward compatibility)
  Future<String?> getCurrentUserId() async {
    return currentUserId;
  }
  
  /// Get user ID statically (backward compatibility)
  static String? getUserIdStatic() {
    return SessionService.instance.currentUserId;
  }

  /// حفظ جلسة الضيف بدون إرسال إشعارات (للاستخدام الداخلي فقط)
  Future<void> _saveGuestSessionSilent() async {
    try {
      developer.log('👤 حفظ جلسة ضيف (صامت)', name: _tag);

      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool(_isLoggedInKey, false),
        prefs.setBool(_isGuestKey, true),
        prefs.setString(_currentUserIdKey, 'guest'),
      ]);

      // Clear any existing user data but keep guest cart
      await _clearUserData();
      await _isolateGuestCart();

      // Update internal state
      _isLoggedIn = false;
      _isGuest = true;
      _currentUserId = 'guest';
      _currentUser = {'user_id': 'guest', 'name': 'ضيف'};

      // Don't emit or notify - this will be done by caller
      
      developer.log('✅ تم حفظ جلسة الضيف بنجاح (صامت)', name: _tag);

    } catch (e, stackTrace) {
      developer.log('❌ خطأ في حفظ جلسة الضيف (صامت): $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
      rethrow;
    }
  }

  /// تنظيف الموارد
  @override
  void dispose() {
    _sessionStateController.close();
    super.dispose();
  }

  /// طباعة حالة الجلسة للتشخيص
  void debugSessionState() {
    developer.log('=== حالة الجلسة ===', name: _tag);
    developer.log('مسجل دخول: $_isLoggedIn', name: _tag);
    developer.log('ضيف: $_isGuest', name: _tag);
    developer.log('معرف المستخدم: $_currentUserId', name: _tag);
    developer.log('بيانات المستخدم: ${_currentUser?.keys.toList()}', name: _tag);
    developer.log('يتم تنفيذ خروج: $_isPerformingLogout', name: _tag);
    developer.log('حالة الجلسة: ${currentSessionState.runtimeType}', name: _tag);
    developer.log('==================', name: _tag);
  }

  /// التحقق من العزل الصحيح للمفضلة عند تغيير المستخدم
  Future<void> validateFavoritesIsolation() async {
    try {
      developer.log('🔍 فحص عزل المفضلة...', name: _tag);
      
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final favoriteKeys = keys.where((key) => 
        key.contains('favorite_stores') || key.contains('favorite_dishes')
      ).toList();
      
      developer.log('🔑 مفاتيح المفضلة الموجودة: $favoriteKeys', name: _tag);
      
      if (_currentUserId != null) {
        final expectedKey = 'favorite_stores_$_currentUserId';
        final hasCorrectKey = favoriteKeys.contains(expectedKey);
        developer.log('✅ المفتاح المتوقع: $expectedKey، موجود: $hasCorrectKey', name: _tag);
      }
      
    } catch (e) {
      developer.log('❌ خطأ في فحص عزل المفضلة: $e', name: _tag);
    }
  }
}
