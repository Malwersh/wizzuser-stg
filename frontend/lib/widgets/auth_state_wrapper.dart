import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../screens/home_screen.dart';
import '../screens/splash_screen.dart';
import 'dart:developer' as developer;

/// Widget wrapper للتحكم في التنقل بناء على حالة المصادقة
class AuthStateWrapper extends StatelessWidget {
  const AuthStateWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        developer.log('🔄 AuthStateWrapper: Building with state:', name: 'AUTH_WRAPPER');
        developer.log('   - isLoggedIn: ${appState.isLoggedIn}', name: 'AUTH_WRAPPER');
        developer.log('   - isGuest: ${appState.isGuest}', name: 'AUTH_WRAPPER');
        developer.log('   - hasUserData: ${appState.userData != null}', name: 'AUTH_WRAPPER');
        
        // إذا المستخدم مسجل دخول أو ضيف، اذهب للشاشة الرئيسية
        if (appState.isLoggedIn || appState.isGuest) {
          developer.log('✅ User authenticated - showing HomeScreen', name: 'AUTH_WRAPPER');
          return const HomeScreen();
        }
        
        // إذا لا يوجد حالة واضحة، اعرض شاشة البداية للتحميل والتحقق
        developer.log('ℹ️ No clear auth state - showing SplashScreen for initialization', name: 'AUTH_WRAPPER');
        return const SplashScreen();
      },
    );
  }
}
