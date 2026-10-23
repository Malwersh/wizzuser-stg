// lib/widgets/clear_cart_sheet.dart

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// 🔥 نافذة تعارض السلة (مطعم مختلف) — نموذج "سلة مطعم واحد"
/// تعرض اسم المطعم صاحب العناصر الحالية وتتيح:
/// [الاحتفاظ بالسلة] أو [مسح وإضافة العنصر]
/// تعيد true إذا اختار المستخدم "مسح وإضافة"، وfalse إذا اختار الاحتفاظ.
Future<bool?> showClearCartConflictSheet(
  BuildContext context, {
  required String otherStoreName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // أيقونة السلة
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: AppColors.secondaryDark,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'بدء سلة جديدة؟',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'سلتك تحتوي على عناصر من '),
                    TextSpan(
                      text: otherStoreName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                    const TextSpan(text: '. يمكنك الطلب من مطعم واحد فقط في كل مرة.'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // زر مسح وإضافة (أساسي)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text(
                    'مسح وإضافة العنصر',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // زر الاحتفاظ بالسلة
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.secondary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(sheetContext, false);
                  },
                  child: const Text(
                    'الاحتفاظ بالسلة',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
