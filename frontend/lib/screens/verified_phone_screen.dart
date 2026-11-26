import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/iraqi_phone.dart';
import '../widgets/iraqi_mobile_field.dart';
import '../constants/app_colors.dart';
import '../services/phone_link_service.dart';
import '../services/session_service.dart';
import 'customer_phone_auth_screen.dart';
import 'email_login_screen.dart';

class VerifiedPhoneScreen extends StatefulWidget {
  const VerifiedPhoneScreen({
    super.key,
    this.initialPhone = '',
    this.service,
    this.currentOwner,
    this.reauthenticate,
    this.savePhone,
  });
  final String initialPhone;
  final PhoneLinkService? service;
  final String? Function()? currentOwner;
  final Future<bool> Function(BuildContext, String)? reauthenticate;
  final Future<void> Function(String)? savePhone;
  @override
  State<VerifiedPhoneScreen> createState() => _VerifiedPhoneScreenState();
}

class _VerifiedPhoneScreenState extends State<VerifiedPhoneScreen> {
  final _phone = TextEditingController(), _code = TextEditingController();
  late final PhoneLinkService _api;
  late final String? _owner;
  Timer? _timer;
  String? _session, _error, _pending;
  String _current = '';
  bool _verified = false,
      _busy = false,
      _loading = true,
      _loaded = false,
      _reauth = false;
  int _resend = 0;
  String? get owner =>
      widget.currentOwner != null
          ? widget.currentOwner!()
          : SessionService.instance.currentUserId;
  bool get sameOwner => _owner != null && _owner == owner;
  @override
  void initState() {
    super.initState();
    _api = widget.service ?? PhoneLinkService();
    _owner = owner;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.call('status');
      if (!mounted || !sameOwner) return;
      setState(() {
        _current = r['phone']?.toString() ?? '';
        _verified = r['verified'] == true;
        _reauth = r['requiresReauthentication'] == true;
        _pending = r['pendingSessionId'] as String?;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object e) =>
      e is PhoneLinkException
          ? e.message
          : 'تعذر الاتصال بالخدمة. أعد المحاولة؛ لم نؤكد تغيير الرقم.';
  Future<void> _authenticate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok =
          widget.reauthenticate != null
              ? await widget.reauthenticate!(context, _current)
              : await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder:
                      (_) =>
                          _verified && IraqiPhone.valid(_current)
                              ? CustomerPhoneAuthScreen(
                                returnToCaller: true,
                                expectedOwner: _owner,
                                initialPhone: _current,
                              )
                              : const EmailLoginScreen(returnToCaller: true),
                ),
              );
      if (!mounted) return;
      if (!sameOwner) {
        setState(() {
          _loaded = false;
          _error = 'تغيّر الحساب؛ أغلق الصفحة وافتحها من الحساب المطلوب';
        });
        return;
      }
      if (ok == true) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _countdown(int seconds) {
    _timer?.cancel();
    _resend = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resend <= 1) {
        t.cancel();
        if (mounted) setState(() => _resend = 0);
      } else {
        setState(() => _resend--);
      }
    });
  }

  Future<void> _send() async {
    if (!sameOwner || !_loaded || _busy) return;
    if (_reauth) {
      await _authenticate();
      return;
    }
    if (!IraqiPhone.valid(_phone.text)) {
      setState(() => _error = 'أدخل رقم هاتف عراقي صحيح');
      return;
    }
    if (_verified && IraqiPhone.normalize(_phone.text) == _current) {
      setState(() => _error = 'هذا رقمك الحالي؛ أدخل الرقم الجديد');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.call('send', {
        'phone': IraqiPhone.normalize(_phone.text),
      });
      if (!mounted || !sameOwner) return;
      if (r['alreadyVerified'] == true) {
        setState(() => _error = 'هذا الرقم موثّق بالفعل');
        return;
      }
      setState(() {
        _session = r['sessionId'] as String;
        _code.clear();
        _countdown((r['resendAfter'] as num?)?.toInt() ?? 60);
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = _message(e);
          if (e is PhoneLinkException && e.code == 'REAUTH_REQUIRED')
            _reauth = true;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (!sameOwner || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.call('verify', {
        'sessionId': _pending ?? _session,
        if (_pending == null) 'code': IraqiPhone.ascii(_code.text.trim()),
      });
      if (!mounted || !sameOwner) return;
      final phone = IraqiPhone.normalize(r['phone']?.toString() ?? '');
      if (r['verified'] != true)
        throw const PhoneLinkException('لم يتم تأكيد تغيير الرقم');
      if (widget.savePhone != null) {
        await widget.savePhone!(phone);
      } else {
        await SessionService.instance.updateUserData({
          'phone': phone,
          'phoneNumber': phone,
          'phone_number': phone,
          'phoneVerified': true,
        });
      }
      if (!mounted || !sameOwner) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث رقم هاتفك بنجاح')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = _message(e);
          if (e is PhoneLinkException && e.code == 'REAUTH_REQUIRED')
            _reauth = true;
        });
      // A lost response may follow a committed identity change. Read status once; no polling.
      try {
        final status = await _api.call('status');
        if (mounted && sameOwner)
          setState(() => _pending = status['pendingSessionId'] as String?);
      } catch (_) {}
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
          title: const Text('تغيير رقم الهاتف'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.secondaryDark,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_loaded && sameOwner) ...[
              Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(
                    Icons.phone_outlined,
                    color: AppColors.secondaryDark,
                  ),
                  title: const Text('رقم هاتفك الحالي'),
                  subtitle: Text(
                    _current.isEmpty
                        ? 'لم يُربط رقم بعد'
                        : IraqiPhone.display(_current),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'يُستخدم الرقم لتسجيل الدخول والتواصل بشأن طلباتك. تغيير الرقم يحافظ على حسابك وطلباتك ورصيدك.',
                style: TextStyle(color: AppColors.secondaryDark, height: 1.6),
              ),
              const SizedBox(height: 20),
              if (_pending != null)
                const Text(
                  'بدأ تحديث رقمك ولم يكتمل تأكيده. أكمل العملية نفسها دون إرسال رمز جديد.',
                  style: TextStyle(color: AppColors.secondaryDark, height: 1.6),
                )
              else if (_reauth)
                const Text(
                  'لأمان حسابك، أكّد هويتك أولًا برمز يصل إلى رقمك الحالي، ثم وثّق الرقم الجديد.',
                  style: TextStyle(color: AppColors.secondaryDark, height: 1.6),
                )
              else ...[
                IraqiMobileField(
                  controller: _phone,
                  enabled: !_busy && _session == null,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف الجديد',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_session != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'أدخل الرمز المرسل إلى رقمك الجديد. صلاحيته ٥ دقائق.',
                  ),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    maxLength: 6,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
                    ],
                  ),
                ],
              ],
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xffa92e2e), height: 1.5),
                ),
              ),
            const SizedBox(height: 20),
            if (!_loading)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondaryDark,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed:
                    _busy || !sameOwner
                        ? null
                        : !_loaded
                        ? _load
                        : _pending != null
                        ? _verify
                        : _reauth
                        ? _authenticate
                        : _session != null
                        ? _verify
                        : _send,
                child:
                    _busy
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Text(
                          !_loaded
                              ? 'إعادة المحاولة'
                              : _pending != null
                              ? 'إكمال تحديث الرقم'
                              : _reauth
                              ? 'تأكيد هويتي للمتابعة'
                              : _session == null
                              ? 'إرسال رمز للرقم الجديد'
                              : 'تأكيد تغيير الرقم',
                        ),
              ),
            if (_session != null && _pending == null && !_reauth) ...[
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
                child: const Text('تعديل الرقم الجديد'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
