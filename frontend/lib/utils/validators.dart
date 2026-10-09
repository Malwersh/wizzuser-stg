// lib/utils/validators.dart

class Validators {
  // التحقق من الاسم
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'يرجى إدخال الاسم الكامل';
    }
    if (value.trim().length < 2) {
      return 'يجب أن يحتوي الاسم على حرفين على الأقل';
    }
    if (value.trim().length > 50) {
      return 'يجب أن يكون الاسم أقل من 50 حرف';
    }
    return null;
  }

  // التحقق من البريد الإلكتروني (اختياري)
  static String? validateOptionalEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // البريد اختياري
    }
    
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
      return 'يرجى إدخال بريد إلكتروني صحيح';
    }
    
    return null;
  }

  // التحقق من رقم الهاتف العراقي
  static String? validateIraqiPhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'رقم الهاتف مطلوب';
    }

    // إزالة المسافات والرموز
    String phone = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // معالجة كود الدولة
    if (phone.startsWith('+964')) {
      phone = phone.substring(4);
    } else if (phone.startsWith('964')) {
      phone = phone.substring(3);
    }
    
    // التأكد من وجود 0 في البداية
    if (!phone.startsWith('0')) {
      phone = '0$phone';
    }
    
    // التحقق من التنسيق: 07XXXXXXXX أو 08XXXXXXXX (10 أرقام)
    if (phone.length != 10) {
      return 'رقم الهاتف يجب أن يحتوي على 10 أرقام';
    }
    
    if (!phone.startsWith('07') && !phone.startsWith('08')) {
      return 'رقم الهاتف يجب أن يبدأ بـ 07 أو 08';
    }
    
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      return 'رقم الهاتف يجب أن يحتوي على أرقام فقط';
    }

    return null;
  }

  // التحقق من كلمة المرور
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'كلمة المرور مطلوبة';
    }
    
    if (value.length < 8) {
      return 'كلمة المرور يجب أن تحتوي على 8 أحرف على الأقل';
    }

    // التحقق من الحروف العربية أو الإنجليزية
    bool hasArabic = hasArabicLetters(value);
    bool hasEnglish = hasEnglishLetters(value);
    
    if (!hasArabic && !hasEnglish) {
      return 'كلمة المرور يجب أن تحتوي على حروف أبجدية';
    }

    // إذا كانت تحتوي على حروف إنجليزية، تحقق من الكبيرة والصغيرة
    if (hasEnglish && !hasEnglishRequirement(value)) {
      return 'كلمة المرور يجب أن تحتوي على حروف كبيرة وصغيرة باللغة الإنجليزية';
    }

    if (!hasNumber(value)) {
      return 'كلمة المرور يجب أن تحتوي على رقم واحد على الأقل';
    }

    if (!hasSpecialChar(value)) {
      return 'كلمة المرور يجب أن تحتوي على رمز خاص واحد على الأقل';
    }

    return null;
  }

  // التحقق من تطابق كلمة المرور
  static String? validateConfirmPassword(String? value, String? originalPassword) {
    if (value == null || value.isEmpty) {
      return 'تأكيد كلمة المرور مطلوب';
    }
    
    if (value != originalPassword) {
      return 'كلمة المرور غير متطابقة';
    }
    
    return null;
  }

  // وظائف مساعدة للتحقق من متطلبات كلمة المرور
  static bool hasArabicLetters(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  static bool hasEnglishLetters(String value) {
    return RegExp(r'[a-zA-Z]').hasMatch(value);
  }

  static bool hasEnglishRequirement(String value) {
    if (!hasEnglishLetters(value)) return true; // إذا لم تحتوي على إنجليزية، فالشرط محقق
    return RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value);
  }

  static bool hasNumber(String value) {
    return RegExp(r'[0-9]').hasMatch(value);
  }

  static bool hasSpecialChar(String value) {
    return RegExp(r'[@#$%^&*_\-+=!,.?/]').hasMatch(value);
  }
}
