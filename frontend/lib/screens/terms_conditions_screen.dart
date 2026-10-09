// lib/screens/terms_conditions_screen.dart

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'الشروط والأحكام',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.article_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الشروط والأحكام',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'الشروط والأحكام الخاصة باستخدام التطبيق',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),

              // Content
              _buildSection(
                title: '1. القبول بالشروط',
                content: '''باستخدامك لتطبيق زاد للتوصيل، فإنك توافق على الالتزام بهذه الشروط والأحكام. إذا كنت لا توافق على أي من هذه الشروط، يرجى عدم استخدام التطبيق.

هذه الشروط قابلة للتطبيق على جميع المستخدمين، بما في ذلك:
• العملاء
• المطاعم الشريكة
• سائقي التوصيل''',
              ),

              _buildSection(
                title: '2. وصف الخدمة',
                content: '''زاد هو تطبيق يربط بين العملاء والمطاعم وسائقي التوصيل لتقديم خدمة توصيل الطعام. نحن نوفر منصة تقنية فقط ولا نملك أو نشغل المطاعم.

خدماتنا تشمل:
• عرض قوائم المطاعم والأسعار
• تسهيل عملية الطلب والدفع
• تنسيق عملية التوصيل
• خدمة العملاء''',
              ),

              _buildSection(
                title: '3. التسجيل والحساب',
                content: '''لاستخدام التطبيق، يجب عليك:
• تقديم معلومات صحيحة ومحدثة
• الحفاظ على سرية كلمة المرور
• إشعارنا بأي استخدام غير مصرح به لحسابك
• تحديث معلوماتك عند الحاجة

أنت مسؤول عن جميع الأنشطة التي تحدث في حسابك.''',
              ),

              _buildSection(
                title: '4. الطلبات والدفع',
                content: '''عند تقديم طلب:
• الأسعار المعروضة نهائية وتشمل جميع الرسوم
• الدفع مطلوب قبل تحضير الطلب
• يمكن إلغاء الطلب خلال فترة محددة
• أوقات التوصيل تقديرية وقد تختلف

طرق الدفع المقبولة:
• الدفع نقداً عند التوصيل
• البطاقات الائتمانية
• المحافظ الإلكترونية''',
              ),

              _buildSection(
                title: '5. سياسة الإلغاء والاسترداد',
                content: '''إلغاء الطلبات:
• يمكن إلغاء الطلب مجاناً خلال 5 دقائق من التأكيد
• بعد بدء التحضير، قد تُطبق رسوم إلغاء
• في حالة التأخير الشديد، يحق لك الإلغاء مجاناً

الاسترداد:
• في حالة الإلغاء المجاني، سيتم استرداد كامل المبلغ
• مدة الاسترداد تتراوح بين 3-7 أيام عمل
• الاسترداد سيتم بنفس طريقة الدفع الأصلية''',
              ),

              _buildSection(
                title: '6. المسؤوليات والضمانات',
                content: '''نحن نسعى لتقديم أفضل خدمة ممكنة، لكننا لا نضمن:
• توفر جميع الأصناف في كل وقت
• دقة أوقات التوصيل المقدرة
• جودة الطعام (مسؤولية المطعم)
• عدم انقطاع الخدمة

مسؤوليتنا محدودة بقيمة الطلب المحدد.''',
              ),

              _buildSection(
                title: '7. السلوك المقبول',
                content: '''يُمنع استخدام التطبيق لـ:
• أنشطة غير قانونية أو ضارة
• التلاعب بالنظام أو محاولة اختراقه
• إساءة معاملة الموظفين أو الشركاء
• نشر محتوى مسيء أو غير لائق
• إنشاء حسابات وهمية

مخالفة هذه القواعد قد تؤدي إلى إغلاق الحساب.''',
              ),

              _buildSection(
                title: '8. الملكية الفكرية',
                content: '''جميع المحتويات في التطبيق محمية بحقوق الطبع والنشر:
• العلامة التجارية "زاد"
• تصميم التطبيق والواجهات
• النصوص والصور
• البرمجيات والخوارزميات

استخدام أي من هذه المحتويات دون إذن مسبق محظور.''',
              ),

              _buildSection(
                title: '9. تعديل الشروط',
                content: '''نحتفظ بالحق في تعديل هذه الشروط في أي وقت. التعديلات المهمة سيتم الإشعار عنها عبر:
• إشعارات داخل التطبيق
• رسائل البريد الإلكتروني
• رسائل نصية

استمرارك في استخدام التطبيق بعد التعديل يعني موافقتك على الشروط الجديدة.

تاريخ آخر تحديث: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}''',
              ),

              const SizedBox(height: 32),

              // Contact Info
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'للاستفسار أو الشكاوى',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.email_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'legal@zad-app.com',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '+964 770 123 4567',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
