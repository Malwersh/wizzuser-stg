import 'dart:math';

/// نتيجة التحقق من البطاقة
class ValidationResult {
  final bool isValid;
  final String message;
  final String? cardType;
  final String? maskedNumber;
  final Map<String, dynamic>? details;

  const ValidationResult({
    required this.isValid,
    required this.message,
    this.cardType,
    this.maskedNumber,
    this.details,
  });
}

/// خدمة التحقق من البطاقات المصرفية (محاكاة متقدمة)
class CardValidationService {

  /// التحقق من صحة رقم البطاقة باستخدام خوارزمية Luhn
  bool _validateCardNumberWithLuhn(String cardNumber) {
    final cleanNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanNumber.length < 13 || cleanNumber.length > 19) return false;

    int sum = 0;
    bool alternate = false;
    
    for (int i = cleanNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cleanNumber[i]);
      
      if (alternate) {
        digit *= 2;
        if (digit > 9) digit = (digit % 10) + 1;
      }
      
      sum += digit;
      alternate = !alternate;
    }
    
    return sum % 10 == 0;
  }

  /// تحديد نوع البطاقة
  String _getCardType(String cardNumber) {
    final cleanNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    
    if (cleanNumber.startsWith('4')) return 'Visa';
    if (cleanNumber.startsWith(RegExp(r'^5[1-5]'))) return 'Mastercard';
    if (cleanNumber.startsWith(RegExp(r'^3[47]'))) return 'American Express';
    if (cleanNumber.startsWith('6')) return 'Discover';
    if (cleanNumber.startsWith(RegExp(r'^35'))) return 'JCB';
    
    return 'Unknown';
  }

  /// إخفاء رقم البطاقة للأمان
  String _maskCardNumber(String cardNumber) {
    final cleanNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanNumber.length < 4) return cardNumber;
    
    final lastFour = cleanNumber.substring(cleanNumber.length - 4);
    return '**** **** **** $lastFour';
  }

  /// التحقق من تاريخ الانتهاء
  bool _validateExpiryDate(String expiry) {
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(expiry)) return false;
    
    final parts = expiry.split('/');
    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);
    
    if (month == null || year == null || month < 1 || month > 12) return false;
    
    final now = DateTime.now();
    final expiryDate = DateTime(2000 + year, month + 1);
    
    return expiryDate.isAfter(now);
  }

  /// التحقق من رمز CVV
  bool _validateCVV(String cvv, String cardType) {
    if (cardType == 'American Express') {
      return cvv.length == 4 && RegExp(r'^\d{4}$').hasMatch(cvv);
    }
    return cvv.length == 3 && RegExp(r'^\d{3}$').hasMatch(cvv);
  }

  /// محاكاة التحقق من البطاقة مع بوابة الدفع
  Future<ValidationResult> validateCard({
    required String cardNumber,
    required String holderName,
    required String expiryDate,
    required String cvv,
  }) async {
    try {
      // محاكاة زمن الاستجابة
      await Future.delayed(Duration(seconds: 2 + Random().nextInt(2)));
      
      final cleanCardNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
      
      // التحقق من البيانات الأساسية
      if (holderName.trim().isEmpty) {
        return const ValidationResult(
          isValid: false,
          message: 'اسم حامل البطاقة مطلوب',
        );
      }
      
      if (!_validateCardNumberWithLuhn(cardNumber)) {
        return const ValidationResult(
          isValid: false,
          message: 'رقم البطاقة غير صحيح',
        );
      }
      
      if (!_validateExpiryDate(expiryDate)) {
        return const ValidationResult(
          isValid: false,
          message: 'تاريخ انتهاء البطاقة غير صحيح أو منتهي',
        );
      }
      
      final cardType = _getCardType(cardNumber);
      if (!_validateCVV(cvv, cardType)) {
        return ValidationResult(
          isValid: false,
          message: 'رمز CVV غير صحيح (${cardType == 'American Express' ? '4' : '3'} أرقام)',
        );
      }
      
      // محاكاة سيناريوهات مختلفة للاختبار
      if (cleanCardNumber.endsWith('0002')) {
        return const ValidationResult(
          isValid: false,
          message: 'البطاقة مرفوضة - رصيد غير كافي',
        );
      }
      
      if (cleanCardNumber.endsWith('0119')) {
        return const ValidationResult(
          isValid: false,
          message: 'البطاقة مرفوضة - بيانات غير صحيحة',
        );
      }
      
      if (cleanCardNumber.endsWith('0127')) {
        return const ValidationResult(
          isValid: false,
          message: 'البطاقة مرفوضة - تم رفضها من قبل البنك',
        );
      }
      
      if (cleanCardNumber.endsWith('0051')) {
        return const ValidationResult(
          isValid: false,
          message: 'البطاقة منتهية الصلاحية',
        );
      }
      
      if (cleanCardNumber.endsWith('0078')) {
        return const ValidationResult(
          isValid: false,
          message: 'البطاقة مغلقة أو محظورة',
        );
      }
      
      // نجح التحقق
      return ValidationResult(
        isValid: true,
        message: 'تم التحقق من البطاقة بنجاح',
        cardType: cardType,
        maskedNumber: _maskCardNumber(cardNumber),
        details: {
          'holderName': holderName,
          'expiryDate': expiryDate,
          'balance': 'متاح',
          'limits': 'طبيعية',
          'securityChecks': 'مكتملة',
        },
      );
      
    } catch (e) {
      return const ValidationResult(
        isValid: false,
        message: 'حدث خطأ أثناء التحقق من البطاقة. يرجى المحاولة مرة أخرى.',
      );
    }
  }
  
  /// الحصول على رسائل المساعدة للمستخدم
  List<String> getHelpMessages() {
    return [
      '• تأكد من إدخال رقم البطاقة كاملاً',
      '• تحقق من تاريخ انتهاء البطاقة',
      '• تأكد من أن البطاقة مفعلة للدفع الإلكتروني',
      '• تحقق من توفر رصيد كافي',
      '• تأكد من صحة رمز CVV',
    ];
  }
  
  /// أرقام بطاقات تجريبية للاختبار
  Map<String, String> getTestCards() {
    return {
      '4242424242424242': 'نجح ✅',
      '4000000000000002': 'رصيد غير كافي ❌',
      '4000000000000119': 'بيانات غير صحيحة ❌',
      '4000000000000127': 'مرفوضة من البنك ❌',
      '4000000000000051': 'منتهية الصلاحية ❌',
      '4000000000000078': 'البطاقة محظورة ❌',
    };
  }
}