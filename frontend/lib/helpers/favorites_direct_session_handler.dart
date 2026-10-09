
import 'dart:developer' as developer;
import '../models/favorites_model.dart';
import '../services/session_service.dart';

/// معالج مباشر لتكامل المفضلة مع إدارة الجلسات
/// يتم استدعاؤه مباشرة عند تسجيل الدخول/الخروج
class FavoritesDirectSessionHandler {
  static const String _tag = 'FAVORITES_DIRECT_HANDLER';
  
  /// معالجة تسجيل دخول مستخدم جديد
  static Future<void> handleUserLogin(FavoritesModel favoritesModel) async {
    try {
      final currentUserId = SessionService.instance.currentUserId;
      developer.log('👤 معالجة تسجيل دخول مستخدم جديد: $currentUserId', name: _tag);
      
      if (currentUserId != null) {
        // إعادة تحميل المفضلة للمستخدم الجديد
        await favoritesModel.reloadAfterLogin();
        developer.log('✅ تم إعادة تحميل المفضلة للمستخدم الجديد بنجاح', name: _tag);
      } else {
        developer.log('⚠️ لا يوجد معرف مستخدم حالي', name: _tag);
      }
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في معالجة تسجيل دخول المستخدم: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
    }
  }

  /// معالجة تسجيل خروج المستخدم
  static Future<void> handleUserLogout(FavoritesModel favoritesModel) async {
    try {
      developer.log('🚪 معالجة تسجيل خروج المستخدم', name: _tag);
      
      // مسح جميع بيانات المفضلة المحلية
      await favoritesModel.clearAllFavorites();
      developer.log('✅ تم مسح جميع بيانات المفضلة بعد تسجيل الخروج', name: _tag);
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في معالجة تسجيل خروج المستخدم: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
    }
  }

  /// معالجة تحول إلى وضع الضيف
  static Future<void> handleGuestMode(FavoritesModel favoritesModel) async {
    try {
      developer.log('🚶 معالجة تحول إلى وضع الضيف', name: _tag);
      
      // مسح جميع بيانات المفضلة وإعادة التهيئة للضيف
      await favoritesModel.clearAllFavorites();
      developer.log('✅ تم تنظيف المفضلة لوضع الضيف', name: _tag);
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في معالجة وضع الضيف: $e', name: _tag);
      developer.log('Stack trace: $stackTrace', name: _tag);
    }
  }
}
