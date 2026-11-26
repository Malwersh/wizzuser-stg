import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// موضوع التطبيق المحسن - بسيط ونظيف
/// يتبع مبدأ: خلفيات بيضاء، نصوص سوداء، الألوان الأساسية للأيقونات والأزرار فقط
class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,

      // ========================================
      // الألوان الأساسية
      // ========================================
      primarySwatch: _createMaterialColor(AppColors.primary),
      primaryColor: AppColors.primary,

      // مخطط الألوان البسيط - النصوص دائماً سوداء
      colorScheme: const ColorScheme.light(
        // الألوان الأساسية
        primary: AppColors.primary,
        onPrimary: AppColors.secondaryDark,
        primaryContainer: Color(0xFFFFF8E6),
        onPrimaryContainer: AppColors.textPrimary,

        // الألوان الثانوية
        secondary: AppColors.secondary,
        onSecondary: AppColors.textOnSecondary,
        secondaryContainer: Color(0xFFEDF2FA),
        onSecondaryContainer: AppColors.secondaryDark,

        // الألوان الثالثية
        tertiary: AppColors.primary,
        onTertiary: AppColors.textOnPrimary,
        tertiaryContainer: AppColors.white,
        onTertiaryContainer: AppColors.textPrimary,

        // ألوان الخلفية والأسطح
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary, // أسود نقي
        surfaceVariant: AppColors.lightGrey,
        onSurfaceVariant: AppColors.textSecondary, // رمادي
        // الخلفية الرئيسية
        background: AppColors.background, // خلفية بيضاء
        onBackground: AppColors.textPrimary, // نص أسود
        // ألوان الحالة
        error: AppColors.error,
        onError: AppColors.textOnError,
        errorContainer: AppColors.lightGrey,
        onErrorContainer: AppColors.error,

        // حدود وخطوط
        outline: AppColors.border,
        outlineVariant: AppColors.divider,

        // إزالة أي تأثيرات لونية
        surfaceTint: Colors.transparent,
        shadow: Colors.black26,
        scrim: Colors.black54,

        // ألوان الانعكاس
        inverseSurface: AppColors.textPrimary,
        onInverseSurface: AppColors.white,
        inversePrimary: AppColors.white,
      ),

      // ========================================
      // خلفيات التطبيق - دائماً بيضاء
      // ========================================
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,

      // ========================================
      // شريط التطبيق العلوي
      // ========================================
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: GoogleFonts.notoSansArabic().fontFamily,
        ),
      ),

      // ========================================
      // شريط التنقل السفلي
      // ========================================
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamily: GoogleFonts.notoSansArabic().fontFamily,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          fontFamily: GoogleFonts.notoSansArabic().fontFamily,
        ),
      ),

      // ========================================
      // الأزرار
      // ========================================
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondaryDark,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.secondaryDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondaryDark,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: GoogleFonts.notoSansArabic().fontFamily,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondaryDark,
          side: BorderSide(color: AppColors.secondaryDark, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: GoogleFonts.notoSansArabic().fontFamily,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: GoogleFonts.notoSansArabic().fontFamily,
          ),
        ),
      ),

      // ========================================
      // البطاقات
      // ========================================
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      ),

      // ========================================
      // حقول الإدخال
      // ========================================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.error),
        ),
        labelStyle: TextStyle(
          color: AppColors.textSecondary,
          fontFamily: GoogleFonts.notoSansArabic().fontFamily,
        ),
        hintStyle: TextStyle(
          color: AppColors.textTertiary,
          fontFamily: GoogleFonts.notoSansArabic().fontFamily,
        ),
      ),

      // ========================================
      // النصوص
      // ========================================
      textTheme: GoogleFonts.notoSansArabicTextTheme(
        TextTheme(
          // عناوين كبيرة - أسود
          headlineLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary, // أسود
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary, // أسود
          ),
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary, // أسود
          ),

          // عناوين عادية - أسود
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary, // أسود
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary, // أسود
          ),
          titleSmall: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary, // أسود
          ),

          // نصوص عادية - أسود
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: AppColors.textPrimary, // أسود
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.textPrimary, // أسود
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: AppColors.textSecondary, // رمادي
          ),

          // تسميات - أسود/رمادي
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary, // أسود
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary, // أسود
          ),
          labelSmall: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            color: AppColors.textSecondary, // رمادي
          ),
        ),
      ),

      // ========================================
      // أيقونات وعناصر أخرى
      // ========================================
      iconTheme: IconThemeData(
        color: AppColors.textPrimary, // أيقونات سوداء
        size: 24,
      ),

      primaryIconTheme: IconThemeData(
        color: AppColors.textOnPrimary, // أيقونات سوداء على الأصفر
        size: 24,
      ),

      // تأكد من النصوص السوداء في كل مكان
      brightness: Brightness.light,

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondaryDark,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ========================================
      // الخط والكثافة البصرية
      // ========================================
      fontFamily: GoogleFonts.notoSansArabic().fontFamily,
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // ========================================
      // إعدادات إضافية لفرض النصوص السوداء
      // ========================================
      // فرض لون النصوص في ListTile والعناصر المشابهة
      listTileTheme: ListTileThemeData(
        textColor: AppColors.textPrimary,
        iconColor: AppColors.textPrimary,
      ),

      // إعدادات الـ tabs
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
      ),

      // إعدادات الـ Switch و Checkbox
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.primary),
        trackColor: WidgetStateProperty.all(
          AppColors.primary.withValues(alpha: 0.3),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.all(AppColors.primary),
        checkColor: WidgetStateProperty.all(AppColors.textOnPrimary),
      ),
    );
  }

  // إنشاء MaterialColor من لون واحد
  static MaterialColor _createMaterialColor(Color color) {
    List strengths = <double>[.05];
    Map<int, Color> swatch = {};
    final int r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }

    for (double strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }
}
