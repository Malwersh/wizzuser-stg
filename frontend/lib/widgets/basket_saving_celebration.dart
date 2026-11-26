import 'saving_celebration_motion.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/pending_offer.dart';
import '../services/point_invoice_321.dart';
import 'basket_line_card.dart' show basketMoney;

class BasketSavingCelebration extends StatefulWidget {
  final String branch;
  final List<Map<String, dynamic>> items;
  const BasketSavingCelebration({
    super.key,
    required this.branch,
    required this.items,
  });
  @override
  State<BasketSavingCelebration> createState() =>
      _BasketSavingCelebrationState();
}

class _BasketSavingCelebrationState extends State<BasketSavingCelebration> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      PendingOffer.revision,
      PointInvoice321.instance,
    ]),
    builder: (context, _) {
      final pending = PendingOffer.current;
      final request = PointInvoice321.basketRequest(
        widget.branch,
        widget.items,
      );
      final invoice =
          request == null ? null : PointInvoice321.instance.peek(request);
      final scope = pending?.offer['automaticBasketScope'];
      if (scope is! String ||
          request == null ||
          invoice == null ||
          request['deliveryBenefitId'] != pending?.offer['id'])
        return const SizedBox.shrink();
      final saving = pending!.offer['savingMinor'];
      final before = pending.offer['previousTotalMinor'];
      final total = invoice['customerTotal']?['minorAmount'];
      if (saving is! int ||
          saving <= 0 ||
          before is! int ||
          total is! int ||
          before - total != saving)
        return const SizedBox.shrink();
      final free = invoice['deliveryFee']?['minorAmount'] == 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SavingCelebrationMotion(
          celebrationKey: '$scope|${pending.offer['id']}',
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xffedf7f1),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xffcce7d6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.celebration_outlined,
                      color: Color(0xff22744b),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        free
                            ? 'مبروك، توصيلك مجاني!'
                            : 'مبروك، وفّرت ${basketMoney(saving / 1000)}',
                        style: const TextStyle(
                          color: AppColors.secondaryDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'طُبّقت ميزة التوصيل تلقائيًا على سلتك.',
                  style: TextStyle(color: Color(0xff427054), fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      basketMoney(before / 1000),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      'الإجمالي الآن ${basketMoney(total / 1000)}',
                      style: const TextStyle(
                        color: Color(0xff22744b),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
