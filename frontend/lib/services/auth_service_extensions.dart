// إضافة temporary للدوال المفقودة في AuthService
import 'dart:developer' as developer;

class AuthServiceExtensions {
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
}
