import '../utils/readable_colors.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/session_service.dart';
import '../services/notification_service.dart';

class NotificationManagementScreen extends StatefulWidget {
  const NotificationManagementScreen({super.key});

  @override
  State<NotificationManagementScreen> createState() =>
      _NotificationManagementScreenState();
}

class _NotificationManagementScreenState
    extends State<NotificationManagementScreen> {
  bool _isLoading = false;
  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationStatus();
  }

  Future<void> _loadNotificationStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _notificationsEnabled =
          NotificationService.areNotificationsEnabledStatic();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل حالة الإشعارات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendTestNotification() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sessionData = SessionService.instance.currentUser;
      final userId = sessionData?['userId'] ?? '';

      if (userId.isNotEmpty) {
        await NotificationService.sendTestNotificationStatic();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إرسال إشعار تجريبي'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يجب تسجيل الدخول أولاً'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال الإشعار: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleNotifications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_notificationsEnabled) {
        await NotificationService.disableNotificationsStatic();
        _notificationsEnabled = false;
      } else {
        await NotificationService.initialize();
        _notificationsEnabled =
            NotificationService.areNotificationsEnabledStatic();
      }

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _notificationsEnabled
                  ? 'تم تفعيل الإشعارات'
                  : 'تم تعطيل الإشعارات',
            ),
            backgroundColor:
                _notificationsEnabled ? Colors.green : AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تغيير حالة الإشعارات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text(
            'إدارة الإشعارات',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          elevation: 0,
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(),
                      const SizedBox(height: 20),
                      _buildControlsCard(),
                      const SizedBox(height: 20),
                      _buildTestingCard(),
                      const SizedBox(height: 20),
                      _buildInfoCard(),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
          Row(
            children: [
              Icon(
                _notificationsEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off,
                color: _notificationsEnabled ? Colors.green : Colors.red,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'حالة الإشعارات',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _notificationsEnabled ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    _notificationsEnabled
                        ? Colors.green[200]!
                        : Colors.red[200]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _notificationsEnabled ? Icons.check_circle : Icons.error,
                  color:
                      _notificationsEnabled
                          ? Colors.green[700]
                          : Colors.red[700],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _notificationsEnabled ? 'الإشعارات مفعلة' : 'الإشعارات معطلة',
                  style: TextStyle(
                    color:
                        _notificationsEnabled
                            ? Colors.green[700]
                            : Colors.red[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
          const Text(
            'التحكم في الإشعارات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _toggleNotifications,
              icon: Icon(
                _notificationsEnabled
                    ? Icons.notifications_off
                    : Icons.notifications_active,
              ),
              label: Text(
                _notificationsEnabled ? 'تعطيل الإشعارات' : 'تفعيل الإشعارات',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _notificationsEnabled ? Colors.red : Colors.green,
                foregroundColor: readableForeground(
                  _notificationsEnabled ? Colors.red : Colors.green,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
          const Text(
            'اختبار الإشعارات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'اختبر عمل الإشعارات عن طريق إرسال إشعار تجريبي',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_isLoading || !_notificationsEnabled)
                      ? null
                      : _sendTestNotification,
              icon: const Icon(Icons.send),
              label: const Text('إرسال إشعار تجريبي'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700]),
              const SizedBox(width: 12),
              const Text(
                'معلومات هامة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '• الإشعارات تحتاج لموافقة من النظام\n'
            '• يمكن تعديل الإعدادات من إعدادات الجهاز\n'
            '• الإشعارات التجريبية تساعد في التأكد من عمل النظام\n'
            '• يتم حفظ تفضيلات الإشعارات تلقائياً',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
