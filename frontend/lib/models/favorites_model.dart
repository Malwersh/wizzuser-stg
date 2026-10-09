import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import '../services/favorites_service.dart';
import '../services/session_service.dart';

class FavoritesModel extends ChangeNotifier {
  List<String> _favoriteStoreIds = [];
  List<String> _favoriteDishIds = [];
  Map<String, String> _favoriteStoreLookup = {}; // businessId -> favoriteId
  bool _isInitialized = false;
  bool _isLoading = false;

  List<String> get favoriteStoreIds => _favoriteStoreIds;
  List<String> get favoriteDishIds => _favoriteDishIds;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;

  FavoritesModel() {
    initialize();
  }

  /// Get current user ID for favorites storage isolation
  Future<String> _getCurrentUserId() async {
    try {
      // Always get fresh user ID from session service
      final sessionService = SessionService.instance;
      String userId;
      
      if (sessionService.isLoggedIn && sessionService.currentUserId != null) {
        // Logged in user
        userId = sessionService.currentUserId!;
      } else if (sessionService.isGuest) {
        // Guest user
        userId = 'guest';
      } else {
        // Anonymous/unknown state
        userId = 'anonymous';
      }
      
      return userId;
    } catch (e) {
      developer.log('❌ خطأ في الحصول على معرف المستخدم: $e', name: 'FAVORITES_MODEL');
      return 'anonymous';
    }
  }

  /// Generate user-specific storage key
  Future<String> _getUserSpecificKey(String baseKey) async {
    final userId = await _getCurrentUserId();
    return '${baseKey}_$userId';
  }

