import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../services/customer_order_complaint_service.dart';
import 'customer_support_chat_screen.dart';

class CustomerOrderComplaintScreen extends StatefulWidget {
  final String orderId;
  final CustomerOrderComplaintService? service;
  const CustomerOrderComplaintScreen({
    super.key,
    required this.orderId,
    this.service,
  });
  @override
  State<CustomerOrderComplaintScreen> createState() => _ComplaintState();
}

class _ComplaintState extends State<CustomerOrderComplaintScreen> {
  static const navy = Color(0xFF00296B), gold = Color(0xFFFFC600);
  static const types = {
    'MISSING_ITEMS': 'أصناف ناقصة',
    'WRONG_ITEMS': 'أصناف مختلفة',
    'QUALITY': 'جودة الطلب',
    'NOT_DELIVERED': 'لم أستلم الطلب',
    'SAFETY': 'مشكلة تتعلق بالسلامة',
    'OTHER': 'مشكلة أخرى',
  };
  static const statuses = {
    'OPEN': 'تم استلام الشكوى',
    'IN_REVIEW': 'قيد المراجعة',
    'WAITING_CUSTOMER': 'نحتاج معلومات منك',
    'REMEDY_PENDING': 'اعتمد التعويض — جارٍ تجهيزه',
    'DECIDED': 'صدر قرار المراجعة',
    'APPEAL_REVIEW': 'اعتراضك قيد المراجعة',
    'CLOSED': 'أُغلقت الشكوى',
  };
  late final CustomerOrderComplaintService service;
  final reason = TextEditingController(), extra = TextEditingController();
  final requests = <String, String>{};
  Map<String, dynamic>? data;
  String type = 'MISSING_ITEMS';
  String? error;
  bool busy = false;
  XFile? pendingImage;
  String? pendingImageId;
  @override
  void initState() {
    super.initState();
    service = widget.service ?? CustomerOrderComplaintService();
    load();
  }

  @override
  void dispose() {
    reason.dispose();
    extra.dispose();
    if (widget.service == null) service.dispose();
    super.dispose();
  }

