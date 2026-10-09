import 'package:flutter/foundation.dart';

class UserService extends ChangeNotifier {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  // بيانات المستخدم
  int _currentPoints = 1250; // النقاط الحالية
  final List<Map<String, dynamic>> _validCoupons = [
    {
      'id': '1',
      'code': 'SAVE20',
      'title': 'خصم 20%',
      'description': 'خصم 20% على جميع الطلبات',
      'discount': '20%',
      'discountValue': 20,
      'discountType': 'percentage', // percentage or fixed
      'expiry': '2025-12-31',
      'minOrder': 50.0,
      'isFromRewards': false,
      'status': 'valid',
      'createdAt': DateTime.now(),
    },
    {
      'id': '2',
      'code': 'WELCOME10',
      'title': 'خصم ترحيبي',
      'description': 'خصم 10% للمستخدمين الجدد',
      'discount': '10%',
      'discountValue': 10,
      'discountType': 'percentage',
      'expiry': '2025-06-30',
      'minOrder': 25.0,
      'isFromRewards': false,
      'status': 'valid',
      'createdAt': DateTime.now(),
    },
  ];

  final List<Map<String, dynamic>> _usedCoupons = [];
  final List<Map<String, dynamic>> _expiredCoupons = [];

  // قائمة المكافآت المتاحة
  final List<Map<String, dynamic>> _availableRewards = [
    {
      'id': 'reward_1',
      'title': 'خصم 15%',
      'description': 'خصم 15% على طلبك القادم',
      'points': 200,
      'discount': '15%',
      'discountValue': 15,
      'discountType': 'percentage',
      'category': 'discount',
      'validityDays': 30,
      'minOrder': 30.0,
    },
    {
      'id': 'reward_2',
      'title': 'خصم 25%',
      'description': 'خصم 25% على الطلبات أكثر من 100 ريال',
      'points': 350,
      'discount': '25%',
      'discountValue': 25,
      'discountType': 'percentage',
      'category': 'discount',
      'validityDays': 15,
      'minOrder': 100.0,
    },
    {
      'id': 'reward_3',
      'title': 'توصيل مجاني',
      'description': 'توصيل مجاني لطلبك القادم',
      'points': 150,
      'discount': 'توصيل مجاني',
      'discountValue': 0,
      'discountType': 'free_delivery',
      'category': 'delivery',
      'validityDays': 7,
      'minOrder': 0.0,
    },
    {
      'id': 'reward_4',
      'title': 'خصم 50 ريال',
      'description': 'خصم ثابت 50 ريال على طلبك',
      'points': 500,
      'discount': '50 ر.س',
      'discountValue': 50,
      'discountType': 'fixed',
      'category': 'discount',
      'validityDays': 30,
      'minOrder': 150.0,
    },
    {
      'id': 'reward_5',
      'title': 'وجبة مجانية',
      'description': 'احصل على وجبة مجانية مع طلبك',
      'points': 800,
      'discount': 'وجبة مجانية',
      'discountValue': 0,
      'discountType': 'free_item',
      'category': 'food',
      'validityDays': 14,
      'minOrder': 80.0,
    },
    {
      'id': 'reward_6',
      'title': 'خصم 30%',
      'description': 'خصم 30% على طلبات المطاعم الفاخرة',
      'points': 600,
      'discount': '30%',
      'discountValue': 30,
      'discountType': 'percentage',
      'category': 'premium',
      'validityDays': 21,
      'minOrder': 200.0,
    },
  ];

  // بيانات المستخدم الشخصية
  final bool _isLoggedIn = true; // محاكاة تسجيل الدخول
  String _userName = 'أحمد محمد العلي';
  String _userPhone = '+964 770 123 4567';
  Map<String, String> _userAddress = {
    'governorate': 'بغداد',
    'district': 'الكرخ',
    'neighborhood': 'المنصور',
    'landmark': 'بالقرب من مول المنصور',
    'fullAddress': 'شارع الأميرات، بناية رقم 15، الطابق الثالث'
  };

  // Getters
  int get currentPoints => _currentPoints;
  List<Map<String, dynamic>> get validCoupons => List.unmodifiable(_validCoupons);
  List<Map<String, dynamic>> get usedCoupons => List.unmodifiable(_usedCoupons);
  List<Map<String, dynamic>> get expiredCoupons => List.unmodifiable(_expiredCoupons);
  List<Map<String, dynamic>> get availableRewards => List.unmodifiable(_availableRewards);

  // Getters for user data
  bool get isLoggedIn => _isLoggedIn;
  String get userName => _userName;
  String get userPhone => _userPhone;
  Map<String, String> get userAddress => Map.unmodifiable(_userAddress);