  /// Clear cached user data when user changes
  void _clearUserCache() {
    // This method is kept for potential future use
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Clear user cache to ensure fresh user context
      _clearUserCache();
      
      // أولاً تحميل البيانات المحلية كـ fallback
      final prefs = await SharedPreferences.getInstance();
      
      // Load favorite stores with user-specific key
      final storeKey = await _getUserSpecificKey('favorite_stores');
      final storeIds = prefs.getStringList(storeKey) ?? [];
      _favoriteStoreIds = storeIds;
      
      // Load favorite dishes with user-specific key
      final dishKey = await _getUserSpecificKey('favorite_dishes');
      final dishIds = prefs.getStringList(dishKey) ?? [];
      _favoriteDishIds = dishIds;
      
      // محاولة تحميل البيانات من الخادم
      await _loadFavoritesFromServer();
      
      _isInitialized = true;
      
      final userId = await _getCurrentUserId();
      developer.log('✅ تم تهيئة المفضلة للمستخدم: $userId (${_favoriteStoreIds.length} مطعم، ${_favoriteDishIds.length} طبق)', 
                   name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في تهيئة المفضلة: $e', name: 'FAVORITES_MODEL');
      _isInitialized = true;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  /// تحميل المفضلة من الخادم
  Future<void> _loadFavoritesFromServer() async {
    try {
      developer.log('🔄 تحميل المفضلة من الخادم', name: 'FAVORITES_MODEL');
      
      final result = await FavoritesService.getUserFavorites();
      
      if (result['success'] == true) {
        final favorites = result['data']['favorites'] as List?;
        if (favorites != null && favorites.isNotEmpty) {
          // احتفظ بالبيانات المحلية الحالية كـ backup
          final localStoreIds = Set<String>.from(_favoriteStoreIds);
          final localLookup = Map<String, String>.from(_favoriteStoreLookup);
          
          // مسح فقط عند وجود بيانات جديدة من الخادم
          _favoriteStoreIds.clear();
          _favoriteStoreLookup.clear();
          
          for (final favorite in favorites) {
            final businessId = favorite['business_id'] ?? favorite['businessId'];
            final favoriteId = favorite['id'] ?? favorite['favoriteId'];
            
            if (businessId != null && favoriteId != null) {
              _favoriteStoreIds.add(businessId);
              _favoriteStoreLookup[businessId] = favoriteId;
            }
          }
          
          // دمج البيانات المحلية إذا لم تكن موجودة في الخادم
          for (final localStoreId in localStoreIds) {
            if (!_favoriteStoreIds.contains(localStoreId)) {
              _favoriteStoreIds.add(localStoreId);
              // احتفظ بـ lookup إذا كان موجوداً
              if (localLookup.containsKey(localStoreId)) {
                _favoriteStoreLookup[localStoreId] = localLookup[localStoreId]!;
              }
            }
          }
          
          // حفظ البيانات المدموجة محلياً
          await _saveFavoriteStores();
          
          developer.log('✅ تم تحميل ودمج ${_favoriteStoreIds.length} مطعم مفضل (${favorites.length} من الخادم، ${localStoreIds.length} محلي)', name: 'FAVORITES_MODEL');
        } else {
          developer.log('ℹ️ لا توجد مفضلة في الخادم، الاحتفاظ بالبيانات المحلية', name: 'FAVORITES_MODEL');
        }
      } else {
        developer.log('⚠️ فشل في تحميل المفضلة من الخادم: ${result['error']}، الاحتفاظ بالبيانات المحلية', name: 'FAVORITES_MODEL');
      }
    } catch (e) {
      developer.log('❌ خطأ في تحميل المفضلة من الخادم: $e', name: 'FAVORITES_MODEL');
    }
  }

  // Store favorites methods
  bool isStoreFavorite(String storeId) {
    return _favoriteStoreIds.contains(storeId);
  }

  /// تبديل حالة المفضلة للمطعم مع التفاعل مع قاعدة البيانات
  Future<void> toggleStoreFavorite(
    String storeId, 
    String storeName, {
    String? storeImage,
    String? storeCategory,
  }) async {
    try {
      developer.log('🔄 تبديل مفضلة المطعم: $storeName', name: 'FAVORITES_MODEL');
      
      final wasAlreadyFavorite = _favoriteStoreIds.contains(storeId);
      
      if (wasAlreadyFavorite) {
        // إزالة من المفضلة
        await _removeStoreFavorite(storeId);
      } else {
        // إضافة للمفضلة  
        await _addStoreFavorite(storeId, storeName, storeImage, storeCategory);
      }
      
    } catch (e) {
      developer.log('❌ خطأ في تبديل مفضلة المطعم: $e', name: 'FAVORITES_MODEL');
      throw Exception('فشل في تحديث المفضلة: $e');
    }
  }

  /// إضافة مطعم للمفضلة
  Future<void> _addStoreFavorite(String storeId, String storeName, String? storeImage, String? storeCategory) async {
    try {
      developer.log('➕ إضافة مطعم للمفضلة: $storeName', name: 'FAVORITES_MODEL');
      
      // 1. أولاً تحقق من الحالة في الخادم لتجنب الإضافة المكررة
      final statusResult = await FavoritesService.checkFavoriteStatus(businessId: storeId);
      
      if (statusResult['success'] == true && statusResult['data']['is_favorite'] == true) {
        // المطعم موجود بالفعل في الخادم، فقط أضفه للمحلي
        final favoriteId = statusResult['data']['favoriteId'];
        if (!_favoriteStoreIds.contains(storeId)) {
          _favoriteStoreIds.add(storeId);
          if (favoriteId != null) {
            _favoriteStoreLookup[storeId] = favoriteId;
          }
          notifyListeners();
          await _saveFavoriteStores();
        }
        developer.log('✅ المطعم موجود بالفعل في الخادم، تم تحديث المحلي فقط', name: 'FAVORITES_MODEL');
        return;
      }
      
      // 2. إضافة محلياً للاستجابة السريعة
      if (!_favoriteStoreIds.contains(storeId)) {
        _favoriteStoreIds.add(storeId);
        notifyListeners();
        await _saveFavoriteStores();
      }
      
      // 3. إضافة للخادم
      final result = await FavoritesService.addToFavorites(
        businessId: storeId,
        businessName: storeName,
        businessImage: storeImage ?? '',
        businessCategory: storeCategory ?? '',
      );
      
      if (result['success'] == true) {
        // حفظ favoriteId للاستخدام في الحذف لاحقاً
        final favoriteId = result['data']?['id'];
        if (favoriteId != null) {
          _favoriteStoreLookup[storeId] = favoriteId;
        }
        
        // تأكد من حفظ البيانات محلياً مع التحديث الجديد
        await _saveFavoriteStores();
        
        developer.log('✅ تم إضافة المطعم للمفضلة بنجاح وحفظ محلياً', name: 'FAVORITES_MODEL');
      } else {
        // إذا فشلت العملية على الخادم، إزالة من المحلي
        _favoriteStoreIds.remove(storeId);
        notifyListeners();
        await _saveFavoriteStores();
        throw Exception(result['error'] ?? 'فشل في إضافة المطعم للمفضلة');
      }
      
    } catch (e) {
      developer.log('❌ خطأ في إضافة المطعم للمفضلة: $e', name: 'FAVORITES_MODEL');
      rethrow;
    }
  }

  /// إزالة مطعم من المفضلة
  Future<void> _removeStoreFavorite(String storeId) async {
    try {
      developer.log('➖ إزالة مطعم من المفضلة: $storeId', name: 'FAVORITES_MODEL');
      
      // البحث عن favoriteId
      String? favoriteId = _favoriteStoreLookup[storeId];
      
      if (favoriteId == null) {
        // محاولة البحث عن favoriteId من الخادم
        final statusResult = await FavoritesService.checkFavoriteStatus(businessId: storeId);
        if (statusResult['success'] == true && statusResult['data']['is_favorite'] == true) {
          favoriteId = statusResult['data']['favoriteId'];
        }
      }
      
      if (favoriteId == null) {
        developer.log('⚠️ لم يتم العثور على favoriteId للمطعم $storeId', name: 'FAVORITES_MODEL');
        // إزالة محلياً فقط
        _favoriteStoreIds.remove(storeId);
        _favoriteStoreLookup.remove(storeId);
        notifyListeners();
        await _saveFavoriteStores();
        return;
      }
      
      // إزالة محلياً أولاً للاستجابة السريعة
      _favoriteStoreIds.remove(storeId);
      _favoriteStoreLookup.remove(storeId);
      notifyListeners();
      await _saveFavoriteStores();
      
      // إزالة من الخادم
      final result = await FavoritesService.removeFromFavorites(favoriteId: favoriteId);
      
      if (result['success'] == true) {
        developer.log('✅ تم إزالة المطعم من المفضلة بنجاح', name: 'FAVORITES_MODEL');
      } else {
        // إذا فشلت العملية على الخادم، إعادة إضافة للمحلي
        _favoriteStoreIds.add(storeId);
        _favoriteStoreLookup[storeId] = favoriteId;
        notifyListeners();
        await _saveFavoriteStores();
        throw Exception(result['error'] ?? 'فشل في إزالة المطعم من المفضلة');
      }
      
    } catch (e) {
      developer.log('❌ خطأ في إزالة المطعم من المفضلة: $e', name: 'FAILURES_MODEL');
      rethrow;
    }
  }

  Future<void> _saveFavoriteStores() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storeKey = await _getUserSpecificKey('favorite_stores');
      await prefs.setStringList(storeKey, _favoriteStoreIds);
      
      final userId = await _getCurrentUserId();
      developer.log('💾 تم حفظ مفضلة المطاعم للمستخدم $userId: ${_favoriteStoreIds.length} مطعم', 
                   name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في حفظ مفضلة المطاعم: $e', name: 'FAVORITES_MODEL');
    }
  }

  // Dish favorites methods (تبقى كما هي لأنها محلية فقط)
  bool isDishFavorite(String dishId) {
    return _favoriteDishIds.contains(dishId);
  }

  Future<void> toggleDishFavorite(String dishId) async {
    try {
      if (_favoriteDishIds.contains(dishId)) {
        _favoriteDishIds.remove(dishId);
      } else {
        _favoriteDishIds.add(dishId);
      }
      
      await _saveFavoriteDishes();
      notifyListeners();
    } catch (e) {
      developer.log('❌ خطأ في تبديل مفضلة الطبق: $e', name: 'FAVORITES_MODEL');
    }
  }

  Future<void> addDishFavorite(String dishId) async {
    if (!_favoriteDishIds.contains(dishId)) {
      _favoriteDishIds.add(dishId);
      await _saveFavoriteDishes();
      notifyListeners();
    }
  }

  Future<void> removeDishFavorite(String dishId) async {
    if (_favoriteDishIds.contains(dishId)) {
      _favoriteDishIds.remove(dishId);
      await _saveFavoriteDishes();
      notifyListeners();
    }
  }

  Future<void> _saveFavoriteDishes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dishKey = await _getUserSpecificKey('favorite_dishes');
      await prefs.setStringList(dishKey, _favoriteDishIds);
      
      final userId = await _getCurrentUserId();
      developer.log('💾 تم حفظ مفضلة الأطباق للمستخدم $userId: ${_favoriteDishIds.length} طبق', 
                   name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في حفظ مفضلة الأطباق: $e', name: 'FAVORITES_MODEL');
    }
  }

