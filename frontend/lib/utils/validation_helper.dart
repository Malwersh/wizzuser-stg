import 'iraqi_phone.dart';

/// مساعدات التحقق من صحة البيانات
class ValidationHelper {
  /// التحقق من صحة البريد الإلكتروني
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return emailRegex.hasMatch(email);
  }

  /// التحقق من صحة رقم الهاتف العراقي
  static bool isValidIraqiPhone(String phone) => IraqiPhone.valid(phone);

  /// تنسيق رقم الهاتف العراقي
  static String formatIraqiPhone(String phone) => IraqiPhone.display(phone);

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
    final passwordRegex = RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
    );
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
  static bool isValidIraqiPhoneInput(String phone) => IraqiPhone.valid(phone);

  /// تحويل رقم الهاتف المدخل إلى الصيغة الكاملة مع كود البلد
  static String convertToFullPhoneNumber(String phoneInput) =>
      IraqiPhone.display(phoneInput);

  /// تنسيق رقم الهاتف للعرض (إضافة مسافات)
  static String formatPhoneDisplay(String phone) => IraqiPhone.display(phone);
}