  // إضافة نقاط (للاستخدام المستقبلي مع الباك إند)
  Future<bool> addPoints(int points, {String? reason}) async {
    try {
      _currentPoints += points;
      notifyListeners();
      
      // هنا يمكن إضافة استدعاء API للباك إند
      // await apiService.addUserPoints(points, reason);
      
      if (kDebugMode) {
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
      }
      return false;
    }
  }

  // استبدال النقاط بمكافأة
  Future<Map<String, dynamic>?> redeemReward(String rewardId) async {
    try {
      final reward = _availableRewards.firstWhere(
        (r) => r['id'] == rewardId,
        orElse: () => {},
      );

      if (reward.isEmpty) {
        throw Exception('المكافأة غير موجودة');
      }

      final requiredPoints = reward['points'] as int;
      if (_currentPoints < requiredPoints) {
        throw Exception('نقاط غير كافية');
      }

      // خصم النقاط
      _currentPoints -= requiredPoints;

      // إنشاء قسيمة جديدة
      final newCoupon = _createCouponFromReward(reward);
      _validCoupons.add(newCoupon);

      notifyListeners();

      // هنا يمكن إضافة استدعاء API للباك إند
      // await apiService.redeemReward(rewardId, requiredPoints);

      if (kDebugMode) {
      }

      return newCoupon;
    } catch (e) {
      if (kDebugMode) {
      }
      return null;
    }
  }