  // Additional methods for API integration
  Future<void> loadFavoritesFromServer() async {
    await _loadFavoritesFromServer();
  }

  Future<bool> checkRestaurantFavoriteStatus(String restaurantId) async {
    try {
      final result = await FavoritesService.checkFavoriteStatus(businessId: restaurantId);
      if (result['success'] == true) {
        final isFavorite = result['data']['is_favorite'] ?? false;
        final favoriteId = result['data']['favoriteId'];
        
        // تحديث الحالة المحلية
        if (isFavorite && !_favoriteStoreIds.contains(restaurantId)) {
          _favoriteStoreIds.add(restaurantId);
          if (favoriteId != null) {
            _favoriteStoreLookup[restaurantId] = favoriteId;
          }
          await _saveFavoriteStores();
          notifyListeners();
        } else if (!isFavorite && _favoriteStoreIds.contains(restaurantId)) {
          _favoriteStoreIds.remove(restaurantId);
          _favoriteStoreLookup.remove(restaurantId);
          await _saveFavoriteStores();
          notifyListeners();
        }
        
        return isFavorite;
      }
      
      // إذا فشل الطلب، استخدام الحالة المحلية
      return isStoreFavorite(restaurantId);
    } catch (e) {
      developer.log('❌ خطأ في فحص حالة المطعم المفضل: $e', name: 'FAVORITES_MODEL');
      return isStoreFavorite(restaurantId);
    }
  }

