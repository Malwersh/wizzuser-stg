/// مساعدات التحقق من صحة البيانات
class ValidationHelper {
  /// التحقق من صحة البريد الإلكتروني
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return emailRegex.hasMatch(email);
  }

  /// التحقق من صحة رقم الهاتف العراقي
  static bool isValidIraqiPhone(String phone) {
    // إزالة المسافات والرموز الأخرى
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    // الأنماط المقبولة:
    // 1. 10 أرقام تبدأ بـ 7: 7901234567
    // 2. 11 رقم يبدأ بـ 07: 07901234567  
    // 3. 13 رقم يبدأ بـ 964: 9647901234567
    // 4. 14 رقم يبدأ بـ +964: +9647901234567 (سيصبح 13 بعد إزالة +)
    
    String actualNumber = '';
    
    if (digitsOnly.length == 10 && digitsOnly.startsWith('7')) {
      actualNumber = digitsOnly;
    } else if (digitsOnly.length == 11 && digitsOnly.startsWith('07')) {
      actualNumber = digitsOnly.substring(1); // إزالة الـ 0
    } else if (digitsOnly.length == 13 && digitsOnly.startsWith('964')) {
      actualNumber = digitsOnly.substring(3); // إزالة 964
    } else {
      return false;
    }
    
    // التحقق من كود المشغل العراقي (790, 791, 792, 793, 794, 780, 781, 782, 783, 750, 751, 752, 753)
    List<String> validOperatorCodes = [
      '790', '791', '792', '793', '794', // زين العراق
      '780', '781', '782', '783',        // آسياسيل
      '750', '751', '752', '753'         // كورك تيليكوم وأخرى
    ];
    
    String operatorCode = actualNumber.substring(0, 3);
    return validOperatorCodes.contains(operatorCode) && actualNumber.length == 10;
  }

  /// تنسيق رقم الهاتف العراقي
  static String formatIraqiPhone(String phone) {
    // التحقق من صحة الرقم أولاً
    if (!isValidIraqiPhone(phone)) {
      return phone; // إرجاع الرقم كما هو إذا لم يكن صحيحاً
    }
    
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    if (digitsOnly.length == 10 && digitsOnly.startsWith('7')) {
      // 7901234567 -> +9647901234567
      return '+964$digitsOnly';
    } else if (digitsOnly.length == 11 && digitsOnly.startsWith('07')) {
      // 07901234567 -> +9647901234567
      return '+964${digitsOnly.substring(1)}';
    } else if (digitsOnly.length == 13 && digitsOnly.startsWith('964')) {
      // 9647901234567 -> +9647901234567
      return '+$digitsOnly';
    }
    
    // إذا لم يكن بالصيغة المتوقعة، إرجاع الرقم كما هو
    return phone;
  }

  /// تحديد نوع المدخل (إيميل أم رقم هاتف)
  static String getInputType(String input) {
    if (isValidEmail(input)) {
      return 'email';
    } else if (isValidIraqiPhone(input)) {
      return 'phone';
    } else {
      return 'unknown';
    }
  }

  /// التحقق من قوة كلمة المرور
  static bool isStrongPassword(String password) {
    // كلمة المرور يجب أن تحتوي على:
    // - 8 أحرف على الأقل
    // - حرف كبير واحد على الأقل
    // - حرف صغير واحد على الأقل
    // - رقم واحد على الأقل
    // - رمز خاص واحد على الأقل
    final passwordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$');
    return passwordRegex.hasMatch(password);
  }

  /// الحصول على رسالة خطأ لكلمة المرور الضعيفة
  static String getPasswordValidationMessage(String password) {
    if (password.length < 8) {
      return 'كلمة المرور يجب أن تحتوي على 8 أحرف على الأقل';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'كلمة المرور يجب أن تحتوي على حرف صغير واحد على الأقل';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'كلمة المرور يجب أن تحتوي على حرف كبير واحد على الأقل';
    }
    if (!password.contains(RegExp(r'\d'))) {
      return 'كلمة المرور يجب أن تحتوي على رقم واحد على الأقل';
    }
    if (!password.contains(RegExp(r'[@$!%*?&]'))) {
      return 'كلمة المرور يجب أن تحتوي على رمز خاص واحد على الأقل';
    }
    return '';
  }

  /// التحقق من صحة رقم الهاتف العراقي (بدون كود البلد)
  /// يقبل فقط: 07XXXXXXXX (11 رقم) أو 7XXXXXXXX (10 أرقام)
  static bool isValidIraqiPhoneInput(String phone) {
    if (phone.isEmpty) return false;
    
    // إزالة المسافات والفواصل
    String cleanPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    
    // التحقق من أن الرقم يحتوي على أرقام فقط
    if (!RegExp(r'^\d+$').hasMatch(cleanPhone)) {
      return false;
    }
    
    // صيغة 07XXXXXXXX (11 رقم)
    if (cleanPhone.startsWith('07') && cleanPhone.length == 11) {
      String withoutZero = cleanPhone.substring(1); // إزالة الصفر للحصول على 7XXXXXXXX
      return _isValidOperatorCode(withoutZero);
    }
    
    // صيغة 7XXXXXXXX (10 أرقام)
    if (cleanPhone.startsWith('7') && cleanPhone.length == 10) {
      return _isValidOperatorCode(cleanPhone);
    }
    
    return false;
  }
  
  /// التحقق من صحة كود المشغل العراقي
  static bool _isValidOperatorCode(String phone) {
    if (phone.length != 10 || !phone.startsWith('7')) {
      return false;
    }
    
    // أكواد المشغلين العراقيين المعتمدة
    List<String> validPrefixes = [
      '790', '791', '792', '793', '794', // زين العراق
      '780', '781', '782', '783',        // آسياسيل  
      '750', '751', '752', '753',        // كورك تيليكوم
      '770', '771'                       // أوريدو
    ];
    
    String prefix = phone.substring(0, 3);
    return validPrefixes.contains(prefix);
  }
  
  /// تحويل رقم الهاتف المدخل إلى الصيغة الكاملة مع كود البلد
  static String convertToFullPhoneNumber(String phoneInput) {
    if (!isValidIraqiPhoneInput(phoneInput)) {
      return phoneInput; // إرجاع الرقم كما هو إذا لم يكن صحيحاً
    }
    
    String cleanPhone = phoneInput.replaceAll(RegExp(r'[\s-]'), '');
    
    // إذا كان بصيغة 07XXXXXXXX، تحويله إلى +9647XXXXXXXX
    if (cleanPhone.startsWith('07') && cleanPhone.length == 11) {
      String withoutZero = cleanPhone.substring(1);
      return '+964$withoutZero';
    }
    
    // إذا كان بصيغة 7XXXXXXXX، تحويله إلى +9647XXXXXXXX
    if (cleanPhone.startsWith('7') && cleanPhone.length == 10) {
      return '+964$cleanPhone';
    }
    
    return phoneInput;
  }
  
  /// تنسيق رقم الهاتف للعرض (إضافة مسافات)
  static String formatPhoneDisplay(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    
    // صيغة 07XXXXXXXX -> 07XX XXX XXXX
    if (cleanPhone.startsWith('07') && cleanPhone.length == 11) {
      return '${cleanPhone.substring(0, 4)} ${cleanPhone.substring(4, 7)} ${cleanPhone.substring(7)}';
    }
    
    // صيغة 7XXXXXXXX -> 7XX XXX XXXX  
    if (cleanPhone.startsWith('7') && cleanPhone.length == 10) {
      return '${cleanPhone.substring(0, 3)} ${cleanPhone.substring(3, 6)} ${cleanPhone.substring(6)}';
    }
    
    return phone;
  }
}
