import 'dart:async';
import 'dart:math';

class StripeService {
  // Stripe Test Cards - البطاقات الاختبارية
  static const Map<String, Map<String, dynamic>> testCards = {
    '4242424242424242': {
      'type': 'Visa',
      'success': true,
      'message': 'بطاقة Visa صالحة',
      'country': 'US',
      'funding': 'credit',
    },
    '4000000000000002': {
      'type': 'Visa',
      'success': false,
      'message': 'البطاقة مرفوضة - رصيد غير كافٍ',
      'country': 'US',
      'funding': 'credit',
    },
    '4000000000000069': {
      'type': 'Visa',
      'success': false,
      'message': 'البطاقة منتهية الصلاحية',
      'country': 'US',
      'funding': 'credit',
    },
    '4000000000000127': {
      'type': 'Visa',
      'success': false,
      'message': 'CVV غير صحيح',
      'country': 'US',
      'funding': 'credit',
    },
    '5555555555554444': {
      'type': 'Mastercard',
      'success': true,
      'message': 'بطاقة Mastercard صالحة',
      'country': 'US',
      'funding': 'debit',
    },
    '5200828282828210': {
      'type': 'Mastercard',
      'success': true,
      'message': 'بطاقة Mastercard صالحة',
      'country': 'US',
      'funding': 'debit',
    },
    '4000000000000341': {
      'type': 'Visa',
      'success': false,
      'message': 'رقم بطاقة غير صحيح',
      'country': 'US',
      'funding': 'credit',
    },
    '378282246310005': {
      'type': 'American Express',
      'success': true,
      'message': 'بطاقة American Express صالحة',
      'country': 'US',
      'funding': 'credit',
    },
    '371449635398431': {
      'type': 'American Express',
      'success': true,
      'message': 'بطاقة American Express صالحة',
      'country': 'US',
      'funding': 'credit',
    },
    '6011111111111117': {
      'type': 'Discover',
      'success': true,
      'message': 'بطاقة Discover صالحة',
      'country': 'US',
      'funding': 'credit',
    },
  };

  /// التحقق من صحة البطاقة باستخدام بطاقات Stripe الاختبارية
  Future<Map<String, dynamic>> validateCard({
    required String cardNumber,
    required int expiryMonth,
    required int expiryYear,
    required String cvv,
    required String cardholderName,
  }) async {
    // محاكاة تأخير شبكة حقيقي
    await Future.delayed(Duration(milliseconds: 1500 + Random().nextInt(1000)));

    try {
      // تنظيف رقم البطاقة
      final cleanCardNumber = cardNumber.replaceAll(RegExp(r'\D'), '');

      // التحقق من صحة البيانات الأساسية
      final basicValidation = _validateBasicCardData(
        cleanCardNumber,
        expiryMonth,
        expiryYear,
        cvv,
        cardholderName,
      );

      if (!basicValidation['isValid']) {
        return {
          'success': false,
          'message': basicValidation['message'],
          'errorType': 'validation_error',
        };
      }

      // التحقق من البطاقات الاختبارية
      if (testCards.containsKey(cleanCardNumber)) {
        final testCard = testCards[cleanCardNumber]!;
        
        if (testCard['success']) {
          // بطاقة صالحة
          return {
            'success': true,
            'message': testCard['message'],
            'cardType': testCard['type'],
            'funding': testCard['funding'],
            'country': testCard['country'],
            'last4': cleanCardNumber.substring(cleanCardNumber.length - 4),
            'maskedCardNumber': _maskCardNumber(cleanCardNumber),
            'transactionId': _generateTransactionId(),
            'authorizationCode': _generateAuthCode(),
            'availableBalance': _generateRandomBalance(),
          };
        } else {
          // بطاقة مرفوضة أو بها مشكلة
          return {
            'success': false,
            'message': testCard['message'],
            'cardType': testCard['type'],
            'errorType': 'card_declined',
          };
        }
      }

      // إذا لم تكن البطاقة من البطاقات الاختبارية
      // نفترض أنها بطاقة صالحة في البيئة الحقيقية
      final cardType = _getCardType(cleanCardNumber);
      
      // محاكاة نسبة نجاح 85%
      final isSuccess = Random().nextDouble() > 0.15;
      
      if (isSuccess) {
        return {
          'success': true,
          'message': 'تم التحقق من البطاقة بنجاح',
          'cardType': cardType,
          'funding': 'credit',
          'country': 'SA',
          'last4': cleanCardNumber.substring(cleanCardNumber.length - 4),
          'maskedCardNumber': _maskCardNumber(cleanCardNumber),
          'transactionId': _generateTransactionId(),
          'authorizationCode': _generateAuthCode(),
          'availableBalance': _generateRandomBalance(),
        };
      } else {
        return {
          'success': false,
          'message': 'فشل في التحقق من البطاقة - يرجى المحاولة مرة أخرى',
          'cardType': cardType,
          'errorType': 'network_error',
        };
      }

    } catch (e) {
      return {
        'success': false,
        'message': 'حدث خطأ في الشبكة - يرجى المحاولة مرة أخرى',
        'errorType': 'network_error',
      };
    }
  }

