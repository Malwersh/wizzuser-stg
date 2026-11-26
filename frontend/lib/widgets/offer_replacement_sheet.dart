import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'basket_line_card.dart' show basketMoney;

Future<bool> confirmOfferReplacement(
  BuildContext context, {
  required String title,
  required int currentTotalMinor,
  required int replacementTotalMinor,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.swap_horiz_rounded,
                    color: AppColors.secondaryDark,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'استبدال خصم التوصيل؟',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'عرض «$title» يحلّ محل خصم التوصيل الحالي؛ لا يُجمعان في هذا الاختيار.',
                    style: const TextStyle(
                      height: 1.6,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xfff1f4fa),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('الإجمالي بخصم التوصيل'),
                            ),
                            Text(basketMoney(currentTotalMinor / 1000)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('الإجمالي بالعرض الجديد'),
                            ),
                            Text(
                              basketMoney(replacementTotalMinor / 1000),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (replacementTotalMinor > currentTotalMinor) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'الإجمالي سيزيد عند اختيار هذا العرض.',
                      style: TextStyle(color: Color(0xffa33a32)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.secondaryDark,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('استبدال العرض'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'الاحتفاظ بخصم التوصيل',
                      style: TextStyle(color: AppColors.secondaryDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ) ??
    false;
