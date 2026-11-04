import '../widgets/wallet_transfer_gate.dart';
import '../widgets/transfer_verification_sheet.dart';
import 'verified_phone_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_colors.dart';
import '../services/wallet_transfer_service.dart';

class WalletTransferScreen extends StatefulWidget {
  const WalletTransferScreen({super.key});
  @override
  State<WalletTransferScreen> createState() => _WalletTransferScreenState();
}

class _WalletTransferScreenState extends State<WalletTransferScreen> {
  final api = WalletTransferService();
  final phone = TextEditingController(),
      amount = TextEditingController(),
      reason = TextEditingController();
  Map<String, dynamic>? account, recipient, pending;
  List<Map<String, dynamic>> history = [];
  String? error, cursor;
  String recipientType = 'DRIVER';
  String get pendingKey => 'wallet_pending_transfer_${account!['walletId']}';
  bool loading = true, searching = false, sending = false, more = false;
  bool get uncertain => pending != null;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    phone.dispose();
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  String money(dynamic n) => '${n ?? 0} د.ع';
  Future<void> _load() async {
    try {
      final results = await Future.wait([
        api.call('context'),
        api.call('history'),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(
        'wallet_pending_transfer_${results[0]['walletId']}',
      );
      if (!mounted) return;
      setState(() {
        if (pending == null && saved != null) {
          pending = Map<String, dynamic>.from(jsonDecode(saved));
        }
        if (pending != null) {
          amount.text = pending!['amount'].toString();
          reason.text = pending!['reason'] ?? '';
          phone.text = pending!['recipientPhone'] ?? '';
          recipient = {
            'walletId': pending!['recipientWalletId'],
            'name': pending!['recipientName'] ?? 'المستلم المحدد',
            'phone': pending!['recipientPhone'] ?? '',
          };
        }
        account = results[0];
        history = List<Map<String, dynamic>>.from(
          results[1]['transactions'] ?? [],
        );
        cursor = results[1]['nextCursor'];
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> _find() async {
    FocusScope.of(context).unfocus();
    setState(() {
      searching = true;
      recipient = null;
      error = null;
    });
    try {
      final r = await api.call(
        'recipient',
        query: {'phone': phone.text.trim(), 'type': recipientType},
      );
      if (mounted) setState(() => recipient = r);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  int? _integer(String raw) => int.tryParse(
    raw.replaceAllMapped(
      RegExp('[٠-٩]'),
      (m) => '٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!).toString(),
    ),
  );
  Future<void> _submit() async {
    if (sending) return;
    if (pending == null) {
      final n = _integer(amount.text.trim()), a = account;
      if (a == null || recipient == null) {
        setState(() => error = 'اختر المستلم أولًا');
        return;
      }
      if (n == null ||
          n < (a['minAmount'] as num) ||
          n > (a['maxAmount'] as num) ||
          n > (a['available'] as num) ||
          n > (a['dailyRemaining'] as num)) {
        setState(() => error = 'أدخل مبلغًا ضمن حدود التحويل والرصيد المتاح');
        return;
      }
      if (reason.text.trim().length < 5) {
        setState(() => error = 'اكتب سبب التحويل بما لا يقل عن خمسة أحرف');
        return;
      }
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder:
            (c) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'تأكيد التحويل',
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    Text(recipient!['name'].toString()),
                    Text(
                      recipient!['phone'].toString(),
                      textDirection: TextDirection.ltr,
                    ),
                    const SizedBox(height: 16),
                    Text(money(n), style: Theme.of(c).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(reason.text.trim()),
                    const SizedBox(height: 16),
                    const Text(
                      'سيُخصم المبلغ من الرصيد المتاح. تحقق من اسم المستلم ورقمه قبل التأكيد.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('تأكيد وإرسال'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('رجوع'),
                    ),
                  ],
                ),
              ),
            ),
      );
      if (confirmed != true || !mounted) return;
      pending = {
        'requestId': const Uuid().v4(),
        'recipientWalletId': recipient!['walletId'],
        'amount': n,
        'reason': reason.text.trim(),
        'recipientName': recipient!['name'],
        'recipientPhone': recipient!['phone'],
      };
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pendingKey, jsonEncode(pending));
      final status = await api.call(
        'status',
        query: {'requestId': pending!['requestId'].toString()},
      );
      final result =
          status['status'] == 'COMPLETED' ? status : await _sendRequest();
      if (result['status'] == 'COMPLETED') await prefs.remove(pendingKey);
      if (!mounted) return;
      if (result['status'] != 'COMPLETED') {
        throw WalletTransferException(
          'العملية لم تكتمل بعد. تحقق بنفس مرجع التحويل.',
        );
      }
      setState(() {
        pending = null;
        recipient = null;
        phone.clear();
        amount.clear();
        reason.clear();
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم التحويل بنجاح')));
      }
    } on WalletTransferException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          // Retain the reference until the server confirms its outcome.
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () =>
              error =
                  'تعذر تأكيد النتيجة. أعد التحقق؛ سيُستخدم نفس المرجع لمنع تكرار التحويل.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'انقطع الاتصال. أعد التحقق بنفس مرجع التحويل.');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<Map<String, dynamic>> _sendRequest() async {
    try {
      return await api.call('request', body: pending);
    } on WalletTransferException catch (e) {
      if (e.code != 'REAUTH_REQUIRED' || !mounted) rethrow;
      final proof = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder:
            (_) => TransferVerificationSheet(
              request: Map<String, dynamic>.from(pending!),
              call: (path, body) => api.call(path, body: body),
            ),
      );
      if (proof == null) {
        throw WalletTransferException(
          'التحويل لم يُنفّذ. أكمل التحقق أو ألغِ المحاولة.',
        );
      }
      pending!['verificationId'] = proof;
      await (await SharedPreferences.getInstance()).setString(
        pendingKey,
        jsonEncode(pending),
      );
      return await api.call('request', body: pending);
    }
  }

  Future<void> _cancelAttempt() async {
    if (pending == null || sending) return;
    setState(() => sending = true);
    try {
      final result = await api.call('cancel', body: pending);
      if (!['CANCELLED', 'COMPLETED'].contains(result['status'])) {
        throw WalletTransferException('تعذر تأكيد حالة العملية');
      }
      await (await SharedPreferences.getInstance()).remove(pendingKey);
      if (!mounted) return;
      setState(() => pending = null);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['status'] == 'COMPLETED'
                  ? 'التحويل مكتمل بالفعل'
                  : 'أُلغيت المحاولة دون خصم',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _more() async {
    if (cursor == null || more) return;
    setState(() => more = true);
    try {
      final r = await api.call('history', query: {'cursor': cursor!});
      if (mounted) {
        setState(() {
          history.addAll(
            List<Map<String, dynamic>>.from(r['transactions'] ?? []),
          );
          cursor = r['nextCursor'];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => more = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    void Function(String)? changed,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      enabled: !sending && !uncertain && !searching,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric
              ? [FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩+]'))]
              : null,
      onChanged: changed,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => WalletTransferGate(check:()async{final current=await api.call('context');if(mounted)setState(()=>account=current);return current['canTransfer']==true;},builder:(transfersEnabled)=>Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: !sending,
      child: Scaffold(
        backgroundColor: AppColors.lightGrey,
        appBar: AppBar(
          title: const Text('محفظتي'),
          backgroundColor: Colors.white,
        ),
        body:
            loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                        ),
                      if (account == null)
                        OutlinedButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      if (account != null) ...[
                        if (account!['phoneVerified'] == true)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified_user_outlined,
                                  color: AppColors.secondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'رقمك موثّق: ${account!['verifiedPhone']}',
                                    style: const TextStyle(
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          OutlinedButton.icon(
                            onPressed:
                                sending
                                    ? null
                                    : () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) =>
                                                  const VerifiedPhoneScreen(),
                                        ),
                                      );
                                      if (mounted) await _load();
                                    },
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('توثيق رقمك لاستقبال التحويلات'),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'الرصيد المتاح للتحويل',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                money(account!['available']),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'المتبقي اليوم: ${money(account!['dailyRemaining'])}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'من ${money(account!['minAmount'])} إلى ${money(account!['maxAmount'])} لكل تحويل. الحد اليومي ${money(account!['dailyLimit'])} حسب توقيت بغداد.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 24),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'هذا رصيد التحويلات بين المحافظ، وهو منفصل حاليًا عن رصيد دفع الطلبات. لا تُنقل الأرصدة بينهما تلقائيًا.',
                          ),
                        ),
                        if (transfersEnabled && account!['canTransfer'] == true || uncertain) ...[
                          Text(
                            'المستلم',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: recipientType,
                            decoration: const InputDecoration(
                              labelText: 'نوع المستلم',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'DRIVER',
                                child: Text('سائق'),
                              ),
                              DropdownMenuItem(
                                value: 'CUSTOMER',
                                child: Text('مستخدم'),
                              ),
                            ],
                            onChanged:
                                sending || uncertain
                                    ? null
                                    : (value) => setState(() {
                                      recipientType = value!;
                                      recipient = null;
                                    }),
                          ),
                          const SizedBox(height: 16),
                          _field(
                            'رقم هاتف المستلم',
                            phone,
                            numeric: true,
                            changed: (_) => setState(() => recipient = null),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                searching || sending || uncertain
                                    ? null
                                    : _find,
                            icon:
                                searching
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.search),
                            label: const Text('البحث عن المستلم'),
                          ),
                          if (recipient != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person_outline),
                              title: Text(recipient!['name'].toString()),
                              subtitle: Text(
                                recipient!['phone'].toString(),
                                textDirection: TextDirection.ltr,
                              ),
                            ),
                          const SizedBox(height: 20),
                          _field('المبلغ بالدينار', amount, numeric: true),
                          _field('سبب التحويل', reason),
                          if (uncertain)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'يوجد تحويل قيد التحقق. لن تُنشأ عملية جديدة عند إعادة المحاولة.',
                              ),
                            ),
                          if(transfersEnabled) FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.secondary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: sending ? null : _submit,
                            icon:
                                sending
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.arrow_outward),
                            label: Text(
                              uncertain
                                  ? 'التحقق وإكمال التحويل'
                                  : 'مراجعة التحويل',
                            ),
                          ),
                        ] else
                          const Text('التحويلات غير متاحة حاليًا لهذا الحساب.'),
                        if (uncertain)
                          TextButton(
                            onPressed: sending ? null : _cancelAttempt,
                            child: const Text('إلغاء المحاولة إذا لم تُنفذ'),
                          ),
                        const SizedBox(height: 32),
                        Text(
                          'سجل التحويلات',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (history.isEmpty)
                          const Text('لا توجد تحويلات في هذه الصفحة.'),
                        for (final row in history)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              (row['amount'] as num) < 0
                                  ? Icons.north_east
                                  : Icons.south_west,
                              color: AppColors.secondary,
                            ),
                            title: Text(
                              '${(row['amount'] as num) < 0 ? 'تحويل صادر' : 'تحويل وارد'} · ${money((row['amount'] as num).abs())}',
                            ),
                            subtitle: Text(
                              '${row['description'] ?? ''}\n${DateTime.tryParse(row['createdAt'] ?? '')?.toLocal().toString().split('.').first ?? ''}',
                            ),
                            onTap:
                                () => showModalBottomSheet(
                                  context: context,
                                  showDragHandle: true,
                                  builder:
                                      (c) => SafeArea(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text('تحويل مكتمل'),
                                              Text(
                                                money(
                                                  (row['amount'] as num).abs(),
                                                ),
                                              ),
                                              Text(row['description'] ?? ''),
                                              const SizedBox(height: 12),
                                              const Text('مرجع التحويل'),
                                              SelectableText(
                                                row['transactionId'] ?? '',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                ),
                          ),
                        if (cursor != null)
                          TextButton(
                            onPressed: more ? null : _more,
                            child: Text(
                              more ? 'جارٍ التحميل…' : 'تحميل المزيد',
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
      ),
    ),
  ));
}
