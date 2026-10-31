import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class CheckoutSignInPanel extends StatelessWidget {
  final String storeName;
  final int itemCount;
  final String? areaName;
  final bool busy;
  final VoidCallback onSignIn;
  const CheckoutSignInPanel({
    super.key,
    required this.storeName,
    required this.itemCount,
    this.areaName,
    this.busy = false,
    required this.onSignIn,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.verified_user_outlined,
          size: 52,
          color: AppColors.secondaryDark,
        ),
        const SizedBox(height: 20),
        const Text(
          'تحقق من رقمك لإتمام الطلب',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryDark,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'يمكنك التصفح كضيف. لإرسال الطلب ومتابعته والتواصل مع الدعم، سجّل الدخول أو أنشئ حسابك برقم الهاتف.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.7, color: Color(0xFF52627A)),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE1E7F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                storeName,
                style: const TextStyle(
                  color: AppColors.secondaryDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text('$itemCount قطعة في سلتك'),
              if (areaName != null) ...[
                const SizedBox(height: 10),
                Text('منطقة التوصيل: $areaName'),
              ],
              const SizedBox(height: 14),
              const Text(
                'ستبقى سلتك ونقطة التوصيل عند العودة. تراجع الإجمالي قبل تأكيد الطلب.',
                style: TextStyle(color: Color(0xFF52627A), height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.secondaryDark,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: busy ? null : onSignIn,
          icon: const Icon(Icons.phone_iphone),
          label: const Text('التحقق بالهاتف والمتابعة'),
        ),
      ],
    ),
  );
}
