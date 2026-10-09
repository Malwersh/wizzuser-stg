import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import 'home_screen.dart';
import 'intro_screen.dart';
import 'address_gate_screen.dart';
import '../services/delivery_address_manager.dart';
import '../services/guest_cache_service.dart';
import '../services/push_notifications_service.dart';
import '../services/session_service.dart';
import '../services/websocket_service.dart';
import 'dart:developer' as developer;

/// شاشة البداية - تقوم بتهيئة التطبيق والتحقق من الجلسة
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _hasNavigated = false; // تجنب التنقل المتعدد

  @override
  void initState() {
    super.initState();
    
    // تهيئة الرسوم المتحركة
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    // بدء الرسوم المتحركة
    _animationController.forward();
    
    // تأجيل التهيئة لتجنب setState أثناء البناء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndNavigate();
      
      // إضافة مراقب لحالة الجلسة للتفاعل مع تغييرات login/logout
      _setupSessionStateListener();
    });
  }

  void _setupSessionStateListener() {
    // مراقبة تغييرات حالة الجلسة
    final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);
    appStateProvider.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    if (_hasNavigated) return; // تجنب التنقل المتعدد
    
    final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);
    developer.log('🔄 SplashScreen: App state changed - isLoggedIn: ${appStateProvider.isLoggedIn}, isGuest: ${appStateProvider.isGuest}');
    
    // إذا تم تسجيل الدخول بنجاح، انتقل للشاشة الرئيسية
    if (appStateProvider.isLoggedIn && mounted) {
      _hasNavigated = true;
      developer.log('✅ User logged in - navigating to home from splash');
      _navigateToHome();
    }
  }

  @override
  void dispose() {
    // إزالة المراقب
    try {
      final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);
      appStateProvider.removeListener(_onAppStateChanged);
    } catch (e) {
      developer.log('⚠️ Error removing listener: $e');
    }
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeAndNavigate() async {
    try {
      // تهيئة مزود حالة التطبيق
      final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);
      
      developer.log('🚀 بدء تهيئة شاشة البداية');

      // ✅ تهيئة الخدمات بالتوازي لتسريع التحميل
      await Future.wait([
        SessionService.instance.initialize(),
        PushNotificationsService.initialize(
          onNotificationTap: (message) async {
            await PushNotificationsService.stashPendingTabFromTap(message);
            await PushNotificationsService.stashOrderFromTap(message);
          },
        ),
        appStateProvider.initializeApp(),
        // انتظار بسيط للرسوم المتحركة فقط
        Future.delayed(const Duration(milliseconds: 1200)),
      ]);

      // 🌐 تهيئة WebSocket (بدون حجب)
      WebSocketService.instance.enableReconnection();
      
      if (!mounted) return;
      
      // التحقق من حالة التطبيق والتنقل المناسب
      await _navigateToNextScreen(appStateProvider);
      
    } catch (e) {
      developer.log('❌ خطأ في تهيئة شاشة البداية: $e');
      
      if (mounted) {
        // في حالة الخطأ، انتقل لشاشة المقدمة
        _navigateToIntro();
      }
    }
  }

  Future<void> _navigateToNextScreen(AppStateProvider appStateProvider) async {
    try {
      // تحديد الشاشة التالية بناءً على حالة المستخدم
      if (appStateProvider.isLoggedIn) {
        developer.log('✅ المستخدم مسجل الدخول - التحقق من العنوان...');
        _hasNavigated = true;
        await _navigateWithAddressCheck(isGuest: false);
      } else if (appStateProvider.isGuest) {
        developer.log('✅ المستخدم ضيف - التحقق من العنوان المحفوظ...');  
        _hasNavigated = true;
        await _navigateWithAddressCheck(isGuest: true);
      } else {
        developer.log('ℹ️ مستخدم جديد - التنقل لشاشة المقدمة');
        _hasNavigated = true;
        _navigateToIntro();
      }
    } catch (e) {
      developer.log('❌ خطأ في تحديد الشاشة التالية: $e');
      _hasNavigated = true;
      _navigateToIntro();
    }
  }

  /// ✅ التحقق من العنوان قبل التنقل للشاشة الرئيسية
  Future<void> _navigateWithAddressCheck({required bool isGuest}) async {
    try {
      final addressManager = DeliveryAddressManager.instance;
      
      if (isGuest) {
        // للضيوف: التحقق من الـ cache المحلي
        final hasGuestAddress = await GuestCacheService.hasGuestAddress();
        
        if (hasGuestAddress) {
          final address = await GuestCacheService.getGuestAddress();
          if (address != null) {
            developer.log('📍 تم تحميل عنوان الضيف من الـ cache');
            await addressManager.setActiveAddress(address);
            _navigateToHome();
            return;
          }
        }
        
        developer.log('⚠️ لا يوجد عنوان محفوظ للضيف - التوجيه لاختيار العنوان');
        _navigateToAddressGate(isGuest: true);
        
      } else {
        // للمستخدمين المسجلين: التحقق من العنوان النشط
        final hasAddress = await addressManager.hasActiveAddress();
        
        if (hasAddress) {
          developer.log('📍 يوجد عنوان نشط - التنقل للشاشة الرئيسية');
          _navigateToHome();
        } else {
          developer.log('⚠️ لا يوجد عنوان نشط - التوجيه لاختيار العنوان');
          _navigateToAddressGate(isGuest: false);
        }
      }
      
    } catch (e) {
      developer.log('❌ خطأ في التحقق من العنوان: $e');
      // في حالة الخطأ، اطلب من المستخدم اختيار العنوان
      _navigateToAddressGate(isGuest: isGuest);
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _navigateToIntro() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const IntroScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _navigateToAddressGate({required bool isGuest}) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AddressGateScreen(
          isGuest: isGuest,
          showBackButton: false,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDC500), // ✅ خلفية باللون الأساسي (أصفر)
      body: Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ✅ أيقونة Wiz (زرقاء)
                    Image.asset(
                      'assets/Wiz_Logo/Wizz_AB_icon_w_1024_Blue.png',
                      width: 200,
                      height: 200,
                      fit: BoxFit.contain,
                    ),
                    
                    const SizedBox(height: 120),
                    
                    // مؤشر التحميل بالأصفر
                    const SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF00509D), // ✅ باللون الثانوي (أزرق)
                        ),
                        strokeWidth: 4,
                        backgroundColor: Color(0x3300509D), // خلفية زرقاء خفيفة
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}