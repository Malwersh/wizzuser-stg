import '../utils/readable_colors.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/session_service.dart';
import '../services/user_profile_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _isLoading = false;

  // إعدادات الإشعارات
  bool _orderNotifications = true;
  bool _promotionNotifications = true;
  bool _newsletterNotifications = false;
  bool _reminderNotifications = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final sessionData = SessionService.instance.currentUser;
      final userId = sessionData?['userId'] ?? sessionData?['user_id'] ?? '';

      if (userId.isNotEmpty) {
        // جلب إعدادات الإشعارات من الخادم
        final profile = await UserProfileService.getUserProfile(userId);

        if (profile != null &&
            profile['notification_settings'] != null &&
            mounted) {
          final notificationSettings = profile['notification_settings'];
          setState(() {
            _orderNotifications =
                notificationSettings['order_notifications'] ?? true;
            _promotionNotifications =
                notificationSettings['promotion_notifications'] ?? true;
            _newsletterNotifications =
                notificationSettings['newsletter_notifications'] ?? false;
            _reminderNotifications =
                notificationSettings['reminder_notifications'] ?? true;
            _soundEnabled = notificationSettings['sound_enabled'] ?? true;
            _vibrationEnabled =
                notificationSettings['vibration_enabled'] ?? true;
          });
        } else {
          // استخدام إعدادات افتراضية
          if (mounted) {
            setState(() {
              _orderNotifications = true;
              _promotionNotifications = true;
              _newsletterNotifications = false;
              _reminderNotifications = true;
              _soundEnabled = true;
              _vibrationEnabled = true;
            });
          }
        }
      } else {
        // استخدام إعدادات افتراضية للجلسة المحلية
        if (mounted) {
          setState(() {
            _orderNotifications = true;
            _promotionNotifications = true;
            _newsletterNotifications = false;
            _reminderNotifications = true;
            _soundEnabled = true;
            _vibrationEnabled = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل الإعدادات: $e'),
            backgroundColor: AppColors.primaryDark,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveNotificationSettings() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final sessionData = SessionService.instance.currentUser;
      final userId = sessionData?['userId'] ?? sessionData?['user_id'] ?? '';

      if (userId.isEmpty) {
        throw Exception('معرف المستخدم غير موجود');
      }

      // إعدادات الإشعارات - مُعطل مؤقتاً
      // final notificationSettings = {
      //   'order_notifications': _orderNotifications,
      //   'promotion_notifications': _promotionNotifications,
      //   'newsletter_notifications': _newsletterNotifications,
      //   'reminder_notifications': _reminderNotifications,
      //   'sound_enabled': _soundEnabled,
      //   'vibration_enabled': _vibrationEnabled,
      // };

      // محاكاة نجاح الحفظ
      final result = {
        'success': true,
        'message': 'تم حفظ إعدادات الإشعارات بنجاح (وضع تجريبي)',
      };

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message']?.toString() ?? 'تم حفظ الإعدادات بنجاح',
              ),
              backgroundColor: AppColors.primary,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message']?.toString() ?? 'فشل في حفظ الإعدادات',
              ),
              backgroundColor: AppColors.primaryDark,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ الإعدادات: $e'),
            backgroundColor: AppColors.primaryDark,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('إعدادات الإشعارات'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: _isLoading ? null : _saveNotificationSettings,
              child: const Text(
                'حفظ',
                style: TextStyle(
                  color: const Color(0xFF00296B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // إعدادات الإشعارات الأساسية
                      _buildSectionCard(
                        title: 'إشعارات التطبيق',
                        icon: Icons.notifications_outlined,
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('إشعارات الطلبات'),
                              subtitle: const Text(
                                'تلقي إشعارات حالة الطلبات والتوصيل',
                              ),
                              value: _orderNotifications,
                              activeColor: AppColors.secondary,
                              onChanged:
                                  (value) => setState(
                                    () => _orderNotifications = value,
                                  ),
                            ),
                            const Divider(),
                            SwitchListTile(
                              title: const Text('إشعارات العروض والخصومات'),
                              subtitle: const Text(
                                'تلقي إشعارات العروض الخاصة والتخفيضات',
                              ),
                              value: _promotionNotifications,
                              activeColor: AppColors.secondary,
                              onChanged:
                                  (value) => setState(
                                    () => _promotionNotifications = value,
                                  ),
                            ),
                            const Divider(),
                            SwitchListTile(
                              title: const Text('إشعارات النشرة الإلكترونية'),
                              subtitle: const Text(
                                'تلقي النشرة الإلكترونية والأخبار',
                              ),
                              value: _newsletterNotifications,
                              activeColor: AppColors.secondary,
                              onChanged:
                                  (value) => setState(
                                    () => _newsletterNotifications = value,
                                  ),
                            ),
                            const Divider(),
                            SwitchListTile(
                              title: const Text('إشعارات التذكير'),
                              subtitle: const Text(
                                'تذكيرات السلة المتروكة والعروض المنتهية',
                              ),
                              value: _reminderNotifications,
                              activeColor: AppColors.secondary,
                              onChanged:
                                  (value) => setState(
                                    () => _reminderNotifications = value,
                                  ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // إعدادات الصوت والاهتزاز
                      _buildSectionCard(
                        title: 'إعدادات الصوت والاهتزاز',
                        icon: Icons.volume_up_outlined,
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('تشغيل الصوت'),
                              subtitle: const Text(
                                'تشغيل صوت عند وصول الإشعارات',
                              ),
                              value: _soundEnabled,
                              activeColor: AppColors.secondary,
                              onChanged:
                                  (value) =>
                                      setState(() => _soundEnabled = value),
                            ),
                            const Divider(),
                            SwitchListTile(
                              title: const Text('تشغيل الاهتزاز'),
                              subtitle: const Text(
                                'اهتزاز الجهاز عند وصول الإشعارات',
                              ),
                              value: _vibrationEnabled,
                              activeColor: AppColors.secondary,
                              onChanged:
                                  (value) =>
                                      setState(() => _vibrationEnabled = value),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // زر الحفظ
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _isLoading ? null : _saveNotificationSettings,
                          style: ElevatedButton.styleFrom(
                            foregroundColor: readableForeground(
                              AppColors.primary,
                            ),
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child:
                              _isLoading
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: const Color(0xFF00296B),
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Text(
                                    'حفظ الإعدادات',
                                    style: TextStyle(
                                      color: const Color(0xFF00296B),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // معلومات إضافية
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue[600],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'يمكنك تغيير هذه الإعدادات في أي وقت من خلال هذه الصفحة',
                                style: TextStyle(
                                  color: Colors.blue[800],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF00296B), size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF00296B),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
