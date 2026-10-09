library favorites_session_integration;

import 'dart:developer' as developer;
import '../models/favorites_model.dart';
import '../services/session_service.dart';
import '../models/session_state.dart';

/// مساعد لتهيئة أنظمة المفضلة مع أنظمة إدارة الجلسات
class FavoritesSessionIntegration {
  static const String _tag = 'FAVORITES_SESSION_INTEGRATION';
  
  // مرجع ثابت للنموذج الأصلي لاستخدامه في callbacks
  static FavoritesModel? _favoritesModelInstance;
  
  /// تهيئة التكامل بين نظام المفضلة وإدارة الجلسات (النموذج المحسن)
  static void initialize(FavoritesModel favoritesModel) {
    // حفظ المرجع للاستخدام في callbacks
    _favoritesModelInstance = favoritesModel;
    
    developer.log('🔗 تهيئة تكامل المفضلة مع إدارة الجلسات', name: _tag);
    
    // استمع لتغيرات حالة الجلسة بشكل أكثر دقة
    SessionService.instance.sessionStateStream.listen(
      (sessionState) async {
        developer.log('🔔 تلقي تحديث حالة الجلسة: ${sessionState.runtimeType}', name: _tag);
        await _handleSessionStateChange(sessionState, favoritesModel);
      },
      onError: (error) {
        developer.log('❌ خطأ في stream حالة الجلسة: $error', name: _tag);
      },
      onDone: () {
        developer.log('✅ انتهاء stream حالة الجلسة', name: _tag);
      }
    );
    
    // إضافة تسجيل للحالة الحالية
    final currentState = SessionService.instance.currentSessionState;
    developer.log('📊 الحالة الحالية للجلسة: ${currentState.runtimeType}', name: _tag);
  }

  /// التعامل مع تغيير حالة الجلسة
  static Future<void> _handleSessionStateChange(
    SessionState sessionState, 
    FavoritesModel favoritesModel
  ) async {
    developer.log('📱 معالجة تغيير حالة الجلسة: ${sessionState.runtimeType}', name: _tag);
    
    try {
      if (sessionState is SessionActive) {
        // مستخدم جديد سجل دخوله - إعادة تحميل المفضلة
        developer.log('👤 مستخدم جديد سجل الدخول - إعادة تحميل المفضلة', name: _tag);
        await _handleUserLogin(favoritesModel);
      } else if (sessionState is GuestSession) {
        // تحول إلى ضيف - مسح المفضلة
        developer.log('🚶 تحول إلى وضع الضيف - مسح المفضلة المحلية', name: _tag);
        await _handleGuestSession(favoritesModel);
      } else if (sessionState is SessionExpired) {
        // انتهاء جلسة - تنظيف المفضلة
        developer.log('🚪 انتهاء الجلسة - تنظيف المفضلة', name: _tag);
        await _handleLogout(favoritesModel);
      } else if (sessionState is SessionInitial) {
        // جلسة أولية - قد تحتاج تنظيف المفضلة
        developer.log('🔄 جلسة أولية - إعادة تهيئة المفضلة', name: _tag);
        await _handleLogout(favoritesModel);
      } else {
        developer.log('❓ حالة جلسة غير معروفة: ${sessionState.runtimeType}', name: _tag);
      }
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في معالجة تغيير حالة الجلسة: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
    }
  }

  /// معالجة تسجيل دخول مستخدم جديد
  static Future<void> _handleUserLogin(FavoritesModel favoritesModel) async {
    try {
      developer.log('🔄 بدء إعادة تحميل المفضلة للمستخدم الجديد...', name: _tag);
      await favoritesModel.reloadAfterLogin();
      developer.log('✅ تم إعادة تحميل المفضلة للمستخدم الجديد بنجاح', name: _tag);
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في إعادة تحميل المفضلة: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
    }
  }

  /// معالجة الضيف
  static Future<void> _handleGuestSession(FavoritesModel favoritesModel) async {
    try {
      developer.log('🔄 بدء إعادة تهيئة المفضلة للضيف...', name: _tag);
      
      // Clear everything first
      await favoritesModel.clearAllFavorites();
      
      // Reset for guest user
      await favoritesModel.resetForNewUser();
      
      // Verify that favorites are actually empty
      if (favoritesModel.favoriteStoreIds.isEmpty) {
        developer.log('✅ تأكيد: تم مسح المفضلة للضيف بنجاح', name: _tag);
      } else {
        developer.log('⚠️ تحذير: لا تزال هناك مفضلة بعد المسح!', name: _tag);
      }
      
      developer.log('✅ تم مسح المفضلة وإعادة تهيئتها للضيف', name: _tag);
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في تهيئة مفضلة الضيف: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
    }
  }

  /// معالجة تسجيل الخروج
  static Future<void> _handleLogout(FavoritesModel favoritesModel) async {
    try {
      developer.log('🔄 بدء تنظيف المفضلة بعد تسجيل الخروج...', name: _tag);
      // 🔧 إصلاح: مسح المفضلة قبل إعادة التهيئة للضيف
      await favoritesModel.clearAllFavorites();
      await favoritesModel.resetForNewUser();
      developer.log('✅ تم مسح المفضلة وإعادة تهيئتها بعد تسجيل الخروج', name: _tag);
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في تنظيف المفضلة: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
    }
  }

  /// دالة يدوية لإعادة تحميل المفضلة بعد تسجيل الدخول (للاستخدام في واجهات المستخدم)
  static Future<void> handleSuccessfulLogin() async {
    if (_favoritesModelInstance != null) {
      await _handleUserLogin(_favoritesModelInstance!);
    } else {
      developer.log('⚠️ FavoritesModel instance not found', name: _tag);
    }
  }

  /// دالة يدوية لمعالجة تسجيل الخروج (للاستخدام في واجهات المستخدم)
  static Future<void> handleLogout() async {
    if (_favoritesModelInstance != null) {
      developer.log('🧹 تنظيف يدوي للمفضلة عند تسجيل الخروج', name: _tag);
      await _handleLogout(_favoritesModelInstance!);
    } else {
      developer.log('⚠️ FavoritesModel instance not found', name: _tag);
    }
  }
}