  /// معالجة الدفع الفعلي
  Future<Map<String, dynamic>> processPayment({
    required String cardNumber,
    required int expiryMonth,
    required int expiryYear,
    required String cvv,
    required String cardholderName,
    required double amount,
    required String currency,
    String? description,
  }) async {
    // محاكاة تأخير معالجة الدفع
    await Future.delayed(Duration(milliseconds: 2000 + Random().nextInt(2000)));

    try {
      // أولاً: التحقق من صحة البطاقة
      final validationResult = await validateCard(
        cardNumber: cardNumber,
        expiryMonth: expiryMonth,
        expiryYear: expiryYear,
        cvv: cvv,
        cardholderName: cardholderName,
      );

      if (!validationResult['success']) {
        return {
          'success': false,
          'message': validationResult['message'],
          'errorType': validationResult['errorType'],
        };
      }

      // ثانياً: محاكاة معالجة الدفع
      final cleanCardNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
      
      // للبطاقات الاختبارية، نستخدم قواعد خاصة
      if (testCards.containsKey(cleanCardNumber)) {
        final testCard = testCards[cleanCardNumber]!;
        
        if (testCard['success']) {
          return {
            'success': true,
            'message': 'تم الدفع بنجاح',
            'transactionId': _generateTransactionId(),
            'authorizationCode': _generateAuthCode(),
            'amount': amount,
            'currency': currency,
            'cardType': testCard['type'],
            'last4': cleanCardNumber.substring(cleanCardNumber.length - 4),
            'receipt': _generateReceipt(amount, currency, description),
          };
        } else {
          return {
            'success': false,
            'message': 'فشل في معالجة الدفع: ${testCard['message']}',
            'errorType': 'payment_declined',
          };
        }
      }

      // للبطاقات الأخرى، محاكاة نسبة نجاح
      final isSuccess = Random().nextDouble() > 0.1; // 90% نسبة نجاح
      
      if (isSuccess) {
        return {
          'success': true,
          'message': 'تم الدفع بنجاح',
          'transactionId': _generateTransactionId(),
          'authorizationCode': _generateAuthCode(),
          'amount': amount,
          'currency': currency,
          'cardType': validationResult['cardType'],
          'last4': cleanCardNumber.substring(cleanCardNumber.length - 4),
          'receipt': _generateReceipt(amount, currency, description),
        };
      } else {
        return {
          'success': false,
          'message': 'فشل في معالجة الدفع - رصيد غير كافٍ',
          'errorType': 'insufficient_funds',
        };
      }

    } catch (e) {
      return {
        'success': false,
        'message': 'حدث خطأ في معالجة الدفع',
        'errorType': 'processing_error',
      };
    }
  }

  /// التحقق من صحة البيانات الأساسية
  Map<String, dynamic> _validateBasicCardData(
    String cardNumber,
    int expiryMonth,
    int expiryYear,
    String cvv,
    String cardholderName,
  ) {
    // التحقق من رقم البطاقة
    if (cardNumber.length < 13 || cardNumber.length > 19) {
      return {
        'isValid': false,
        'message': 'رقم البطاقة يجب أن يكون بين 13-19 رقم',
      };
    }

    // التحقق من خوارزمية Luhn
    if (!_isValidLuhn(cardNumber)) {
      return {
        'isValid': false,
        'message': 'رقم البطاقة غير صحيح',
      };
    }

    // التحقق من تاريخ الانتهاء
    final currentYear = DateTime.now().year;
    final currentMonth = DateTime.now().month;
    
    if (expiryYear < currentYear || (expiryYear == currentYear && expiryMonth < currentMonth)) {
      return {
        'isValid': false,
        'message': 'البطاقة منتهية الصلاحية',
      };
    }

    if (expiryMonth < 1 || expiryMonth > 12) {
      return {
        'isValid': false,
        'message': 'شهر انتهاء الصلاحية غير صحيح',
      };
    }

    // التحقق من CVV
    if (cvv.length < 3 || cvv.length > 4) {
      return {
        'isValid': false,
        'message': 'CVV يجب أن يكون 3 أو 4 أرقام',
      };
    }

    // التحقق من اسم حامل البطاقة
    if (cardholderName.trim().isEmpty) {
      return {
        'isValid': false,
        'message': 'اسم حامل البطاقة مطلوب',
      };
    }

    return {'isValid': true};
  }

