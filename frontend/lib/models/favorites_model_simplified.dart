import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import '../services/favorites_service.dart';
import '../services/session_service.dart';

/// نموذج مبسط للمفضلة يعمل أولاً مع قاعدة البيانات
class FavoritesModelSimplified extends ChangeNotifier {
  List<String> _favoriteStoreIds = [];
  List<String> _favoriteDishIds = [];
  Map<String, String> _favoriteStoreLookup = {}; // businessId -> favoriteId
  bool _isInitialized = false;
  bool _isLoading = false;

  // Cache for current user ID
  String? _currentUserId;

  List<String> get favoriteStoreIds => _favoriteStoreIds;
  List<String> get favoriteDishIds => _favoriteDishIds;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;

  FavoritesModelSimplified() {
    initialize();
  }

  /// Get current user ID for favorites storage isolation
  Future<String> _getCurrentUserId() async {
    if (_currentUserId != null) return _currentUserId!;
    
    try {
      final userId = SessionService.instance.currentUserId ?? 'anonymous';
      _currentUserId = userId;
      return userId;
    } catch (e) {
      _currentUserId = 'anonymous';
      return _currentUserId!;
    }
  }

  /// Generate user-specific storage key
  Future<String> _getUserSpecificKey(String baseKey) async {
    final userId = await _getCurrentUserId();
    return '${baseKey}_$userId';
  }

