import 'services/live_activity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'providers/app_state_provider.dart';
import 'providers/versioning_providers.dart'; // 🔥 إضافة providers الجديدة
import 'services/address_service.dart';
import 'models/favorites_model.dart';
import 'helpers/favorites_session_integration.dart';
import 'screens/splash_screen.dart';
import 'themes/app_theme.dart';
import 'services/notification_navigation.dart';

void main() async {
  // تأكد من تهيئة Flutter
  WidgetsFlutterBinding.ensureInitialized();
  
  // إعداد orientation للجهاز
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // ضمان دعم النصوص العربية
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  
  await LiveActivityService.initialize();
  runApp(const FoodApp());
}

class FoodApp extends StatelessWidget {
  const FoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final appStateProvider = AppStateProvider();
            return appStateProvider;
          }
        ),
        
        // النموذج الأصلي للمفضلة مع إصلاح عزل المستخدمين
        ChangeNotifierProvider<FavoritesModel>(
          create: (context) {
            final favoritesModel = FavoritesModel();
            // تهيئة التكامل مع أنظمة إدارة الجلسات
            FavoritesSessionIntegration.initialize(favoritesModel);
            return favoritesModel;
          },
        ),
        
        ChangeNotifierProvider(create: (context) => EnhancedAddressService()),
        
        // 🔥 إضافة providers للتحديثات التلقائية (Version Polling)
        ChangeNotifierProvider(
          create: (_) => MenuProviderWithVersioning(),
        ),
        ChangeNotifierProvider(
          create: (_) => RestaurantListProviderWithVersioning(),
        ),
        ChangeNotifierProvider(
          create: (_) => BatchVersionProviderWithVersioning(),
        ),
      ],
      child: MaterialApp(
        title: 'Food App',
        navigatorKey: NotificationNavigation.navigatorKey,
        scaffoldMessengerKey: NotificationNavigation.messengerKey,
        debugShowCheckedModeBanner: false,
        
        // الموضوع المحسن - بسيط ونظيف
        theme: AppTheme.lightTheme,
        
        // دعم اللغة العربية
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar', 'SA'), // العربية السعودية
          Locale('en', 'US'), // الإنجليزية
        ],
        locale: const Locale('ar', 'SA'),
        
        // الشاشة الأولى
        home: const SplashScreen(),
        
        // إعدادات إضافية
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.0),
              ),
              child: child!,
            ),
          );
        },
      ),
    );
  }
}