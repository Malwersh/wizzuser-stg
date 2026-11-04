import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/app_state_provider.dart';
import '../services/customer_phone_auth_service.dart';
import '../services/delivery_address_manager.dart';
import '../services/guest_cache_service.dart';
import 'email_login_screen.dart';
import 'home_screen.dart';
import 'address_gate_screen.dart';
import 'customer_legal_screen.dart';
import '../models/customer_legal_bundle.dart';
import '../services/customer_legal_service.dart';
import 'delete_account_screen.dart';
import '../services/account_deletion_service.dart';

class CustomerPhoneAuthScreen extends StatefulWidget {
  final bool registration;
  final bool returnToCaller;
  final CustomerPhoneAuthService? service;
  final CustomerLegalService? legalService;
  const CustomerPhoneAuthScreen({
    super.key,
    this.registration = false,
    this.returnToCaller = false,
    this.service,
    this.legalService,
  });
  @override
  State<CustomerPhoneAuthScreen> createState() =>
      _CustomerPhoneAuthScreenState();
}

class _CustomerPhoneAuthScreenState extends State<CustomerPhoneAuthScreen> {
  late final CustomerPhoneAuthService api;
  final phone = TextEditingController(),
      code = TextEditingController(),
      name = TextEditingController();
  bool busy = false, sent = false, needsName = false, accepted = false;
  int remaining = 0;
  String? error;
  Timer? timer;
  CustomerLegalBundle? _legalBundle;
  bool _legalBusy = false;
  String? _legalError;
  late final Future<bool> _savedDeletionReceipt;
  @override
  void initState() {
    super.initState();
    api = widget.service ?? CustomerPhoneAuthService();
    needsName = widget.registration;
    if (needsName) unawaited(_loadLegal());
    _savedDeletionReceipt = AccountDeletionService.hasSavedReceipt();
  }

