// lib/screens/privacy_policy_screen.dart

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'سياسة الخصوصية',
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
            icon: const Icon(Icons.arrow_forward, color: Colors.white), // إصلاح أيقونة RTL
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
                        Icons.privacy_tip_outlined,
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
                            'سياسة الخصوصية',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'نلتزم بحماية خصوصيتك وبياناتك الشخصية',
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
                title: '1. جمع المعلومات',
                content: '''نحن نجمع المعلومات التي تقدمها لنا بشكل مباشر عند:
• إنشاء حساب جديد
• تقديم طلب توصيل
• التواصل مع خدمة العملاء
• استخدام التطبيق

تشمل هذه المعلومات:
• الاسم الكامل
• رقم الهاتف
• البريد الإلكتروني (اختياري)
• عناوين التوصيل
• تفضيلات الطعام''',
              ),

              _buildSection(
                title: '2. استخدام المعلومات',
                content: '''نستخدم المعلومات التي نجمعها لـ:
• تقديم خدمات التوصيل
• تحسين تجربة المستخدم
• إرسال التحديثات والعروض
• ضمان أمان المنصة
• التواصل معك حول طلباتك''',
              ),

              _buildSection(
                title: '3. مشاركة المعلومات',
                content: '''لا نشارك معلوماتك الشخصية مع أطراف ثالثة إلا في الحالات التالية:
• مع شركاء التوصيل لإتمام الطلبات
• مع المطاعم المشاركة لتحضير الطلبات
• عند الحاجة للامتثال للقوانين
• لحماية حقوقنا أو حقوق المستخدمين''',
              ),

              _buildSection(
                title: '4. حماية البيانات',
                content: '''نحن نتخذ إجراءات أمنية متقدمة لحماية بياناتك:
• تشفير جميع البيانات الحساسة
• استخدام خوادم آمنة
• مراقبة الوصول للبيانات
• تحديث أنظمة الأمان بانتظام''',
              ),

              _buildSection(
                title: '5. حقوقك',
                content: '''لك الحق في:
• الوصول إلى بياناتك الشخصية
• طلب تعديل البيانات غير الصحيحة
• حذف حسابك وبياناتك
• إيقاف تلقي الرسائل التسويقية
• تقديم شكوى حول كيفية معالجة بياناتك''',
              ),

              _buildSection(
                title: '6. ملفات تعريف الارتباط (Cookies)',
                content: '''نستخدم ملفات تعريف الارتباط لـ:
• تحسين أداء التطبيق
• تذكر تفضيلاتك
• تحليل استخدام التطبيق
• تخصيص المحتوى المعروض''',
              ),

              _buildSection(
                title: '7. تحديث السياسة',
                content: '''قد نقوم بتحديث هذه السياسة من وقت لآخر. سنقوم بإشعارك بأي تغييرات مهمة عبر:
• إشعارات داخل التطبيق
• رسائل البريد الإلكتروني
• رسائل نصية

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
                      'للتواصل معنا',
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
                          'support@zad-app.com',
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
