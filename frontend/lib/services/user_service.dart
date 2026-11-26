import 'package:flutter/foundation.dart';
import 'order_service.dart';
import 'pending_offer.dart';
import 'session_service.dart';

class UserService extends ChangeNotifier {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal() {
    SessionService.instance.addListener(() {
      final account = SessionService.instance.currentUserId;
      if (account != _couponAccount) {
        _couponAccount = account;
        resetData();
      }
    });
  }
  String? _couponAccount = SessionService.instance.currentUserId;

  final int _currentPoints = 0;
  final List<Map<String, dynamic>> _validCoupons = [];
  final List<Map<String, dynamic>> _usedCoupons = [];
  final List<Map<String, dynamic>> _expiredCoupons = [];
  final List<Map<String, dynamic>> _availableRewards = [];
  bool couponsLoading = false;
  String? couponsError;
  int _couponRequest = 0;

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

  // Rewards and redemption require server records. Checkout owns usage.
  Future<bool> addPoints(int points, {String? reason}) async => false;
  Future<Map<String, dynamic>?> redeemReward(String rewardId) async => null;
  Future<bool> useCoupon(String couponId) async => false;

  // Selecting a code is provisional; branch/cart eligibility is checked at checkout.
  Future<bool> addCoupon(String code) async {
    final normalized = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9_-]{1,40}$').hasMatch(normalized)) return false;
    PendingOffer.selectCode(normalized, null);
    return true;
  }

  void checkExpiredCoupons() {
    _validCoupons.removeWhere((coupon) {
      final end = DateTime.tryParse(coupon['expiry']?.toString() ?? '');
      return end != null && !end.isAfter(DateTime.now());
    });
  }

  Future<void> syncUserData() async {
    final request = ++_couponRequest;
    final account = SessionService.instance.currentUserId;
    _validCoupons.clear();
    couponsLoading = true;
    couponsError = null;
    notifyListeners();
    try {
      final offers = await OrderService().getActivePromoCodes(throwOnError: true);
      if (request != _couponRequest || account != SessionService.instance.currentUserId) return;
      _validCoupons.addAll(offers.map((offer) => <String, dynamic>{
        'id': offer.code, 'code': offer.code, 'title': offer.title,
        'description': [offer.description, offer.termsSummary].where((s) => s.isNotEmpty).join('\n'),
        'discount': offer.displayValue, 'discountValue': offer.value,
        'discountType': offer.type, 'expiry': offer.endDate?.toIso8601String() ?? 'غير محدد',
        'minOrder': offer.minOrderAmount, 'isFromRewards': false,
      }));
    } catch (_) {
      if (request == _couponRequest) couponsError = 'تعذر تحميل العروض. أعد المحاولة.';
    } finally {
      if (request == _couponRequest) {
        couponsLoading = false;
        notifyListeners();
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

  void resetData() {
    _couponRequest++;
    _validCoupons.clear();
    _usedCoupons.clear();
    _expiredCoupons.clear();
    couponsLoading = false;
    couponsError = null;
    notifyListeners();
  }
}
