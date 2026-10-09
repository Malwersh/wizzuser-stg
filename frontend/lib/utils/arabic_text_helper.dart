// مساعد لمعالجة النصوص العربية والتشفير
class ArabicTextHelper {
  
  /// يقوم بتنظيف وإصلاح النصوص العربية المشوهة
  static String cleanArabicText(String text) {
    if (text.isEmpty) return text;
    
    // قائمة الأحرف المشوهة وتصحيحها
    final Map<String, String> corrections = {
      'هرفثقرشم': 'حدث خطأ',
      'سثقدثق': 'في معالجة',
      'ثققخق': 'الطلب',
      'Ã¡Ã': 'أ',
      'Ã©': 'ة', 
      'Ã­': 'ي',
      'Ã³': 'و',
      'Ãº': 'ى',
      // يمكن إضافة المزيد حسب الحاجة
    };
    
    String cleanedText = text;
    corrections.forEach((wrong, correct) {
      cleanedText = cleanedText.replaceAll(wrong, correct);
    });
    
    // إذا كان النص لا يزال مشوهاً، استخدم رسالة افتراضية
    if (_isGarbledText(cleanedText)) {
      return 'حدث خطأ غير متوقع';
    }
    
    return cleanedText;
  }
  
  /// يتحقق إذا كان النص مشوهاً أو غير قابل للقراءة
  static bool _isGarbledText(String text) {
    // تحقق من وجود رموز غريبة متتالية
    final RegExp garbledPattern = RegExp(r'[ÃÂÄÅÇÉÑÖÜàáâãäåçèéêëìíîïñòóôõöùúûüÿ]{3,}');
    return garbledPattern.hasMatch(text) || 
           text.contains('��') || // رمز الاستبدال
           _hasConsecutiveNonArabicChars(text);
  }
  
  /// يتحقق من وجود أحرف غير عربية متتالية قد تشير لمشكلة في التشفير
  static bool _hasConsecutiveNonArabicChars(String text) {
    int consecutiveCount = 0;
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final isArabic = RegExp(r'[\u0600-\u06FF\u0750-\u077F]').hasMatch(char);
      final isLatin = RegExp(r'[a-zA-Z]').hasMatch(char);
      final isSpace = char == ' ';
      
      if (!isArabic && !isSpace && !isLatin) {
        consecutiveCount++;
        if (consecutiveCount > 4) return true;
      } else {
        consecutiveCount = 0;
      }
    }
    return false;
  }
  
  /// يتحقق إذا كان النص عربياً صحيحاً
  static bool isValidArabicText(String text) {
    if (text.trim().isEmpty) return false;
    return !_isGarbledText(text);
  }
  
  /// يحول النص من UTF-8 إلى العربية إذا كان مُشفراً
  static String decodeIfNeeded(String text) {
    try {
      // محاولة فك التشفير إذا كان النص مُرمزاً
      if (text.contains('\\u')) {
        return text.replaceAllMapped(
          RegExp(r'\\u([0-9a-fA-F]{4})'),
          (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16))
        );
      }
      return text;
    } catch (e) {
      return text;
    }
  }
  
  /// رسائل خطأ افتراضية بالعربية
  static const Map<String, String> defaultErrorMessages = {
    'payment_error': 'حدث خطأ في معالجة عملية الدفع',
    'network_error': 'خطأ في الاتصال بالإنترنت',
    'server_error': 'خطأ في الخادم، يرجى المحاولة لاحقاً',
    'validation_error': 'بيانات غير صحيحة',
    'unknown_error': 'حدث خطأ غير متوقع',
  };
  
  /// يحصل على رسالة خطأ مُنسقة
  static String getErrorMessage(String? message, {String fallbackKey = 'unknown_error'}) {
    if (message == null || message.trim().isEmpty) {
      return defaultErrorMessages[fallbackKey] ?? 'حدث خطأ غير متوقع';
    }
    
    final decodedMessage = decodeIfNeeded(message);
    final cleanedMessage = cleanArabicText(decodedMessage);
    
    return isValidArabicText(cleanedMessage) ? cleanedMessage : 
           defaultErrorMessages[fallbackKey] ?? 'حدث خطأ غير متوقع';
  }
}
