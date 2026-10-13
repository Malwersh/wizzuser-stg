import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../services/phone_link_service.dart';
import '../services/session_service.dart';

class VerifiedPhoneScreen extends StatefulWidget {
  const VerifiedPhoneScreen({super.key, this.initialPhone = ''});
  final String initialPhone;
  @override
  State<VerifiedPhoneScreen> createState() => _VerifiedPhoneScreenState();
}

class _VerifiedPhoneScreenState extends State<VerifiedPhoneScreen> {
  final _phone = TextEditingController(), _code = TextEditingController();
  final _api = PhoneLinkService();
  Timer? _timer;
  String? _session, _error;
  String _verifiedPhone = '';
  bool _busy = false;
  int _resend = 0;
  @override
  void initState() {
    super.initState();
    _phone.text = widget.initialPhone;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.call('status');
      if (!mounted) return;
      setState(() {
        _verifiedPhone = r['verified'] == true ? r['phone'].toString() : '';
        if (_phone.text.isEmpty) _phone.text = r['phone']?.toString() ?? '';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.call('send', {'phone': _phone.text.trim()});
      if (!mounted) return;
      setState(() {
        _session = r['sessionId'].toString();
        _resend = (r['resendAfter'] as num).toInt();
        _code.clear();
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _resend <= 1) {
          t.cancel();
          if (mounted) setState(() => _resend = 0);
        } else {
          setState(() => _resend--);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final digits = _code.text.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
        final n = m[0]!.codeUnitAt(0);
        return '${n >= 0x6f0 ? n - 0x6f0 : n - 0x660}';
      });
      final r = await _api.call('verify', {
        'sessionId': _session,
        'code': digits,
      });
      await SessionService.instance.updateUserData({
        'phone': r['phone'],
        'phoneNumber': r['phone'],
        'phoneVerified': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم توثيق الهاتف، يمكنك استقبال التحويلات بهذا الرقم'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.lightGrey,
        appBar: AppBar(
          title: const Text('توثيق رقم الهاتف'),
          backgroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'اربط رقمك بحسابك الحالي لتسهيل العثور على محفظتك واستقبال التحويلات.',
              style: TextStyle(color: AppColors.secondary, fontSize: 17),
            ),
            if (_verifiedPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('رقمك الموثّق: $_verifiedPhone'),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: _phone,
              enabled: !_busy && _session == null,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف العراقي',
                hintText: '078xxxxxxxx',
                border: OutlineInputBorder(),
              ),
            ),
            if (_session != null) ...[
              const SizedBox(height: 20),
              const Text('أرسلنا رمزًا من 6 أرقام. صلاحيته 5 دقائق.'),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'رمز التحقق',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.secondary),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
              ),
              onPressed:
                  _busy
                      ? null
                      : _session == null
                      ? _send
                      : _verify,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    _busy
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Text(
                          _session == null ? 'إرسال رمز التحقق' : 'تأكيد الرقم',
                        ),
              ),
            ),
            if (_session != null) ...[
              TextButton(
                onPressed: _busy || _resend > 0 ? null : _send,
                child: Text(
                  _resend > 0
                      ? 'إعادة الإرسال بعد $_resend ثانية'
                      : 'إعادة إرسال الرمز',
                ),
              ),
              TextButton(
                onPressed:
                    _busy
                        ? null
                        : () => setState(() {
                          _session = null;
                          _code.clear();
                          _error = null;
                        }),
                child: const Text('تغيير الرقم'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
