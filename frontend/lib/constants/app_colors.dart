import 'package:flutter/material.dart';

/// ألوان التطبيق المحسنة - Wizz App Simple & Clean Colors
/// نهج بسيط: خلفيات بيضاء، نصوص سوداء، الألوان الأساسية للأيقونات والأزرار فقط
class AppColors {
  // ========================================
  // الألوان الأساسية - للأيقونات والأزرار فقط
  // ========================================
  static const Color primary = Color(0xFFFDC500);      // Primary (Mikado yellow) - للأيقونات والأزرار
  static const Color secondary = Color(0xFF00509D);    // Secondary (Polynesian blue) - للتحميل والحالات الثانوية
  
  // تدرجات الألوان الأساسية (للاستخدام المحدود)
  static const Color primaryLight = Color(0xFFFED500);  // ذهبي فاتح - للهوفر
  static const Color primaryDark = Color(0xFFE6B200);   // ذهبي غامق - للضغط
  static const Color secondaryLight = Color(0xFF0066CC); // أزرق فاتح - للهوفر
  static const Color secondaryDark = Color(0xFF00296B);  // أزرق غامق - للضغط
  
  // ========================================
  // الألوان الأساسية - للخلفيات والنصوص
  // ========================================
  
  // خلفيات - دائماً بيضاء
  static const Color surface = Color(0xFFFFFFFF);       // خلفية أساسية بيضاء
  static const Color background = Color(0xFFFFFFFF);    // خلفية التطبيق بيضاء
  static const Color white = Color(0xFFFFFFFF);         // أبيض نقي
  
  // نصوص - دائماً سوداء أو رمادية
  static const Color textPrimary = Color(0xFF000000);   // نص أساسي أسود نقي
  static const Color textSecondary = Color(0xFF666666); // نص ثانوي رمادي
  static const Color textTertiary = Color(0xFF999999);  // نص ثالثي رمادي فاتح
  static const Color black = Color(0xFF000000);         // أسود نقي
  
  // ألوان الحدود والفواصل
  static const Color border = Color(0xFFE0E0E0);        // حدود رمادية فاتحة
  static const Color divider = Color(0xFFF0F0F0);       // فواصل رمادية فاتحة جداً
  static const Color grey = Color(0xFF9E9E9E);          // رمادي متوسط
  static const Color lightGrey = Color(0xFFF5F5F5);     // رمادي فاتح للخلفيات الثانوية
  
  // ========================================
  // ألوان الحالة - بسيطة ووضاحة
  // ========================================
  static const Color success = Color(0xFF4CAF50);       // أخضر للنجاح
  static const Color warning = Color(0xFFFF9800);       // برتقالي للتحذير
  static const Color error = Color(0xFFF44336);         // أحمر للخطأ
  static const Color info = Color(0xFF2196F3);          // أزرق للمعلومات
  
  // ========================================
  // ألوان النصوص على الخلفيات الملونة
  // ========================================
  static const Color textOnPrimary = Color(0xFF000000); // نص أسود على اللون الأساسي (أصفر)
  static const Color textOnSecondary = Color(0xFFFFFFFF); // نص أبيض على اللون الثانوي (أزرق)
  static const Color textOnSurface = Color(0xFF000000); // نص أسود على الخلفية البيضاء
  static const Color textOnSuccess = Color(0xFFFFFFFF); // نص أبيض على الأخضر
  static const Color textOnWarning = Color(0xFF000000); // نص أسود على البرتقالي
  static const Color textOnError = Color(0xFFFFFFFF);   // نص أبيض على الأحمر
  
  // ========================================
  // ألوان قديمة للتوافق (مهملة - ستتم إزالتها لاحقاً)
  // ========================================
  @deprecated
  static const Color accent = Color(0xFFFFD500);
  @deprecated
  static const Color accentLight = Color(0xFFFFF500);
  @deprecated
  static const Color accentDark = Color(0xFFFFCC00);
  @deprecated
  static const Color charcoalBlack = Color(0xFF2C2C2C);
  @deprecated
  static const Color darkGrey = Color(0xFF424242);
  @deprecated
  static const Color backgroundPrimary = Color(0xFFFDC500);
  @deprecated
  static const Color backgroundSecondary = Color(0xFF00509D);
  @deprecated
  static const Color backgroundAccent = Color(0xFFFFD500);
  @deprecated
  static const Color backgroundDark = Color(0xFF00296B);
  @deprecated
  static const Color textOnAccent = Color(0xFF000000);
  @deprecated
  static const Color textOnDark = Color(0xFFFFFFFF);
}

/// أنماط النصوص المحسنة - بسيطة ونظيفة
class WizzTextStyles {
  // شعار Wizz الرئيسي - بسيط بدون ظلال مفرطة
  static const TextStyle logo = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w800,
    color: AppColors.white,
    fontFamily: 'serif',
    letterSpacing: 2,
    shadows: [
      Shadow(
        color: Colors.black26,
        offset: Offset(2, 2),
        blurRadius: 4,
      ),
    ],
  );
  
  // شعار Wizz في الأيقونة - بسيط
  static const TextStyle logoIcon = TextStyle(
    fontSize: 68,
    fontWeight: FontWeight.w900,
    color: AppColors.secondary,
    fontFamily: 'serif',
  );
  
  // النص الفرعي في splash - بسيط
  static const TextStyle subtitle = TextStyle(
    fontSize: 18,
    color: AppColors.white,
    fontWeight: FontWeight.w500,
  );
  
  // نص التحميل - بسيط
  static const TextStyle loading = TextStyle(
    fontSize: 16,
    color: AppColors.white,
    fontWeight: FontWeight.w500,
  );
  
  // أنماط النصوص الأساسية للتطبيق
  static const TextStyle headingLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textTertiary,
  );
}

/// تزيينات بسيطة ونظيفة
class WizzDecorations {
  // تزيين أيقونة الشعار - بسيط
  static BoxDecoration logoContainer = BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(70),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
  
  // خلفية splash - بسيطة
  static const BoxDecoration splashBackground = BoxDecoration(
    color: AppColors.secondary, // أزرق بسيط
  );
  
  // تزيين البطاقات - بسيط
  static BoxDecoration cardDecoration = BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
  
  // تزيين الأزرار - بسيط
  static BoxDecoration buttonDecoration = BoxDecoration(
    color: AppColors.primary,
    borderRadius: BorderRadius.circular(8),
  );
  
  // تزيين الحقول - بسيط
  static BoxDecoration inputDecoration = BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: AppColors.border,
      width: 1,
    ),
  );
}
