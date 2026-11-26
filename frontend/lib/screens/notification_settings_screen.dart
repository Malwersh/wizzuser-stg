import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_colors.dart';
import '../services/customer_notification_preferences.dart';
import '../services/session_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _service = CustomerNotificationPreferencesService();
  CustomerNotificationPreferences _value =
      const CustomerNotificationPreferences();
  bool _busy = true, _loaded = false;
  String? _error;
  late final String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = SessionService.instance.currentUserId;
    _load();
  }

  bool get _sameOwner =>
      mounted &&
      _owner != null &&
      SessionService.instance.currentUserId == _owner;
  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _service.load();
      if (!mounted || !_sameOwner) return;
      setState(() {
        _value = value;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              _owner == null
                  ? 'سجّل الدخول لحفظ تفضيلات إشعارات حسابك.'
                  : 'تعذر تحميل إعدادات الإشعارات. أعد المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_sameOwner || !_loaded || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _service.save(_value);
      if (!mounted || !_sameOwner) return;
      await SessionService.instance.updateUserData({
        'notification_settings': saved.toJson(),
      });
      if (!mounted || !_sameOwner) return;
      setState(() => _value = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ إعدادات الإشعارات'),
          backgroundColor: AppColors.secondaryDark,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'تعذر حفظ الإعدادات. لم نؤكد أي تغيير؛ أعد المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('إعدادات الإشعارات'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.secondaryDark,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.secondaryDark),
              ),
            ),
            if (!_loaded && _owner != null)
              TextButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
          ],
          Card(
            elevation: 0,
            color: Colors.white,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('تنبيهات الطلبات'),
                  subtitle: const Text(
                    'تنبيهات حالة الطلب؛ تبقى حالة الطلب والتتبع متاحين داخل التطبيق.',
                  ),
                  value: _value.orders,
                  activeThumbColor: AppColors.secondaryDark,
                  onChanged:
                      _loaded && !_busy && _sameOwner
                          ? (v) => setState(
                            () =>
                                _value = CustomerNotificationPreferences(
                                  orders: v,
                                  promotions: _value.promotions,
                                ),
                          )
                          : null,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: const Text('العروض والخصومات'),
                  subtitle: const Text('إشعارات الحملات والعروض المناسبة لك.'),
                  value: _value.promotions,
                  activeThumbColor: AppColors.secondaryDark,
                  onChanged:
                      _loaded && !_busy && _sameOwner
                          ? (v) => setState(
                            () =>
                                _value = CustomerNotificationPreferences(
                                  orders: _value.orders,
                                  promotions: v,
                                ),
                          )
                          : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.white,
            child: ListTile(
              leading: const Icon(
                Icons.notifications_outlined,
                color: AppColors.secondaryDark,
              ),
              title: const Text('الصوت وإذن الإشعارات'),
              subtitle: const Text(
                'تُضبط من إعدادات جهازك. السماح بالإشعارات في الجهاز ضروري لوصول التنبيهات.',
              ),
              trailing: const Icon(
                Icons.chevron_left,
                textDirection: ui.TextDirection.ltr,
              ),
              onTap: Geolocator.openAppSettings,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loaded && !_busy && _sameOwner ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.secondaryDark,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('حفظ الإعدادات'),
          ),
        ],
      ),
    ),
  );
}