  /// التحقق من صحة رقم البطاقة باستخدام خوارزمية Luhn
  bool _isValidLuhn(String cardNumber) {
    int sum = 0;
    bool alternate = false;
    
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cardNumber[i]);
      
      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit = (digit % 10) + 1;
        }
      }
      
      sum += digit;
      alternate = !alternate;
    }
    
    return (sum % 10) == 0;
  }

  /// تحديد نوع البطاقة
  String _getCardType(String cardNumber) {
    if (cardNumber.startsWith('4')) {
      return 'Visa';
    } else if (cardNumber.startsWith('5') || cardNumber.startsWith('2')) {
      return 'Mastercard';
    } else if (cardNumber.startsWith('34') || cardNumber.startsWith('37')) {
      return 'American Express';
    } else if (cardNumber.startsWith('6011') || cardNumber.startsWith('65')) {
      return 'Discover';
    } else if (cardNumber.startsWith('35')) {
      return 'JCB';
    } else {
      return 'Unknown';
    }
  }

  /// إخفاء رقم البطاقة
  String _maskCardNumber(String cardNumber) {
    if (cardNumber.length < 4) return cardNumber;
    final last4 = cardNumber.substring(cardNumber.length - 4);
    return '**** **** **** $last4';
  }

  /// إنشاء معرف معاملة وهمي
  String _generateTransactionId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return 'TXN_${List.generate(8, (index) => chars[random.nextInt(chars.length)]).join()}';
  }

  /// إنشاء رمز تفويض وهمي
  String _generateAuthCode() {
    final random = Random();
    return List.generate(6, (index) => random.nextInt(10)).join();
  }

  /// إنشاء رصيد عشوائي للعرض
  double _generateRandomBalance() {
    final random = Random();
    return 1000 + random.nextDouble() * 9000; // رصيد بين 1000-10000
  }

  /// إنشاء إيصال وهمي
  Map<String, dynamic> _generateReceipt(double amount, String currency, String? description) {
    return {
      'transactionDate': DateTime.now().toIso8601String(),
      'amount': amount,
      'currency': currency,
      'description': description ?? 'دفع طلب طعام',
      'merchantName': 'تطبيق زاد للطعام',
      'merchantId': 'ZAAD_FOOD_APP',
      'terminalId': 'TERM_${Random().nextInt(9999).toString().padLeft(4, '0')}',
    };
  }

  /// الحصول على قائمة البطاقات الاختبارية للعرض
  static List<Map<String, dynamic>> getTestCards() {
    return [
      {
        'name': 'Visa ناجحة',
        'number': '4242 4242 4242 4242',
        'type': 'Visa',
        'success': true,
        'description': 'بطاقة اختبار ناجحة',
      },
      {
        'name': 'Visa مرفوضة',
        'number': '4000 0000 0000 0002',
        'type': 'Visa',
        'success': false,
        'description': 'بطاقة اختبار مرفوضة - رصيد غير كافٍ',
      },
      {
        'name': 'Visa منتهية',
        'number': '4000 0000 0000 0069',
        'type': 'Visa',
        'success': false,
        'description': 'بطاقة اختبار منتهية الصلاحية',
      },
      {
        'name': 'CVV خاطئ',
        'number': '4000 0000 0000 0127',
        'type': 'Visa',
        'success': false,
        'description': 'بطاقة اختبار - CVV غير صحيح',
      },
      {
        'name': 'Mastercard',
        'number': '5555 5555 5555 4444',
        'type': 'Mastercard',
        'success': true,
        'description': 'بطاقة Mastercard صالحة',
      },
      {
        'name': 'American Express',
        'number': '3782 822463 10005',
        'type': 'American Express',
        'success': true,
        'description': 'بطاقة American Express صالحة',
      },
    ];
  }

  /// محاكاة حفظ البطاقة للاستخدام المستقبلي
  Future<Map<String, dynamic>> saveCard({
    required String cardNumber,
    required int expiryMonth,
    required int expiryYear,
    required String cardholderName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1000));
    
    return {
      'success': true,
      'message': 'تم حفظ البطاقة بنجاح',
      'cardId': 'CARD_${_generateTransactionId()}',
      'maskedNumber': _maskCardNumber(cardNumber.replaceAll(RegExp(r'\D'), '')),
      'cardType': _getCardType(cardNumber.replaceAll(RegExp(r'\D'), '')),
    };
  }

  /// حذف بطاقة محفوظة
  Future<Map<String, dynamic>> deleteCard(String cardId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    return {
      'success': true,
      'message': 'تم حذف البطاقة بنجاح',
    };
  }
}