  /// Clear all favorites (useful for logout)
  Future<void> clearAllFavorites() async {
    try {
      final userId = await _getCurrentUserId();
      developer.log('🧹 مسح جميع المفضلة للمستخدم: $userId', name: 'FAVORITES_MODEL');
      
      // Clear in-memory data
      _favoriteStoreIds.clear();
      _favoriteDishIds.clear();
      _favoriteStoreLookup.clear();
      
      // Clear from local storage
      final prefs = await SharedPreferences.getInstance();
      final storeKey = await _getUserSpecificKey('favorite_stores');
      final dishKey = await _getUserSpecificKey('favorite_dishes');
      
      await prefs.remove(storeKey);
      await prefs.remove(dishKey);
      
      // Clear user cache to ensure fresh context
      _clearUserCache();
      
      notifyListeners();
      developer.log('✅ تم مسح جميع المفضلة للمستخدم: $userId', name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في مسح المفضلة: $e', name: 'FAVORITES_MODEL');
    }
  }

  /// إعادة تعيين المفضلة للمستخدم الجديد
  Future<void> resetForNewUser() async {
    try {
      developer.log('🔄 بدء إعادة تعيين المفضلة للمستخدم الجديد', name: 'FAVORITES_MODEL');
      
      // Clear cache first to ensure fresh user context
      _clearUserCache();
      
      // Clear current data completely
      _favoriteStoreIds.clear();
      _favoriteDishIds.clear();
      _favoriteStoreLookup.clear();
      
      // Reset initialization state
      _isInitialized = false;
      
      // Notify UI immediately
      notifyListeners();
      
      // Re-initialize for new user
      await initialize();
      
      final userId = await _getCurrentUserId();
      developer.log('✅ تم إعادة تعيين المفضلة للمستخدم الجديد: $userId (${_favoriteStoreIds.length} مطعم)', name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في إعادة تعيين المفضلة: $e', name: 'FAVORITES_MODEL');
    }
  }

  /// إعادة تحميل المفضلة من الخادم (للاستخدام عند تسجيل الدخول)
  Future<void> refreshFavoritesFromServer() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _loadFavoritesFromServer();
    } catch (e) {
      developer.log('❌ خطأ في إعادة تحميل المفضلة: $e', name: 'FAVORITES_MODEL');
    }
    
    _isLoading = false;
    notifyListeners();
  }