  /// Clear cached user ID when user changes
  void _clearUserCache() {
    _currentUserId = null;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Clear user cache to ensure fresh user context
      _clearUserCache();
      
      // 1. تحميل البيانات من الخادم أولاً
      await _loadFavoritesFromServer();
      
      // 2. إذا فشل تحميل من الخادم، تحميل من التخزين المحلي
      if (_favoriteStoreIds.isEmpty) {
        await _loadFavoritesFromLocal();
      }
      
      _isInitialized = true;
      
      final userId = await _getCurrentUserId();
      developer.log('✅ تم تهيئة المفضلة المبسطة للمستخدم: $userId (${_favoriteStoreIds.length} مطعم، ${_favoriteDishIds.length} طبق)', 
                   name: 'FAVORITES_SIMPLIFIED');
    } catch (e) {
      developer.log('❌ خطأ في تهيئة المفضلة: $e', name: 'FAVORITES_SIMPLIFIED');
      // في حال فشل كل شيء، حاول تحميل من المحلي كآخر محاولة
      await _loadFavoritesFromLocal();
      _isInitialized = true;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  /// تحميل المفضلة من الخادم (مصدر الحقيقة الأساسي)
  Future<void> _loadFavoritesFromServer() async {
    try {
      developer.log('🔄 تحميل المفضلة من الخادم', name: 'FAVORITES_SIMPLIFIED');
      
      final result = await FavoritesService.getUserFavorites();
      
      if (result['success'] == true) {
        final favorites = result['data']['favorites'] as List?;
        if (favorites != null && favorites.isNotEmpty) {
          developer.log('📥 تم استلام ${favorites.length} مفضلة من الخادم', name: 'FAVORITES_SIMPLIFIED');
          
          // مسح البيانات المحلية واستبدالها بالبيانات من الخادم
          _favoriteStoreIds.clear();
          _favoriteStoreLookup.clear();
          
          // إضافة البيانات من الخادم فقط
          for (final favorite in favorites) {
            final businessId = favorite['business_id'] ?? favorite['businessId'];
            final favoriteId = favorite['id'] ?? favorite['favoriteId'];
            
            if (businessId != null && favoriteId != null) {
              _favoriteStoreIds.add(businessId);
              _favoriteStoreLookup[businessId] = favoriteId;
              developer.log('➕ إضافة مفضلة من الخادم: $businessId -> $favoriteId', name: 'FAVORITES_SIMPLIFIED');
            }
          }
          
          // حفظ البيانات محلياً (لتسريع التحميل التالي)
          await _saveFavoritesToLocal();
          
          developer.log('✅ تم تحميل ${_favoriteStoreIds.length} مطعم مفضل من الخادم وحفظه محلياً', name: 'FAVORITES_SIMPLIFIED');
        } else {
          developer.log('ℹ️ لا توجد مفضلة في الخادم', name: 'FAVORITES_SIMPLIFIED');
        }
      } else {
        developer.log('⚠️ فشل في تحميل المفضلة من الخادم: ${result['error']}', name: 'FAVORITES_SIMPLIFIED');
        throw Exception(result['error']);
      }
    } catch (e) {
      developer.log('❌ خطأ في تحميل المفضلة من الخادم: $e', name: 'FAVORITES_SIMPLIFIED');
      rethrow;
    }
  }

  /// تحميل المفضلة من التخزين المحلي (كـ fallback فقط)
  Future<void> _loadFavoritesFromLocal() async {
    try {
      developer.log('🔄 تحميل المفضلة من التخزين المحلي', name: 'FAVORITES_SIMPLIFIED');
      
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
      developer.log('📱 تم تحميل ${_favoriteStoreIds.length} مطعم و ${_favoriteDishIds.length} طبق من التخزين المحلي للمستخدم: $userId', 
                   name: 'FAVORITES_SIMPLIFIED');
    } catch (e) {
      developer.log('❌ خطأ في تحميل المفضلة من التخزين المحلي: $e', name: 'FAVORITES_SIMPLIFIED');
    }
  }

  /// حفظ المفضلة محلياً (للتخزين المؤقت فقط)
  Future<void> _saveFavoritesToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final storeKey = await _getUserSpecificKey('favorite_stores');
      await prefs.setStringList(storeKey, _favoriteStoreIds);
      
      final dishKey = await _getUserSpecificKey('favorite_dishes');
      await prefs.setStringList(dishKey, _favoriteDishIds);
      
      final userId = await _getCurrentUserId();
      developer.log('💾 تم حفظ المفضلة محلياً للمستخدم $userId: ${_favoriteStoreIds.length} مطعم، ${_favoriteDishIds.length} طبق', 
                   name: 'FAVORITES_SIMPLIFIED');
    } catch (e) {
      developer.log('❌ خطأ في حفظ المفضلة محلياً: $e', name: 'FAVORITES_SIMPLIFIED');
    }
  }

  // Store favorites methods
  bool isStoreFavorite(String storeId) {
    return _favoriteStoreIds.contains(storeId);
  }

  /// تبديل حالة المفضلة للمطعم
  Future<void> toggleStoreFavorite(
    String storeId, 
    String storeName, {
    String? storeImage,
    String? storeCategory,
  }) async {
    try {
      developer.log('🔄 تبديل مفضلة المطعم: $storeName', name: 'FAVORITES_SIMPLIFIED');
      
      final wasAlreadyFavorite = _favoriteStoreIds.contains(storeId);
      
      if (wasAlreadyFavorite) {
        // إزالة من المفضلة
        await _removeStoreFavorite(storeId);
      } else {
        // إضافة للمفضلة - ولكن أولاً تحقق من عدم وجودها في الخادم
        await _addStoreFavorite(storeId, storeName, storeImage, storeCategory);
      }
      
    } catch (e) {
      developer.log('❌ خطأ في تبديل مفضلة المطعم: $e', name: 'FAVORITES_SIMPLIFIED');
      throw Exception('فشل في تحديث المفضلة: $e');
    }
  }

  /// إضافة مطعم للمفضلة
  Future<void> _addStoreFavorite(String storeId, String storeName, String? storeImage, String? storeCategory) async {
    try {
      developer.log('➕ إضافة مطعم للمفضلة: $storeName', name: 'FAVORITES_SIMPLIFIED');
      
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
          await _saveFavoritesToLocal();
        }
        developer.log('✅ المطعم موجود بالفعل في الخادم، تم تحديث المحلي فقط', name: 'FAVORITES_SIMPLIFIED');
        return;
      }
      
      // 2. إضافة محلياً للاستجابة السريعة
      if (!_favoriteStoreIds.contains(storeId)) {
        _favoriteStoreIds.add(storeId);
        notifyListeners();
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
        
        // حفظ التحديث محلياً
        await _saveFavoritesToLocal();
        
        developer.log('✅ تم إضافة المطعم للمفضلة بنجاح في الخادم والمحلي', name: 'FAVORITES_SIMPLIFIED');
      } else {
        // إذا فشلت العملية على الخادم، إزالة من المحلي
        _favoriteStoreIds.remove(storeId);
        notifyListeners();
        await _saveFavoritesToLocal();
        throw Exception(result['error'] ?? 'فشل في إضافة المطعم للمفضلة');
      }
      
    } catch (e) {
      developer.log('❌ خطأ في إضافة المطعم للمفضلة: $e', name: 'FAVORITES_SIMPLIFIED');
      rethrow;
    }
  }

  /// إزالة مطعم من المفضلة
  Future<void> _removeStoreFavorite(String storeId) async {
    try {
      developer.log('➖ إزالة مطعم من المفضلة: $storeId', name: 'FAVORITES_SIMPLIFIED');
      
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
        developer.log('⚠️ لم يتم العثور على favoriteId للمطعم $storeId، إزالة محلياً فقط', name: 'FAVORITES_SIMPLIFIED');
        // إزالة محلياً فقط
        _favoriteStoreIds.remove(storeId);
        _favoriteStoreLookup.remove(storeId);
        notifyListeners();
        await _saveFavoritesToLocal();
        return;
      }
      
      // إزالة محلياً أولاً للاستجابة السريعة
      _favoriteStoreIds.remove(storeId);
      _favoriteStoreLookup.remove(storeId);
      notifyListeners();
      
      // إزالة من الخادم
      final result = await FavoritesService.removeFromFavorites(favoriteId: favoriteId);
      
      if (result['success'] == true) {
        // حفظ التحديث محلياً
        await _saveFavoritesToLocal();
        developer.log('✅ تم إزالة المطعم من المفضلة بنجاح من الخادم والمحلي', name: 'FAVORITES_SIMPLIFIED');
      } else {
        // إذا فشلت العملية على الخادم، إعادة إضافة للمحلي
        _favoriteStoreIds.add(storeId);
        _favoriteStoreLookup[storeId] = favoriteId;
        notifyListeners();
        await _saveFavoritesToLocal();
        throw Exception(result['error'] ?? 'فشل في إزالة المطعم من المفضلة');
      }
      
    } catch (e) {
      developer.log('❌ خطأ في إزالة المطعم من المفضلة: $e', name: 'FAVORITES_SIMPLIFIED');
      rethrow;
    }
  }

  // Dish favorites methods (محلية فقط)
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
      
      await _saveFavoritesToLocal();
      notifyListeners();
    } catch (e) {
      developer.log('❌ خطأ في تبديل مفضلة الطبق: $e', name: 'FAVORITES_SIMPLIFIED');
    }
  }

  /// إعادة تحميل المفضلة من الخادم بعد تسجيل الدخول
  Future<void> reloadAfterLogin() async {
    try {
      developer.log('🔄 إعادة تحميل المفضلة بعد تسجيل الدخول', name: 'FAVORITES_SIMPLIFIED');
      
      _isLoading = true;
      notifyListeners();
      
      // مسح cache المستخدم للحصول على المستخدم الجديد
      _clearUserCache();
      
      // تحميل البيانات من الخادم
      await _loadFavoritesFromServer();
      
      _isLoading = false;
      notifyListeners();
      
      final userId = await _getCurrentUserId();
      developer.log('✅ تم إعادة تحميل المفضلة بعد تسجيل الدخول للمستخدم: $userId (${_favoriteStoreIds.length} مطعم)', name: 'FAVORITES_SIMPLIFIED');
    } catch (e) {
      developer.log('❌ خطأ في إعادة تحميل المفضلة بعد تسجيل الدخول: $e', name: 'FAVORITES_SIMPLIFIED');
      // في حال فشل تحميل من الخادم، حاول تحميل محلياً
      await _loadFavoritesFromLocal();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// إعادة تعيين المفضلة للمستخدم الجديد
  Future<void> resetForNewUser() async {
    try {
      developer.log('🔄 بدء إعادة تعيين المفضلة للمستخدم الجديد', name: 'FAVORITES_SIMPLIFIED');
      
      // مسح الـ cache للمستخدم القديم
      _clearUserCache();
      
      // مسح البيانات المحملة حالياً
      _favoriteStoreIds.clear();
      _favoriteDishIds.clear();
      _favoriteStoreLookup.clear();
      
      // إعادة تعيين حالة التهيئة
      _isInitialized = false;
      
      // إشعار الواجهة بالتحديث
      notifyListeners();
      
      // إعادة تهيئة للمستخدم الجديد
      await initialize();
      
      final userId = await _getCurrentUserId();
      developer.log('✅ تم إعادة تعيين المفضلة للمستخدم الجديد: $userId (${_favoriteStoreIds.length} مطعم)', name: 'FAVORITES_SIMPLIFIED');
    } catch (e) {
      developer.log('❌ خطأ في إعادة تعيين المفضلة: $e', name: 'FAVORITES_SIMPLIFIED');
    }
  }

  /// مسح جميع المفضلة (عند تسجيل الخروج)
  Future<void> clearAllFavorites() async {
    try {
      final userId = await _getCurrentUserId();
      
      _favoriteStoreIds.clear();
      _favoriteDishIds.clear();
      _favoriteStoreLookup.clear();
      
      final prefs = await SharedPreferences.getInstance();
      final storeKey = await _getUserSpecificKey('favorite_stores');
      final dishKey = await _getUserSpecificKey('favorite_dishes');
      
      await prefs.remove(storeKey);
      await prefs.remove(dishKey);
      
      notifyListeners();
      developer.log('🧹 تم مسح جميع المفضلة للمستخدم: $userId', name: 'FAVORITES_SIMPLIFIED');
    } catch (e) {
      developer.log('❌ خطأ في مسح المفضلة: $e', name: 'FAVORITES_SIMPLIFIED');
    }
  }
}
