import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/customer_order_policy.dart';

class CustomerOrderPolicyScreen extends StatelessWidget {
  final CustomerOrderPolicy? policy;
  const CustomerOrderPolicyScreen({super.key, this.policy});
  @override
  Widget build(BuildContext context) {
    final current = policy ?? CustomerOrderPolicy.current;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.secondaryDark,
          title: Text(current.title, style: const TextStyle(fontSize: 18)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'الإطلاق النقدي · الإصدار ${current.version}',
              style: const TextStyle(color: Color(0xFF53627B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            for (final section in current.sections)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE4EAF2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section['title'],
                      style: const TextStyle(
                        color: AppColors.secondaryDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      section['body'],
                      style: const TextStyle(
                        color: Color(0xFF36455B),
                        fontSize: 15,
                        height: 1.75,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
