import 'package:flutter/foundation.dart';
import '../services/session_service.dart';
import '../models/cart_model.dart';
import '../models/cart_item.dart';
import '../models/dish.dart';
import '../models/session_state.dart';
import '../models/business_suggestion_data.dart';

/// Main application state provider that manages global app state
/// Integrates with SessionService for session management
class AppStateProvider extends ChangeNotifier {
  final SessionService _sessionService = SessionService.instance;
  
  // Cart state
  final CartModel _cart = CartModel();
  
  // User state
  Map<String, dynamic>? _currentUser;
  bool _isLoggedIn = false;
  bool _isGuest = false;
  
  // Loading states
  bool _isLoading = false;
  
  // 🔥 بيانات المطعم للاقتراحات
  Map<String, BusinessSuggestionData> _businessSuggestionData = {};
  
  AppStateProvider() {
    _initializeState();
  }
  
  // Getters
  CartModel get cart => _cart;
  Map<String, dynamic>? get currentUser => _currentUser;
  Map<String, dynamic>? get userData => _currentUser; // Alias for backward compatibility
  bool get isLoggedIn => _isLoggedIn;
  bool get isGuest => _isGuest;
  bool get isLoading => _isLoading;
  
  // 🔥 Getter لبيانات الاقتراحات
  BusinessSuggestionData? getBusinessSuggestionData(String storeId) {
    return _businessSuggestionData[storeId];
  }
  
  // 🔥 Method لحفظ بيانات المطعم للاقتراحات
  void setBusinessSuggestionData(String storeId, BusinessSuggestionData data) {
    _businessSuggestionData[storeId] = data;
    notifyListeners();
  }
  
  // 🔥 Method لحذف بيانات المطعم عند تفريغ السلة
  void clearBusinessSuggestionData(String storeId) {
    _businessSuggestionData.remove(storeId);
    notifyListeners();
  }
  
  // Cart getters for backward compatibility
  List<Map<String, dynamic>> get cartItems => _cart.items.map((item) => {
    'id': item.dish.id,
    'name': item.dish.name,
    'description': item.dish.description,
    'image': item.dish.imageUrls.isNotEmpty ? item.dish.imageUrls.first : '',
    'price': item.unitPrice,
    'base_price': item.unitPrice,
    'quantity': item.quantity,
    'store_id': item.storeId,
    'special_instructions': item.specialInstructions,
    'selected_options': item.selectedOptions.map((k, v) => MapEntry(k, v.toList())),
  }).toList();
  int get cartItemsCount => _cart.itemCount;
  double get cartTotal => _cart.totalAmount;
  
  // Initialize state and listen to session changes
  Future<void> _initializeState() async {
    // Listen to session changes
    _sessionService.sessionStateStream.listen((sessionState) async {
      final previousUserId = _currentUser?['userId'] ?? _currentUser?['user_id'];
      
      if (sessionState is SessionActive) {
        final newUserId = sessionState.userData['userId'] ?? sessionState.userData['user_id'];
        _isLoggedIn = true;
        _isGuest = false;
        _currentUser = sessionState.userData;
        
        // إذا تغير المستخدم، أعد تحميل السلة
        if (previousUserId != newUserId) {
          debugPrint('🔄 تغيير المستخدم من $previousUserId إلى $newUserId - إعادة تحميل السلة');
          await _cart.clearOnSessionChange();
        }
      } else {
        // 🔧 إصلاح: دائماً ارجع إلى حالة الضيف عند عدم وجود جلسة نشطة
        _isLoggedIn = false;
        _isGuest = true; // دائماً true للضيوف
        _currentUser = null;
        
        // إذا كان هناك مستخدم سابق، أعد تحميل سلة الضيف
        if (previousUserId != null && previousUserId != 'guest') {
          debugPrint('🔄 تغيير من المستخدم $previousUserId إلى الضيف - إعادة تحميل السلة');
          await _cart.clearOnSessionChange();
        }
      }
      notifyListeners();
    });
    
    // Initialize with current session state
    final sessionState = _sessionService.currentSessionState;
    if (sessionState is SessionActive) {
      _isLoggedIn = true;
      _isGuest = false;
      _currentUser = sessionState.userData;
    } else {
      // 🔧 إصلاح: دائماً ارجع إلى حالة الضيف عند عدم وجود جلسة نشطة
      _isLoggedIn = false;
      _isGuest = true; // دائماً true للضيوف
      _currentUser = null;
    }
    notifyListeners();
  }
  
  // Login methods
  Future<Map<String, dynamic>> login(String email, String password) async {
    _setLoading(true);
    try {
      // فحص صحة البيانات المدخلة
      if (email.trim().isEmpty || password.isEmpty) {
        return {
          'success': false, 
          'message': 'يرجى إدخال البريد الإلكتروني وكلمة المرور.'
        };
      }
      
      // استخدام loginWithDetails للحصول على رسائل الخطأ التفصيلية
      final result = await _sessionService.loginWithDetails(email.trim(), password);
      return result;
      
    } catch (e) {
      // Log the actual error for debugging
      print('AppStateProvider login error: $e');
      return {
        'success': false,
        'message': 'خطأ في الاتصال بالخادم. يرجى المحاولة مرة أخرى.'
      };
    } finally {
      _setLoading(false);
    }
  }
  
  Future<bool> loginAsGuest() async {
    _setLoading(true);
    try {
      final success = await _sessionService.loginAsGuest();
      return success;
    } finally {
      _setLoading(false);
    }
  }
  
  // Logout
  Future<void> logout() async {
    _setLoading(true);
    try {
      await _sessionService.logout();
      _cart.clear(); // Clear cart on logout
    } finally {
      _setLoading(false);
    }
  }
  
