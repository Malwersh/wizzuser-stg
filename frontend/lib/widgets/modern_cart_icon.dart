// lib/widgets/modern_cart_icon.dart
import '../constants/app_colors.dart';

import 'package:flutter/material.dart';
import 'dart:ui';

class ModernCartIcon extends StatelessWidget {
  final Color color;
  final double size;
  final bool hasGlowEffect;
  final VoidCallback? onPressed;
  final int? badgeCount;
  final bool isGlassmorphic;

  const ModernCartIcon({
    super.key,
    this.color = Colors.white,
    this.size = 24,
    this.hasGlowEffect = false,
    this.onPressed,
    this.badgeCount,
    this.isGlassmorphic = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Container(
      width: size + 8,
      height: size + 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isGlassmorphic ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.1),
        border: isGlassmorphic ? Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ) : null,
        boxShadow: hasGlowEffect ? [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, -2),
          ),
        ] : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: isGlassmorphic ? ImageFilter.blur(sigmaX: 10, sigmaY: 10) : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Container(
            decoration: BoxDecoration(
              color: isGlassmorphic ? Colors.white.withValues(alpha: 0.1) : null,
            ),
            child: Center(
              child: Icon(
                Icons.shopping_bag_rounded,
                size: size,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );

    // إضافة Badge إذا كان مطلوب
    if (badgeCount != null && badgeCount! > 0) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          badgeCount! > 99 ? '99+' : '$badgeCount',
          style: const TextStyle(
            color: AppColors.textOnPrimary, // أسود على خلفية ذهبية
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
              ),
            ),
          ),
        ],
      );
    }

    // إضافة GestureDetector إذا كان مطلوب
    if (onPressed != null) {
      return GestureDetector(
        onTap: onPressed,
        child: iconWidget,
      );
    }

    return iconWidget;
  }
}

// Widget للأيقونة الدائرية بتصميم زجاجي
class ModernCartCircleIcon extends StatelessWidget {
  final Color backgroundColor;
  final Color iconColor;
  final double size;
  final VoidCallback? onPressed;
  final int? badgeCount;

  const ModernCartCircleIcon({
    super.key,
    this.backgroundColor = AppColors.primary,
    this.iconColor = Colors.white,
    this.size = 56,
    this.onPressed,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor, // لون صافي بدون تدرج
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
            ),
            child: Center(
              child: Icon(
                Icons.shopping_bag_outlined,
                size: size * 0.5,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );

    // إضافة Badge إذا كان مطلوب
    if (badgeCount != null && badgeCount! > 0) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: size * 0.05,
            top: size * 0.05,
            child: Container(
              width: size * 0.35,
              height: size * 0.35,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary, // لون صافي بدون تدرج
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                badgeCount! > 99 ? '99+' : '$badgeCount',
                style: TextStyle(
                  color: AppColors.textOnPrimary, // أسود على خلفية ذهبية
                  fontSize: size * 0.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // إضافة GestureDetector إذا كان مطلوب
    if (onPressed != null) {
      return GestureDetector(
        onTap: onPressed,
        child: iconWidget,
      );
    }

    return iconWidget;
  }
}