  Future<void> _loadLegal() async {
    if (_legalBusy) return;
    setState(() {
      _legalBusy = true;
      _legalError = null;
      accepted = false;
      _legalBundle = null;
      api.enrollmentPolicy = null;
    });
    try {
      final bundle = await (widget.legalService ??
              CustomerLegalService.instance)
          .load(refresh: true);
      if (mounted) setState(() => _legalBundle = bundle);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _legalError =
                  'تعذر تحميل السياسات المنشورة. أعد المحاولة قبل إكمال التسجيل.',
        );
    } finally {
      if (mounted) setState(() => _legalBusy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    name.dispose();
    super.dispose();
  }

  void _countdown() {
    timer?.cancel();
    remaining = 60;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => remaining--);
      if (remaining <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.send(phone.text);
      if (mounted) {
        setState(() {
          sent = true;
          _countdown();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error =
                  e is CustomerPhoneAuthException
                      ? e.message
                      : 'تعذر إرسال الرمز. حاول مجددًا',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _finish({bool guest = false}) async {
    if (!mounted) return;
    if (widget.returnToCaller && !guest) {
      Navigator.pop(context, true);
      return;
    }
    final addresses = DeliveryAddressManager.instance;
    var hasAddress = await addresses.hasActiveAddress();
    if (guest) {
      hasAddress = await GuestCacheService.hasGuestAddress();
      if (hasAddress) {
        final a = await GuestCacheService.getGuestAddress();
        if (a != null) await addresses.setActiveAddress(a);
      }
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                hasAddress
                    ? const HomeScreen()
                    : AddressGateScreen(isGuest: guest),
      ),
      (_) => false,
    );
  }

  Future<void> _verify() async {
    if (needsName && (name.text.trim().length < 2 || !accepted)) {
      setState(() => error = 'أدخل اسمك ووافق على الشروط وسياسة الخصوصية');
      return;
    }
    if (needsName && _legalBundle == null) {
      setState(() => error = 'حمّل السياسات المنشورة وراجعها قبل الموافقة.');
      return;
    }
    api.enrollmentPolicy = needsName ? _legalBundle : null;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final done = await api.verify(
        code.text,
        name: name.text.trim(),
        accepted: accepted,
      );
      if (!mounted) return;
      if (!done) {
        setState(() => needsName = true);
        unawaited(_loadLegal());
        return;
      }
      await _finish();
    } catch (e) {
      if (mounted &&
          e is CustomerPhoneAuthException &&
          [
            'LEGAL_VERSION_CHANGED',
            'LEGAL_ACCEPTANCE_REQUIRED',
          ].contains(e.code)) {
        setState(() => needsName = true);
        unawaited(_loadLegal());
      }

      if (mounted) {
        setState(
          () =>
              error =
                  e is CustomerPhoneAuthException
                      ? e.message
                      : 'تعذر الدخول. حاول مجددًا',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.secondary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            const Icon(
              Icons.phone_iphone_rounded,
              size: 52,
              color: AppColors.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              sent
                  ? 'تأكيد رقم الهاتف'
                  : widget.registration
                  ? 'إنشاء حساب'
                  : 'أهلًا بك',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              sent
                  ? 'أدخل الرمز الذي وصلك. صلاحيته 5 دقائق.'
                  : 'أدخل رقم هاتفك لنرسل لك رمز الدخول',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.6),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: phone,
              enabled: !busy && !sent,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(
                labelText: 'رقم الهاتف العراقي',
                hintText: '07831367435',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (sent) ...[
              const SizedBox(height: 18),
              TextField(
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                  labelText: 'رمز التحقق',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
            if (needsName) ...[
              const SizedBox(height: 18),
              TextField(
                controller: name,
                enabled: !busy,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: 'الاسم الكامل',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (_legalBusy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(
                    color: AppColors.secondaryDark,
                  ),
                ),
              if (_legalError != null)
                Column(
                  children: [
                    Text(
                      _legalError!,
                      style: const TextStyle(color: AppColors.secondaryDark),
                    ),
                    TextButton(
                      onPressed: _loadLegal,
                      child: const Text(
                        'إعادة تحميل السياسات',
                        style: TextStyle(color: AppColors.secondaryDark),
                      ),
                    ),
                  ],
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: accepted,
                activeColor: AppColors.secondaryDark,
                onChanged:
                    busy || _legalBundle == null
                        ? null
                        : (v) => setState(() => accepted = v ?? false),
                title: const Text(
                  'أوافق على سياسة الاستخدام والشروط والأحكام، وأقر باطلاعي على سياسة الخصوصية وسياسة الإلغاء والإرجاع.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.secondaryDark,
                  ),
                ),
              ),
              if (_legalBundle != null)
                Wrap(
                  children: [
                    for (final doc in _legalBundle!.documents)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.secondaryDark,
                        ),
                        onPressed:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => CustomerLegalScreen(
                                      documentId: doc['id'],
                                      bundle: _legalBundle,
                                    ),
                              ),
                            ),
                        child: Text(
                          doc['title'],
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    height: 1.6,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed:
                  busy
                      ? null
                      : sent
                      ? _verify
                      : _send,
              child:
                  busy
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Text(sent ? 'تأكيد ومتابعة' : 'إرسال رمز التحقق'),
            ),
            if (sent) ...[
              TextButton(
                onPressed: busy || remaining > 0 ? null : _send,
                child: Text(
                  remaining > 0
                      ? 'إعادة الإرسال بعد $remaining ثانية'
                      : 'إعادة إرسال الرمز',
                ),
              ),
              TextButton(
                onPressed:
                    busy
                        ? null
                        : () {
                          timer?.cancel();
                          setState(() {
                            sent = false;
                            code.clear();
                            remaining = 0;
                            error = null;
                          });
                        },
                child: const Text('تغيير الرقم'),
              ),
            ],
            const SizedBox(height: 20),
            FutureBuilder<bool>(
              future: _savedDeletionReceipt,
              builder:
                  (context, snapshot) =>
                      snapshot.data == true
                          ? TextButton(
                            onPressed:
                                busy
                                    ? null
                                    : () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder:
                                            (_) => const DeleteAccountScreen(),
                                      ),
                                    ),
                            child: const Text('متابعة طلب حذف الحساب'),
                          )
                          : const SizedBox.shrink(),
            ),
            TextButton(
              onPressed:
                  busy
                      ? null
                      : () async {
                        final done = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => EmailLoginScreen(
                                  returnToCaller: widget.returnToCaller,
                                ),
                          ),
                        );
                        if (done == true && mounted && widget.returnToCaller)
                          await _finish();
                      },
              child: const Text('لدي حساب قديم بالبريد — ربط رقم الهاتف'),
            ),
            if (!widget.returnToCaller)
              TextButton(
                onPressed:
                    busy
                        ? null
                        : () async {
                          setState(() => busy = true);
                          try {
                            final ok =
                                await context
                                    .read<AppStateProvider>()
                                    .loginAsGuest();
                            if (ok) await _finish(guest: true);
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                child: const Text('تصفح كضيف'),
              ),
          ],
        ),
      ),
    ),
  );
}
