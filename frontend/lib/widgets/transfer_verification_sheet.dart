import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class TransferVerificationSheet extends StatefulWidget {
  const TransferVerificationSheet({
    super.key,
    required this.request,
    required this.call,
  });
  final Map<String, dynamic> request;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  call;
  @override
  State<TransferVerificationSheet> createState() =>
      _TransferVerificationSheetState();
}

class _TransferVerificationSheetState extends State<TransferVerificationSheet> {
  final _code = TextEditingController();
  Timer? _timer;
  String? _challenge, _error;
  String _phoneHint = '';
  bool _busy = false;
  int _resend = 0;
  @override
  void initState() {
    super.initState();
    _send();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.call('otp/send', widget.request);
      if (!mounted) return;
      setState(() {
        _challenge = r['challengeId'].toString();
        _phoneHint = r['phoneHint'].toString();
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
      if (mounted) setState(() => _error = e.toString());
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
      final code = _code.text.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
        final n = m[0]!.codeUnitAt(0);
        return '${n >= 0x6f0 ? n - 0x6f0 : n - 0x660}';
      });
      final r = await widget.call('otp/verify', {
        ...widget.request,
        'challengeId': _challenge,
        'code': code,
      });
      if (mounted) Navigator.pop(context, r['verificationId'].toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تأكيد التحويل برمز الهاتف',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.request['amount']} د.ع إلى ${widget.request['recipientName'] ?? 'المستلم المحدد'}',
              ),
              const SizedBox(height: 12),
              Text(
                _challenge == null
                    ? 'جارٍ إرسال رمز التأكيد إلى هاتف حسابك'
                    : 'أرسلنا رمزًا إلى الرقم المنتهي بـ $_phoneHint. صلاحيته 5 دقائق.',
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('transfer_confirmation_code'),
                controller: _code,
                enabled: !_busy && _challenge != null,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'رمز التأكيد',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.secondary),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                ),
                onPressed: _busy || _challenge == null ? null : _verify,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child:
                      _busy
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('تأكيد وإكمال التحويل'),
                ),
              ),
              TextButton(
                onPressed: _busy || _resend > 0 ? null : _send,
                child: Text(
                  _resend > 0
                      ? 'إعادة إرسال الرمز بعد $_resend ثانية'
                      : 'إعادة إرسال الرمز',
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('رجوع دون تحويل'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