  /// مزامنة البيانات المحلية مع الخادم
  Future<void> syncWithServer() async {
    try {
      developer.log('🔄 بدء مزامنة المفضلة مع الخادم', name: 'FAVORITES_MODEL');
      
      // رفع البيانات المحلية إلى الخادم أولاً
      await _uploadLocalFavoritesToServer();
      
      // ثم تحميل البيانات من الخادم
      await _loadFavoritesFromServer();
      
      developer.log('✅ تم إكمال مزامنة المفضلة', name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في مزامنة المفضلة: $e', name: 'FAVORITES_MODEL');
    }
  }

  /// رفع البيانات المحلية إلى الخادم
  Future<void> _uploadLocalFavoritesToServer() async {
    try {
      // رفع المطاعم المفضلة المحلية إلى الخادم
      for (final storeId in _favoriteStoreIds) {
        // تحقق من وجود favoriteId (يعني أنه موجود في الخادم)
        if (!_favoriteStoreLookup.containsKey(storeId)) {
          developer.log('⬆️ رفع مطعم محلي للخادم: $storeId', name: 'FAVORITES_MODEL');
          
          // محاولة إضافة المطعم للخادم
          final result = await FavoritesService.addToFavorites(
            businessId: storeId,
            businessName: 'مطعم محفوظ محلياً',
            businessImage: '',
            businessCategory: 'عام',
          );
          
          if (result['success'] == true) {
            final favoriteId = result['data']?['id'];
            if (favoriteId != null) {
              _favoriteStoreLookup[storeId] = favoriteId;
              developer.log('✅ تم رفع المطعم للخادم: $storeId', name: 'FAVORITES_MODEL');
            }
          } else {
            developer.log('⚠️ فشل رفع المطعم للخادم: $storeId', name: 'FAVORITES_MODEL');
          }
        }
      }
    } catch (e) {
      developer.log('❌ خطأ في رفع البيانات المحلية: $e', name: 'FAVORITES_MODEL');
    }
  }

  /// إعادة تحميل المفضلة من الخادم بعد تسجيل الدخول
  Future<void> reloadAfterLogin() async {
    developer.log('🔄 بدء إعادة تحميل المفضلة للمستخدم الجديد...', name: 'FAVORITES_MODEL');
    
    try {
      // مسح البيانات المحلية القديمة بشكل كامل
      await _clearAllLocalFavoritesData();
      
      // إعادة تهيئة كاملة للنموذج
      _isInitialized = false;
      _favoriteStoreIds.clear();
      _favoriteDishIds.clear();
      _favoriteStoreLookup.clear();
      _clearUserCache();
      
      // إعادة تهيئة من الصفر
      await initialize();
      
      developer.log('✅ تم إعادة تحميل المفضلة للمستخدم الجديد بنجاح', name: 'FAVORITES_MODEL');
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في إعادة تحميل المفضلة: $e', name: 'FAVORITES_MODEL');
      developer.log('Stack trace: $stackTrace', name: 'FAVORITES_MODEL');
    }
  }

  /// مسح جميع بيانات المفضلة المحلية (لجميع المستخدمين)
  Future<void> _clearAllLocalFavoritesData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // الحصول على جميع المفاتيح
      final keys = prefs.getKeys();
      
      // مسح جميع مفاتيح المفضلة (التي تحتوي على favorite_stores أو favorite_dishes)
      final favoritesKeys = keys.where((key) => 
        key.contains('favorite_stores') || 
        key.contains('favorite_dishes') ||
        key.contains('favorite_lookup')
      ).toList();
      
      for (final key in favoritesKeys) {
        await prefs.remove(key);
        developer.log('🗑️ تم مسح مفتاح التخزين المحلي: $key', name: 'FAVORITES_MODEL');
      }
      
      developer.log('✅ تم مسح جميع بيانات المفضلة المحلية', name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في مسح بيانات المفضلة المحلية: $e', name: 'FAVORITES_MODEL');
    }
  }

  /// تحميل المفضلة من التخزين المحلي للمستخدم الحالي
  Future<void> loadFavoritesFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load favorite stores with user-specific key
      final storeKey = await _getUserSpecificKey('favorite_stores');
      final storeIds = prefs.getStringList(storeKey) ?? [];
      _favoriteStoreIds = storeIds;
      
      // Load favorite dishes with user-specific key
      final dishKey = await _getUserSpecificKey('favorite_dishes');
      final dishIds = prefs.getStringList(dishKey) ?? [];
      _favoriteDishIds = dishIds;
      
      final userId = await _getCurrentUserId();
      developer.log('📱 تم تحميل ${_favoriteStoreIds.length} مطعم من التخزين المحلي للمستخدم: $userId', name: 'FAVORITES_MODEL');
    } catch (e) {
      developer.log('❌ خطأ في تحميل المفضلة من التخزين المحلي: $e', name: 'FAVORITES_MODEL');
    }
  }
}