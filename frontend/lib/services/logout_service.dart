import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'session_service.dart';

/// خدمة تسجيل الخروج الآمن - واجهة بسيطة لتسجيل الخروج
class LogoutService {
  static const String _tag = 'LOGOUT_SERVICE';

  /// تسجيل خروج آمن مع مربع حوار تأكيد
  static Future<bool> performSecureLogout(BuildContext context, {
    bool showConfirmation = true,
    bool showLoading = true,
  }) async {
    developer.log('🚪 بدء عملية تسجيل الخروج الآمن', name: _tag);
    
    try {
      // Show confirmation dialog if requested
      if (showConfirmation) {
        final confirmed = await _showConfirmationDialog(context);
        if (!confirmed) {
          developer.log('❌ المستخدم ألغى عملية تسجيل الخروج', name: _tag);
          return false;
        }
      }

      // Show loading dialog if requested
      if (showLoading && context.mounted) {
        _showLoadingDialog(context);
      }

      // Perform secure logout
      await SessionService.instance.logout();
      
      // Close loading dialog
      if (showLoading && context.mounted) {
        Navigator.of(context).pop();
      }
      
      // Show success message
      if (context.mounted) {
        _showSuccessMessage(context);
      }
      
      developer.log('✅ تم تسجيل الخروج بنجاح', name: _tag);
      return true;
      
    } catch (e) {
      developer.log('❌ خطأ في تسجيل الخروج: $e', name: _tag);
      
      // Close loading dialog if open
      if (showLoading && context.mounted) {
        Navigator.of(context).pop();
      }
      
      // Show error message
      if (context.mounted) {
        _showErrorMessage(context);
      }
      
      return false;
    }
  }

  /// تسجيل خروج صامت (بدون واجهة مستخدم)
  static Future<bool> performSilentLogout() async {
    try {
      developer.log('🔇 تسجيل خروج صامت', name: _tag);
      await SessionService.instance.logout();
      developer.log('✅ تم تسجيل الخروج الصامت بنجاح', name: _tag);
      return true;
    } catch (e) {
      developer.log('❌ خطأ في تسجيل الخروج الصامت: $e', name: _tag);
      return false;
    }
  }

  /// مربع حوار التأكيد
  static Future<bool> _showConfirmationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.logout, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 12),
              const Text(
                'تسجيل الخروج',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'هل أنت متأكد من رغبتك في تسجيل الخروج؟\n\nستتم المحافظة على سلة التسوق الخاصة بك وسيتم تحويلك إلى وضع الضيف.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'إلغاء',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: AppColors.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        );
      },
    );
    
    return result ?? false;
  }

  /// مربع حوار التحميل
  static void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جارٍ تسجيل الخروج بشكل آمن...'),
          ],
        ),
      ),
    );
  }

  /// رسالة النجاح
  static void _showSuccessMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم تسجيل الخروج بنجاح - أنت الآن في وضع الضيف'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// رسالة الخطأ
  static void _showErrorMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ حدث خطأ أثناء تسجيل الخروج، تم التحويل إلى وضع الضيف'),
        backgroundColor: AppColors.secondary,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