  String friendly(Object e) {
    final s = e.toString();
    if (s.contains('WINDOW_EXPIRED'))
      return 'انتهت مهلة الشكوى العادية. بلاغات السلامة تبقى متاحة للمراجعة.';
    if (s.contains('APPEAL_UNAVAILABLE'))
      return 'سبق تقديم اعتراض لهذا القرار أو انتهت مهلته.';
    if (s.contains('IMAGE_SIZE'))
      return 'اختر صورة JPEG أو PNG لا تتجاوز ٢ ميغابايت.';
    if (s.contains('IMAGE'))
      return 'لم نتأكد من إرفاق الصورة. أعد المحاولة بالصورة نفسها.';
    if (s.contains('CHANGED') || s.contains('ALREADY_OPEN'))
      return 'تغيرت حالة الشكوى. حدّث الصفحة وراجعها قبل المحاولة.';
    if (s.contains('UNAUTHORIZED')) return 'أعد تسجيل الدخول للمتابعة.';
    return 'تعذر تأكيد العملية. يمكنك إعادة المحاولة؛ لن تُسجل مرتين.';
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final next = await service.call(widget.orderId, {'action': 'READ'});
      if (mounted)
        setState(() {
          data = next;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        final d = data?['decision'];
        if (d is Map && d['acknowledgedAt'] == null)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                !busy &&
                ModalRoute.of(context)?.isCurrent == true &&
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed)
              act('ACK_DECISION', {'decisionId': d['decisionId']});
          });
      }
    }
  }

  Future<void> act(String action, Map<String, dynamic> values) async {
    if (busy) return;
    if (action != 'ACK_DECISION' &&
        '${values['reason'] ?? ''}'.trim().length < 5) {
      setState(() => error = 'اكتب وصفًا واضحًا من خمسة أحرف على الأقل.');
      return;
    }
    final version = data?['version'] ?? 0,
        fingerprint = jsonEncode([action, version, values]),
        id = requests.putIfAbsent(fingerprint, () => const Uuid().v4());
    setState(() => busy = true);
    try {
      await service.call(widget.orderId, {
        'action': action,
        'expectedVersion': version,
        'requestId': id,
        ...values,
      });
      final next = await service.call(widget.orderId, {'action': 'READ'});
      if (mounted)
        setState(() {
          data = next;
          error = null;
          if (action == 'ADD_MESSAGE') extra.clear();
        });
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> image() async {
    if (busy || data?['supportSessionId'] == null) return;
    final file =
        pendingImage ??
        await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
    if (file == null || !mounted) return;
    pendingImage = file;
    pendingImageId ??= const Uuid().v4();
    setState(() => busy = true);
    try {
      final bytes = await file.readAsBytes(),
          mime =
              bytes.length >= 8 && bytes[0] == 137 ? 'image/png' : 'image/jpeg';
      await service.upload(
        widget.orderId,
        data!['supportSessionId'],
        bytes,
        mime,
        pendingImageId!,
      );
      if (!mounted) return;
      setState(() => busy = false);
      await act('ADD_IMAGE', {
        'attachmentId': pendingImageId,
        'reason': 'صورة الطلب المرفقة من الزبون',
      });
      if (error == null) {
        pendingImage = null;
        pendingImageId = null;
      }
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE2E7F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: navy,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
  Widget button(String title, VoidCallback? tap) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: gold,
      foregroundColor: navy,
      minimumSize: const Size.fromHeight(46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: busy ? null : tap,
    child: Text(title),
  );
  @override
  Widget build(BuildContext context) {
    final opened = data?['caseId'] != null,
        d = data?['decision'] as Map?,
        closed = data?['status'] == 'CLOSED';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          title: const Text('مساعدة بخصوص الطلب'),
          backgroundColor: Colors.white,
          foregroundColor: navy,
          actions: [
            IconButton(
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث الحالة',
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) const LinearProgressIndicator(color: navy),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFB3261E)),
                  ),
                ),
              if (data == null && !busy) button('إعادة المحاولة', load),
              if (data != null && !opened)
                card('ما المشكلة في طلبك؟', [
                  const Text(
                    'ستصل الشكوى إلى فريق الدعم مع رقم الطلب. أرفق الصور بعد تسجيلها، ولا تُعد الشكوى إلغاءً للطلب.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'نوع المشكلة',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        types.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                    onChanged: busy ? null : (v) => setState(() => type = v!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reason,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'صف ما حدث',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data?['canOpen'] == false && type != 'SAFETY')
                    const Text(
                      'انتهت مهلة الشكوى العادية لهذا الطلب.',
                      style: TextStyle(color: Color(0xFFB3261E)),
                    ),
                  button(
                    'إرسال الشكوى',
                    data?['canOpen'] == false && type != 'SAFETY'
                        ? null
                        : () => act('OPEN', {
                          'type': type,
                          'reason': reason.text.trim(),
                        }),
                  ),
                ]),
              if (opened)
                card(statuses[data?['status']] ?? 'متابعة الشكوى', [
                  Text(
                    types[data?['type']] ?? 'شكوى الطلب',
                    style: const TextStyle(
                      color: navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${data?['description'] ?? ''}'),
                  if (data?['customerRequest'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${data!['customerRequest']['text']}',
                        style: const TextStyle(color: navy),
                      ),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => CustomerSupportChatScreen(
                                  orderId: widget.orderId,
                                  sessionId: data!['supportSessionId'],
                                ),
                          ),
                        ),
                    icon: const Icon(Icons.support_agent),
                    label: const Text('محادثة الدعم بخصوص هذا الطلب'),
                  ),
                ]),
              if (d != null)
                card('قرار المراجعة', [
                  Text('${d['reason']}'),
                  if ((d['remedyAmountIqd'] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'خصم تعويضي على طلب لاحق: ${d['remedyAmountIqd']} د.ع',
                        style: const TextStyle(
                          color: navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('الخصم التعويضي منفصل عن رد مبلغ نقدي.'),
                  if (d['acknowledgedAt'] == null)
                    TextButton(
                      onPressed:
                          () => act('ACK_DECISION', {
                            'decisionId': d['decisionId'],
                          }),
                      child: const Text('اطلعت على القرار'),
                    ),
                ]),
              if (opened && !closed)
                card('معلومات وصور إضافية', [
                  TextField(
                    controller: extra,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'تفاصيل إضافية لفريق المراجعة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  button(
                    'إضافة التفاصيل',
                    () => act('ADD_MESSAGE', {'reason': extra.text.trim()}),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : image,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      pendingImage != null
                          ? 'إعادة محاولة إرفاق الصورة'
                          : 'إرفاق صورة الطلب',
                    ),
                  ),
                ]),
              if (opened && data?['canAppeal'] == true)
                card('إعادة مراجعة القرار', [
                  const Text(
                    'يمكنك الاعتراض مرة واحدة على كل قرار خلال المهلة بعد الاطلاع عليه.',
                  ),
                  Text(
                    'مهلة الاعتراض: ${(data?['appealWindowSeconds'] ?? 0) ~/ 3600} ساعة',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy ? null : () => appeal(d!['decisionId']),
                    child: const Text('تقديم اعتراض'),
                  ),
                ]),
              if (opened &&
                  (data?['evidence'] as List? ?? []).any(
                    (e) => e['attachmentId'] != null,
                  ))
                card('الصور المرفقة', [
                  for (final e in (data?['evidence'] as List? ?? []).where(
                    (e) => e['attachmentId'] != null,
                  ))
                    TextButton.icon(
                      onPressed:
                          busy
                              ? null
                              : () =>
                                  viewImage(e['sessionId'], e['attachmentId']),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('عرض الصورة المرسلة'),
                    ),
                ]),
              if (data?['appeal'] != null)
                card('الاعتراض', [
                  Text(
                    data!['appeal']['status'] == 'OPEN'
                        ? 'اعتراضك قيد المراجعة'
                        : 'تمت مراجعة الاعتراض؛ راجع أحدث قرار.',
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> viewImage(String sessionId, String attachmentId) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final bytes = await service.readImage(sessionId, attachmentId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (context) => Dialog(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Image.memory(bytes, fit: BoxFit.contain)),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              ),
            ),
      );
    } catch (_) {
      if (mounted)
        setState(
          () =>
              error =
                  'الصورة غير متاحة حاليًا أو انتهت مدة إتاحتها. يمكنك إرسال نسخة جديدة عند الحاجة.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> appeal(String id) async {
    final input = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.viewInsetsOf(context).bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'سبب الاعتراض',
                    style: TextStyle(color: navy, fontSize: 20),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: input,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'ما الذي تريد إعادة مراجعته؟',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, input.text.trim()),
                    child: const Text('إرسال الاعتراض'),
                  ),
                ],
              ),
            ),
          ),
    );
    input.dispose();
    if (value != null && mounted)
      await act('APPEAL', {'decisionId': id, 'reason': value});
  }
}