  // إضافة قسيمة يدوياً
  Future<bool> addCoupon(String code) async {
    try {
      // التحقق من أن القسيمة غير موجودة مسبقاً
      final existingCoupon = _validCoupons.any((c) => c['code'] == code);
      if (existingCoupon) {
        throw Exception('القسيمة موجودة مسبقاً');
      }

      // هنا يمكن إضافة استدعاء API للتحقق من صحة القسيمة
      // final couponData = await apiService.validateCoupon(code);

      // بيانات وهمية للاختبار
      final newCoupon = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'code': code.toUpperCase(),
        'title': 'قسيمة خصم',
        'description': 'قسيمة خصم صالحة',
        'discount': '10%',
        'discountValue': 10,
        'discountType': 'percentage',
        'expiry': DateTime.now().add(const Duration(days: 30)).toString().split(' ')[0],
        'minOrder': 25.0,
        'isFromRewards': false,
        'createdAt': DateTime.now(),
      };

      _validCoupons.add(newCoupon);
      notifyListeners();

      if (kDebugMode) {
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
      }
      return false;
    }
  }

  // استخدام قسيمة
  Future<bool> useCoupon(String couponId) async {
    try {
      final couponIndex = _validCoupons.indexWhere((c) => c['id'] == couponId);
      if (couponIndex == -1) {
        throw Exception('القسيمة غير موجودة');
      }

      final coupon = _validCoupons[couponIndex];
      
      // نقل القسيمة إلى قائمة المستخدمة
      coupon['usedAt'] = DateTime.now();
      _usedCoupons.add(coupon);
      _validCoupons.removeAt(couponIndex);

      notifyListeners();

      // هنا يمكن إضافة استدعاء API للباك إند
      // await apiService.useCoupon(couponId);

      if (kDebugMode) {
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
      }
      return false;
    }
  }

  // التحقق من القسائم المنتهية الصلاحية
  void checkExpiredCoupons() {
    final now = DateTime.now();
    final expiredCoupons = <Map<String, dynamic>>[];

    _validCoupons.removeWhere((coupon) {
      final expiryDate = DateTime.parse(coupon['expiry']);
      if (expiryDate.isBefore(now)) {
        coupon['expiredAt'] = now;
        expiredCoupons.add(coupon);
        return true;
      }
      return false;
    });

    if (expiredCoupons.isNotEmpty) {
      _expiredCoupons.addAll(expiredCoupons);
      notifyListeners();
      
      if (kDebugMode) {
      }
    }
  }

  // إنشاء قسيمة من مكافأة
  Map<String, dynamic> _createCouponFromReward(Map<String, dynamic> reward) {
    final expiryDate = DateTime.now().add(Duration(days: reward['validityDays'] ?? 30));
    final couponCode = _generateCouponCode(reward['category']);

    return {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'code': couponCode,
      'title': reward['title'],
      'description': reward['description'],
      'discount': reward['discount'],
      'discountValue': reward['discountValue'],
      'discountType': reward['discountType'],
      'expiry': expiryDate.toString().split(' ')[0],
      'minOrder': reward['minOrder'],
      'isFromRewards': true,
      'rewardId': reward['id'],
      'createdAt': DateTime.now(),
    };
  }

  // توليد كود قسيمة عشوائي
  String _generateCouponCode(String category) {
    final prefixes = {
      'discount': 'DISC',
      'delivery': 'DELV',
      'food': 'FOOD',
      'premium': 'PREM',
    };
    
    final prefix = prefixes[category] ?? 'COUP';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    
    return '$prefix$timestamp';
  }

  // تحديث بيانات المستخدم (للاستخدام مع الباك إند)
  Future<void> syncUserData() async {
    try {
      // هنا يمكن إضافة استدعاء API لمزامنة البيانات
      // final userData = await apiService.getUserData();
      // _currentPoints = userData['points'];
      // _validCoupons.clear();
      // _validCoupons.addAll(userData['coupons']);
      
      checkExpiredCoupons();
      notifyListeners();
      
      if (kDebugMode) {
      }
    } catch (e) {
      if (kDebugMode) {
      }
    }
  }

  // دالة جلب بيانات المستخدم من الباك إند
  Future<Map<String, dynamic>> fetchUserProfile() async {
    try {
      // TODO: Replace with actual API call to backend
      // final response = await http.get(
      //   Uri.parse('${baseUrl}/api/user/profile'),
      //   headers: {
      //     'Authorization': 'Bearer $userToken',
      //     'Content-Type': 'application/json',
      //   },
      // );
      
      // محاكاة استجابة الباك إند
      await Future.delayed(const Duration(seconds: 1));
      
      return {
        'success': true,
        'data': {
          'name': _userName,
          'phone': _userPhone,
          'address': _userAddress,
        },
      };
    } catch (e) {
      if (kDebugMode) {
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  // دالة تحديث عنوان المستخدم
  Future<Map<String, dynamic>> updateUserAddress(Map<String, String> newAddress) async {
    try {
      // TODO: Replace with actual API call to backend
      // final response = await http.put(
      //   Uri.parse('${baseUrl}/api/user/address'),
      //   headers: {
      //     'Authorization': 'Bearer $userToken',
      //     'Content-Type': 'application/json',
      //   },
      //   body: json.encode(newAddress),
      // );
      
      // محاكاة استجابة الباك إند
      await Future.delayed(const Duration(seconds: 1));
      
      // تحديث البيانات المحلية
      _userAddress = Map.from(newAddress);
      notifyListeners();
      
      if (kDebugMode) {
      }
      
      return {
        'success': true,
        'message': 'تم تحديث العنوان بنجاح',
        'data': newAddress,
      };
    } catch (e) {
      if (kDebugMode) {
      }
      
      return {
        'success': false,
        'message': 'فشل في تحديث العنوان',
        'error': e.toString(),
      };
    }
  }

  // دالة تحديث اسم المستخدم
  Future<bool> updateUserName(String newName) async {
    try {
      // TODO: Replace with actual API call
      await Future.delayed(const Duration(milliseconds: 500));
      
      _userName = newName;
      notifyListeners();
      
      return true;
    } catch (e) {
      if (kDebugMode) {
      }
      return false;
    }
  }

  // دالة تحديث رقم الهاتف
  Future<bool> updateUserPhone(String newPhone) async {
    try {
      // TODO: Replace with actual API call
      await Future.delayed(const Duration(milliseconds: 500));
      
      _userPhone = newPhone;
      notifyListeners();
      
      return true;
    } catch (e) {
      if (kDebugMode) {
      }
      return false;
    }
  }

  // إعادة تعيين البيانات (للاختبار)
  void resetData() {
    _currentPoints = 1250;
    _validCoupons.clear();
    _usedCoupons.clear();
    _expiredCoupons.clear();
    
    // إضافة بيانات وهمية
    _validCoupons.addAll([
      {
        'id': '1',
        'code': 'SAVE20',
        'title': 'خصم 20%',
        'description': 'خصم 20% على جميع الطلبات',
        'discount': '20%',
        'discountValue': 20,
        'discountType': 'percentage',
        'expiry': '2025-12-31',
        'minOrder': 50.0,
        'isFromRewards': false,
        'createdAt': DateTime.now(),
      },
      {
        'id': '2',
        'code': 'WELCOME10',
        'title': 'خصم ترحيبي',
        'description': 'خصم 10% للمستخدمين الجدد',
        'discount': '10%',
        'discountValue': 10,
        'discountType': 'percentage',
        'expiry': '2025-06-30',
        'minOrder': 25.0,
        'isFromRewards': false,
        'createdAt': DateTime.now(),
      },
    ]);
    
    notifyListeners();
    
    if (kDebugMode) {
    }
  }
}
