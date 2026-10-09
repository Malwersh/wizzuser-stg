// lib/widgets/floating_cart_bar.dart
import '../constants/app_colors.dart';

import 'package:flutter/material.dart';
import 'modern_cart_icon.dart';

class FloatingCartBar extends StatelessWidget {
  final int count;
  final String? label;
  final VoidCallback onTap;
  final bool expanded;

  const FloatingCartBar._({
    required this.count,
    this.label,
    required this.onTap,
    this.expanded = false,
  });

  /// الحالة الممتدّة: أيقونة + اسم المطعم + العدد
  factory FloatingCartBar.expanded({
    required int count,
    required String label,
    required VoidCallback onTap,
  }) {
    return FloatingCartBar._(
      count: count,
      label: label,
      onTap: onTap,
      expanded: true,
    );
  }

  /// الحالة المنكمشة: أيقونة فقط بالـ badge
  factory FloatingCartBar.collapsed({
    required int count,
    required VoidCallback onTap,
  }) {
    return FloatingCartBar._(
      count: count,
      onTap: onTap,
      expanded: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(28),
      color: expanded ? AppColors.primary : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 20 : 12,
            vertical: expanded ? 14 : 12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (expanded) ...[
                const ModernCartIcon(
                  color: Colors.white,
                  size: 20,
                  isGlassmorphic: false,
                ),
                const SizedBox(width: 12),
                Text(
                  label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                const ModernCartIcon(
                  color: AppColors.primary,
                  size: 20,
                  isGlassmorphic: true,
                ),
              ],
              // العدد داخل دائرة
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: expanded ? Colors.white : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: expanded ? AppColors.primary : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
