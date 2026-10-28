import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/customer_order_policy.dart';
import 'customer_order_policy_screen.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final policy = CustomerOrderPolicy.current;
    Widget section(String title, String content) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.75,
              color: Color(0xFF36455B),
            ),
          ),
        ],
      ),
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text('الشروط والأحكام'),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.secondaryDark,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'خدمة الطلب والتوصيل · الإطلاق النقدي',
              style: TextStyle(color: Color(0xFF53627B)),
            ),
            const SizedBox(height: 16),
            section(
              'الحساب واستخدام الخدمة',
              'يمكنك التصفح كضيف. يلزم تسجيل الدخول إلى حسابك لإرسال الطلب ومتابعته. استخدم بيانات اتصال صحيحة، وحدد نقطة التوصيل واسم الحي وأقرب نقطة دالة. احتفظ برمز التحقق وبيانات حسابك لنفسك.',
            ),
            section(
              'الأصناف والتوصيل',
              'يجهّز المتجر الأصناف، وينقل السائق الطلب وفق إجراءات التسليم. تعرض الفاتورة المبلغ للمراجعة قبل تأكيد الطلب. وقت الوصول تقديري وقد يتغير حسب التجهيز والطريق وتوفر السائق. عند وجود خطأ أو تعذّر التسليم، تراجع الإدارة الحالة والأدلة.',
            ),
            for (final item in policy.sections)
              section(item['title'], item['body']),
            section(
              'التواصل والمراجعة',
              'للمساعدة في طلب، افتح تفاصيله واستخدم مسار الدعم أو الشكوى المتاح. تظهر حالة القضية وقرارها وسببه ضمن المسار المخصص. لا تعني إفادة طرف واحد ثبوت المسؤولية أو استحقاق التعويض.',
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondaryDark,
              ),
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CustomerOrderPolicyScreen(policy: policy),
                    ),
                  ),
              icon: const Icon(Icons.policy_outlined),
              label: Text('سياسة الطلب · الإصدار ${policy.version}'),
            ),
          ],
        ),
      ),
    );
  }
}
