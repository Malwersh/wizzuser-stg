import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import '../constants/app_colors.dart';

/// Displays only the server proposal. It never computes charges or submits an order.
class CommercialConfirmationSheet extends StatefulWidget {
  final Map<String, dynamic> proposal;
  final String storeName, customerName, phone, address, paymentLabel, instructions;
  final List<Map<String, dynamic>> items;
  final DateTime Function()? clock;
  const CommercialConfirmationSheet({super.key, required this.proposal,
    required this.storeName, required this.customerName, required this.phone,
    required this.address, required this.paymentLabel, required this.items,
    this.instructions = '', this.clock});
  @override
  State<CommercialConfirmationSheet> createState() => _CommercialConfirmationSheetState();
}
class _CommercialConfirmationSheetState extends State<CommercialConfirmationSheet> {
  Timer? _timer;
  DateTime get now => widget.clock?.call() ?? DateTime.now();
  DateTime get expires => DateTime.parse(widget.proposal['expiresAt']);
  bool get expired => !now.isBefore(expires);
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  String amount(String key) => '${NumberFormat('#,##0.###', 'en').format((widget.proposal[key]['minorAmount'] as int) / 1000)} د.ع';
  Widget detail(IconData icon, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 21, color: AppColors.secondary), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 3), Text(value, style: const TextStyle(fontSize: 15, height: 1.4)),
      ])),
    ]));
  Widget moneyRow(String label, String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
      Expanded(child: Text(label)), Text(amount(key), textDirection: TextDirection.rtl,
        style: const TextStyle(fontWeight: FontWeight.w600)),
    ]));
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
    child: SafeArea(top: false, child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 12, 12), child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراجعة الطلب', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            SizedBox(height: 5), Text('راجع التفاصيل والمبلغ النهائي قبل الإرسال', style: TextStyle(color: Colors.black54)),
          ])),
          IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close)),
        ])),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
            color: const Color(0xfffff8df), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.storeName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final item in widget.items) Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${item['quantity'] ?? 1} × ${item['name'] ?? item['dish_name'] ?? item['productName'] ?? 'صنف'}')),
            ])),
          const SizedBox(height: 12),
          detail(Icons.location_on_outlined, 'عنوان التوصيل', widget.address),
          if (widget.customerName.isNotEmpty || widget.phone.isNotEmpty)
            detail(Icons.person_outline, 'معلومات المستلم', [widget.customerName, widget.phone].where((v) => v.isNotEmpty).join('\n')),
          detail(Icons.payments_outlined, 'طريقة الدفع', widget.paymentLabel),
          if (widget.instructions.trim().isNotEmpty) detail(Icons.notes_outlined, 'تعليمات التوصيل', widget.instructions),
          const Divider(height: 25),
          const Text('تفاصيل المبلغ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          moneyRow('قيمة الأصناف', 'goodsGross'), moneyRow('الخصم', 'discount'),
          moneyRow('رسوم الخدمة', 'serviceFee'), moneyRow('رسوم التوصيل', 'deliveryFee'),
          if (widget.proposal.containsKey('driverTip')) moneyRow('الإكرامية', 'driverTip'),
          const SizedBox(height: 12),
          Text(expired ? 'انتهت صلاحية هذا السعر. أعد المراجعة للحصول على المبلغ المحدّث.'
              : 'لن يُرسل الطلب إلى المطعم إلا بعد تأكيدك أدناه.',
            style: TextStyle(color: expired ? Colors.red.shade700 : Colors.black54, height: 1.5)),
          const SizedBox(height: 16),
        ]))),
        Container(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: Color(0xffeeeeee)))),
          child: Column(children: [
            Row(children: [const Expanded(child: Text('الإجمالي النهائي', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              Text(amount('customerTotal'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.secondary))]),
            const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: () => Navigator.pop(context, !expired),
              child: Text(expired ? 'إعادة مراجعة السعر' : 'تأكيد الطلب • ${amount('customerTotal')}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
          ])),
      ]),
    )));
}
