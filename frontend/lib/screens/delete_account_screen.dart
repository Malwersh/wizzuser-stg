import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_colors.dart';
import '../services/account_deletion_service.dart';
import '../services/session_service.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _service = AccountDeletionService();
  final _code = TextEditingController();
  final _requestId = const Uuid().v4();
  Map<String, dynamic>? _request;
  String? _challengeId, _phoneHint, _error;
  bool _busy = true, _confirmed = false, _statusKnown = false;
  int _resendSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _refresh() => _perform(() async {
    final data = await _service.call('status');
    if ((data['request'] as Map?)?['status'] == 'COMPLETED' &&
        SessionService.instance.isLoggedIn) {
      await SessionService.instance.logout();
    }
    if (mounted) {
      setState(() {
        _request = data['request'] as Map<String, dynamic>?;
        _statusKnown = true;
      });
    }
  });

  Future<void> _send() => _perform(() async {
    final data = await _service.call('send', body: {'requestId': _requestId});
    if (!mounted) return;
    setState(() {
      _challengeId = data['challengeId'] as String;
      _phoneHint = data['phoneHint'] as String?;
      _resendSeconds = (data['resendAfter'] as num).toInt();
      _code.clear();
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
      }
      if (mounted) {
        setState(() {
          _resendSeconds = (_resendSeconds - 1).clamp(0, 60);
        });
      }
    });
  });

  Future<void> _submit() => _perform(() async {
    final data = await _service.call(
      'request',
      body: {
        'requestId': _requestId,
        'challengeId': _challengeId,
        'code': _code.text.trim(),
      },
    );
    if (mounted) {
      setState(() {
        _request = data;
        _code.clear();
      });
    }
  });

  String get _statusText => switch (_request?['status']) {
    'COMPLETED' => 'اكتمل حذف الحساب',
    'PENDING_SETTLEMENT' => 'طلب الحذف مسجّل وبانتظار تسوية الطلبات أو الأموال',
    'PENDING_POLICY' => 'طلب الحذف مسجّل وبانتظار اكتمال تجهيز التنفيذ',
    'PROCESSING' => 'حذف الحساب قيد التنفيذ',
    'RETRY_REQUIRED' => 'طلبك محفوظ؛ التنفيذ يحتاج متابعة وإعادة محاولة',
    _ => 'طلب الحذف مسجّل وبانتظار التنفيذ',
  };

  String _blocker(Map<String, dynamic> item) => switch (item['code']) {
    'REFUND_REQUIRED' =>
      'رصيد يحتاج تسوية: ${item['amount']} د.ع. يمكنك تحويله إلى محفظة أخرى أو طلب صرف زين كاش من الإدارة.',
    'AMOUNT_DUE' => 'يوجد مبلغ مستحق يحتاج تسوية.',
    'ACTIVE_ORDERS' => 'توجد طلبات لم تنتهِ بعد.',
    'ACTIVE_HOLDS' || 'LOCKED_BALANCE' => 'توجد أموال محجوزة مرتبطة بالطلبات.',
    'PENDING_TRANSFERS' => 'توجد تحويلات لم تُحسم بعد.',
    'PENDING_PAYMENTS' => 'توجد عمليات دفع أو شحن لم تُحسم بعد.',
    _ => 'يوجد إجراء يحتاج متابعة قبل تنفيذ الحذف.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: const Text('حذف الحساب'),
      centerTitle: true,
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.secondary,
    ),
    body: Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(
            Icons.person_remove_outlined,
            size: 48,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 20),
          const Text(
            'حذف حسابك وبياناتك الشخصية',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'تُزال بيانات حسابك الشخصية والعناوين والمفضلة بعد التحقق من هويتك وتسوية الطلبات والأموال. نحتفظ بالسجلات المالية الضرورية لمدة 7 سنوات وفق السياسة الحالية، وبالبيانات اللازمة لنزاع أو التزام موثّق قائم.',
            style: TextStyle(height: 1.7, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          if (_request != null) ...[
            Text(
              _statusText,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in (_request!['blockers'] as List? ?? []))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_blocker(Map<String, dynamic>.from(item as Map))),
              ),
            SelectableText(
              'مرجع الطلب: ${_request!['requestId']}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ] else ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.secondary,
              value: _confirmed,
              onChanged:
                  _busy
                      ? null
                      : (v) => setState(() {
                        _confirmed = v ?? false;
                      }),
              title: const Text('أفهم أثر حذف الحساب وأريد متابعة الطلب'),
            ),
            if (_challengeId != null) ...[
              Text(
                'أرسلنا رمزًا إلى رقم حسابك $_phoneHint. أدخله لتأكيد طلب الحذف.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'رمز التحقق',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || !_confirmed ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.white,
                ),
                child: const Text('تأكيد طلب الحذف'),
              ),
            ],
            TextButton(
              onPressed:
                  _busy || !_confirmed || !_statusKnown || _resendSeconds > 0
                      ? null
                      : _send,
              child: Text(
                _resendSeconds > 0
                    ? 'إعادة الإرسال بعد $_resendSeconds ثانية'
                    : _challengeId == null
                    ? 'إرسال رمز التحقق'
                    : 'إعادة إرسال الرمز',
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.secondary),
              ),
            ),
          if (_busy)
            const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('تحديث حالة الطلب'),
          ),
        ],
      ),
    ),
  );
}
