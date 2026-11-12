import '../utils/iraqi_phone.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class CheckoutDeliverySummary extends StatelessWidget {
  final String name, phone, address;
  final VoidCallback onEdit;
  final bool compact;
  const CheckoutDeliverySummary({
    super.key,
    required this.name,
    required this.phone,
    required this.address,
    required this.onEdit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE7EBF2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.location_on_outlined,
          color: AppColors.secondaryDark,
          size: 23,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'عنوان التوصيل',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryDark,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                address,
                maxLines: compact ? 2 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF53627B),
                ),
              ),
              if (!compact) const SizedBox(height: 5),
              if (!compact) Text(name, style: const TextStyle(fontSize: 13)),
              if (!compact)
                Text(
                  IraqiPhone.display(phone),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF53627B),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onEdit,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondaryDark,
            minimumSize: const Size(44, 44),
          ),
          child: const Text('تعديل'),
        ),
      ],
    ),
  );
}