  // Loading state management
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }
  
  // User management
  void updateUser(Map<String, dynamic>? user) {
    if (_currentUser != user) {
      _currentUser = user;
      notifyListeners();
    }
  }
  
  // Session status helpers
  String? get userId => _currentUser?['userId'] ?? _currentUser?['user_id'];
  String? get userEmail => _currentUser?['email'];
  bool get hasValidSession => _isLoggedIn || _isGuest;
  
  // Cart methods for backward compatibility
  Future<bool> addToCart(Map<String, dynamic> item) async {
    try {
      // إنشاء Dish من البيانات المرسلة
      final dish = Dish(
        id: item['id'] as String,
        name: item['name'] as String,
        description: item['description'] as String? ?? '',
        imageUrls: [item['image'] as String? ?? ''].where((url) => url.isNotEmpty).toList(),
        likesPercent: 85, // قيمة افتراضية
        likesCount: 100, // قيمة افتراضية
        basePrice: (item['base_price'] as num?)?.toDouble() ?? (item['price'] as num).toDouble(),
        optionGroups: [], // قيمة افتراضية
      );
      
      // إنشاء CartItem من البيانات المرسلة
      final quantity = item['quantity'] as int;
      final unitPrice = (item['base_price'] as num?)?.toDouble() ?? (item['price'] as num).toDouble();
      
      final cartItem = CartItem(
        storeId: item['store_id'] as String,
        dish: dish,
        quantity: quantity,
        unitPrice: unitPrice,
        totalPrice: unitPrice * quantity, // حساب السعر الإجمالي بناءً على السعر الأساسي والكمية
        selectedOptions: (item['selected_options'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, Set<String>.from(v as List<dynamic>))
        ) ?? {},
        specialInstructions: item['special_instructions'] as String?,
      );
      
      // التحقق من المطعم إذا كانت السلة تحتوي على عناصر من مطعم آخر
      if (_cart.currentStoreId != null && _cart.currentStoreId != cartItem.storeId) {
        // إرجاع خطأ مطعم مختلف للتعامل معه في الواجهة
        setError('DIFFERENT_STORE');
        return false;
      }
      
      // إضافة العنصر للسلة
      _cart.addItem(cartItem);
      
      // مسح أي خطأ سابق
      clearError();
      
      debugPrint('✅ تم إضافة العنصر للسلة بنجاح: ${item['name']}');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('خطأ في إضافة العنصر للسلة: $e');
      debugPrint('البيانات المرسلة: $item');
      setError('حدث خطأ في إضافة العنصر للسلة');
      return false;
    }
  }
  
  Future<bool> removeFromCart(String itemId) async {
    try {
      // البحث عن العنصر وحذفه
      final itemToRemove = _cart.items.firstWhere(
        (item) => item.dish.id == itemId,
        orElse: () => throw Exception('العنصر غير موجود'),
      );
      
      _cart.removeItem(itemToRemove);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('خطأ في حذف العنصر من السلة: $e');
      return false;
    }
  }
  
  Future<void> clearCart() async {
    _cart.clear();
    notifyListeners();
  }
  
  List<Map<String, dynamic>> getCartItemsForStore(String storeId) {
    return _cart.items
        .where((item) => item.storeId == storeId)
        .map((item) => item.toJson())
        .toList();
  }
  
  int getCartItemsCountForStore(String storeId) {
    return _cart.items.where((item) => item.storeId == storeId).length;
  }
  
  bool hasCartItemsForStore(String storeId) {
    return _cart.items.any((item) => item.storeId == storeId);
  }
  
  double getCartTotalForStore(String storeId) {
    return _cart.items
        .where((item) => item.storeId == storeId)
        .fold(0.0, (sum, item) => sum + item.totalPrice);
  }
  
  Future<void> updateCartItemQuantity(dynamic itemId, int newQuantity, [String? storeId]) async {
    try {
      // إذا كان itemId رقماً (index)، استخدمه مباشرة
      if (itemId is int) {
        if (itemId >= 0 && itemId < _cart.items.length) {
          final itemToUpdate = _cart.items[itemId];
          _cart.updateItemQuantity(itemToUpdate, newQuantity);
          notifyListeners();
          return;
        }
      }
      
      // وإلا، ابحث بالمعرف
      final itemToUpdate = _cart.items.firstWhere(
        (item) => item.dish.id == itemId.toString(),
        orElse: () => throw Exception('العنصر غير موجود'),
      );
      
      // تحديث الكمية
      _cart.updateItemQuantity(itemToUpdate, newQuantity);
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في تحديث كمية العنصر: $e');
    }
  }
  
  // Error handling
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }
  
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
  
  // Additional methods for backward compatibility
  Future<void> checkForUserChange() async {
    // Check if session state has changed and update accordingly
    final sessionState = _sessionService.currentSessionState;
    if (sessionState is SessionActive) {
      if (_currentUser != sessionState.userData) {
        _currentUser = sessionState.userData;
        _isLoggedIn = true;
        _isGuest = false;
        notifyListeners();
      }
    } else {
      // 🔧 إصلاح: دائماً ارجع إلى حالة الضيف عند عدم وجود جلسة نشطة
      if (_isLoggedIn || !_isGuest) {
        _currentUser = null;
        _isLoggedIn = false;
        _isGuest = true; // دائماً true للضيوف
        notifyListeners();
      }
    }
  }
  
  // App initialization method
  Future<void> initializeApp() async {
    _setLoading(true);
    try {
      await _initializeState();
      await _cart.loadFromStorage(); // Load cart from storage
    } finally {
      _setLoading(false);
    }
  }
}