import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'basket_line_card.dart' show basketMoney;

Future<void> showDiscountNoticeSheet(BuildContext context, {
  String? offerTitle,
  required String message,
  double? minimum,
  double? subtotal,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => DiscountNoticeSheet(
    offerTitle: offerTitle, message: message, minimum: minimum, subtotal: subtotal,
  ),
);

class DiscountNoticeSheet extends StatelessWidget {
  final String? offerTitle;
  final String message;
  final double? minimum, subtotal;
  const DiscountNoticeSheet({super.key, this.offerTitle, required this.message,
    this.minimum, this.subtotal});

  @override
  Widget build(BuildContext context) {
    final below = minimum != null && subtotal != null && minimum!.isFinite &&
        subtotal!.isFinite && subtotal! >= 0 && minimum! > subtotal!;
    Widget amount(String label, double value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 16, runSpacing: 4,
        children: [Text(label), Text(basketMoney(value),
          style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600))]),
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(top: false, child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))),
            Row(children: [
              const Icon(Icons.local_offer_outlined, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(child: Text(below ? 'لم تصل للحد الأدنى للعرض' : 'تعذر تطبيق الخصم',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.secondary))),
              IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            if (offerTitle?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Text(offerTitle!, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(below ? 'أضف أصنافًا بقيمة ${basketMoney(minimum! - subtotal!)} لتتمكن من تطبيق هذا الخصم.' : message),
            if (below) ...[
              const SizedBox(height: 16),
              Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF4F6FA), borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  amount('قيمة الأصناف الحالية', subtotal!),
                  amount('الحد الأدنى للعرض', minimum!),
                  const Divider(),
                  amount('المبلغ المتبقي', minimum! - subtotal!, bold: true),
                ])),
              const SizedBox(height: 12),
              const Text('الحد الأدنى يخص قيمة الأصناف قبل الخصم، ولا يشمل رسوم التوصيل أو الخدمة أو الإكرامية.',
                style: TextStyle(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            const Text('لم يُطبّق هذا الخصم على الطلب.', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.primary,
              foregroundColor: AppColors.secondary, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: () => Navigator.pop(context), child: const Text('العودة للطلب')),
          ]),
      )),
    );
  }
}
