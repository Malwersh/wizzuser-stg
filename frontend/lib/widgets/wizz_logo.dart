import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// ويدجت شعار Wizz قابل لإعادة الاستخدام - تصميم أنيق وبسيط
class WizzLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final bool showShadow;
  final Color? textColor;
  final Color? underlineColor;
  
  const WizzLogo({
    super.key,
    this.size = 140,
    this.showText = true,
    this.showShadow = true,
    this.textColor,
    this.underlineColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // شعار Wizz أنيق ومبسط - بدون مربع أو إطار
        Text(
          'Wizz',
          style: TextStyle(
            fontSize: size * 0.3, // أصغر حجم أنيق
            fontWeight: FontWeight.w600, // وزن متوسط للأناقة
            color: textColor ?? Colors.white,
            fontFamily: 'Roboto', // خط أنيق ونظيف
            letterSpacing: size * 0.02, // تباعد أنيق
            height: 1.0,
            fontStyle: FontStyle.normal,
          ),
        ),
        
        // خط تحتي رفيع وأنيق فقط
        if (showText) ...[
          SizedBox(height: size * 0.02),
          Container(
            width: size * 0.25, // أصغر وأنيق
            height: 1.5, // رفيع جداً
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: (underlineColor ?? AppColors.secondary).withOpacity(0.7),
            ),
          ),
        ],
      ],
    );
  }
}

/// ويدجت شعار Wizz صغير للاستخدام في الـ AppBar أو أماكن أخرى
class WizzLogoMini extends StatelessWidget {
  final double size;
  final Color? backgroundColor;
  final Color? textColor;
  
  const WizzLogoMini({
    super.key,
    this.size = 40,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.2,
        vertical: size * 0.15,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.15),
        color: backgroundColor ?? AppColors.primary,
      ),
      child: Text(
        'Wizz',
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          color: textColor ?? Colors.white,
          fontFamily: 'Poppins',
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// خلفية تدرج Wizz البسيطة للاستخدام في الشاشات المختلفة
class WizzGradientBackground extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;
  
  const WizzGradientBackground({
    super.key,
    required this.child,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors ?? [
            Colors.white,
            Colors.grey[50]!,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// ويدجت شعار Wizz المحسن مع أيقونة - تصميم مسطح وحديث
class WizzLogoEnhanced extends StatelessWidget {
  final double size;
  final bool showIcon;
  final Color? primaryColor;
  final Color? secondaryColor;
  
  const WizzLogoEnhanced({
    super.key,
    this.size = 140,
    this.showIcon = true,
    this.primaryColor,
    this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // أيقونة بسيطة للطعام
        if (showIcon)
          Container(
            margin: EdgeInsets.only(bottom: size * 0.15),
            padding: EdgeInsets.all(size * 0.12),
            decoration: BoxDecoration(
              color: (primaryColor ?? AppColors.primary).withOpacity(0.1),
              borderRadius: BorderRadius.circular(size * 0.15),
            ),
            child: Icon(
              Icons.restaurant_menu,
              size: size * 0.25,
              color: primaryColor ?? AppColors.primary,
            ),
          ),
        
        // النص الرئيسي "Wizz"
        Text(
          'Wizz',
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w800,
            color: primaryColor ?? AppColors.primary,
            fontFamily: 'Poppins',
            letterSpacing: 2,
          ),
        ),
        
        // خط تحت النص
        Container(
          margin: EdgeInsets.only(top: size * 0.08),
          width: size * 0.4,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: secondaryColor ?? AppColors.secondary,
          ),
        ),
      ],
    );
  }
}
