import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

int? parseDriverTipIqd(String text) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final normalized =
      text.trim().split('').map((c) {
        final a = digits.indexOf(c), p = persian.indexOf(c);
        return a >= 0
            ? '$a'
            : p >= 0
            ? '$p'
            : c;
      }).join();
  if (!RegExp(r'^\d+$').hasMatch(normalized)) return null;
  final amount = int.tryParse(normalized);
  return amount != null && amount <= 1000000000 ? amount : null;
}

class DriverTipSelector extends StatelessWidget {
  final int amountIqd;
  final bool enabled;
  final bool showHeading;
  final ValueChanged<int> onChanged;
  const DriverTipSelector({
    super.key,
    required this.amountIqd,
    required this.onChanged,
    this.enabled = true,
    this.showHeading = true,
  });

  Future<void> _custom(BuildContext context) async {
    var text = amountIqd == 0 ? '' : '$amountIqd';
    final form = GlobalKey<FormState>();
    final amount = await showDialog<int>(
      context: context,
      builder:
          (dialog) => AlertDialog(
            title: const Text('إكرامية السائق'),
            content: Form(
              key: form,
              child: TextFormField(
                initialValue: text,
                onChanged: (value) => text = value,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [LengthLimitingTextInputFormatter(12)],
                decoration: const InputDecoration(
                  labelText: 'المبلغ بالدينار العراقي',
                ),
                validator:
                    (v) =>
                        parseDriverTipIqd(v ?? '') == null
                            ? 'أدخل مبلغًا صحيحًا بالدينار'
                            : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () {
                  if (form.currentState!.validate())
                    Navigator.pop(dialog, parseDriverTipIqd(text));
                },
                child: const Text('تطبيق'),
              ),
            ],
          ),
    );
    if (amount != null && context.mounted) onChanged(amount);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading)
          const Text(
            'إكرامية السائق (اختياري)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 8),
        const Text(
          'تصل الإكرامية بالكامل إلى السائق.',
          style: TextStyle(fontSize: 13, color: Color(0xFF53627B)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in [0, 500, 1000, 2000])
              ChoiceChip(
                label: Text(amount == 0 ? 'دون إكرامية' : '$amount د.ع'),
                selected: amountIqd == amount,
                onSelected: enabled ? (_) => onChanged(amount) : null,
              ),
            ActionChip(
              label: Text(
                [0, 500, 1000, 2000].contains(amountIqd)
                    ? 'مبلغ آخر'
                    : '$amountIqd د.ع • تعديل',
              ),
              onPressed: enabled ? () => _custom(context) : null,
            ),
          ],
        ),
      ],
    ),
  );
}
