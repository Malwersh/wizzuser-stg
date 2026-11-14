import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/address_model.dart';

class AddressCapacityChoice {
  final DetailedAddress? address;
  final bool manage;
  const AddressCapacityChoice.saved(this.address) : manage = false;
  const AddressCapacityChoice.manage() : address = null, manage = true;
}

class AddressCapacitySheet extends StatelessWidget {
  final List<DetailedAddress> addresses;
  const AddressCapacitySheet({super.key, required this.addresses});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'قائمة العناوين ممتلئة',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'لديك ١٠ عناوين محفوظة. اختر أحدها للتوصيل، أو افتح إدارة العناوين لحذف عنوان لم تعد تحتاجه ثم تابع حفظ الموقع الجديد.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: addresses.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final a = addresses[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.secondaryDark,
                    ),
                    title: Text(a.name),
                    subtitle: Text(
                      a.fullAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap:
                        () => Navigator.pop(
                          context,
                          AddressCapacityChoice.saved(a),
                        ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondaryDark,
              ),
              onPressed:
                  () => Navigator.pop(
                    context,
                    const AddressCapacityChoice.manage(),
                  ),
              child: const Text('إدارة العناوين والمتابعة'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('رجوع'),
            ),
          ],
        ),
      ),
    ),
  );
}
