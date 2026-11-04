import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class EmptyBasketView extends StatelessWidget {
  final VoidCallback onBrowse;
  const EmptyBasketView({super.key, required this.onBrowse});
  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  'سلة التسوق',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryDark,
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder:
                    (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 24,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 156,
                                height: 156,
                                child: CustomPaint(
                                  painter: _BasketIllustration(),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'سلتك فارغة الآن',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.secondaryDark,
                                ),
                              ),
                              const SizedBox(height: 9),
                              const Text(
                                'أضف ما يعجبك، وستجد اختياراتك هنا',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF687384),
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: onBrowse,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.secondaryDark,
                                  elevation: 3,
                                  shadowColor: const Color(0x2600296B),
                                  minimumSize: const Size(170, 46),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                child: const Text(
                                  'متابعة التصفح',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Small vector illustration in the Wizz palette; no third-party brand artwork.
class _BasketIllustration extends CustomPainter {
  const _BasketIllustration();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 156, size.height / 156);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawOval(
      const Rect.fromLTWH(26, 142, 105, 7),
      paint..color = const Color(0xFFF0F2F6),
    );
    // Bread, bottle and produce peek out of the basket.
    canvas.save();
    canvas.translate(43, 68);
    canvas.rotate(-.25);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-13, -38, 26, 59),
        const Radius.circular(13),
      ),
      paint..color = const Color(0xFFE4AF56),
    );
    paint
      ..color = const Color(0xFFF8DA9D)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (double y = -27; y < 0; y += 12) {
      canvas.drawLine(Offset(-6, y), Offset(4, y - 4), paint);
    }
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(69, 35, 26, 54),
        const Radius.circular(8),
      ),
      paint..color = const Color(0xFFDFEAF4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(74, 25, 16, 14),
        const Radius.circular(3),
      ),
      paint..color = AppColors.secondaryDark,
    );
    canvas.drawOval(
      const Rect.fromLTWH(104, 34, 16, 30),
      paint..color = const Color(0xFF73A88B),
    );
    canvas.drawOval(
      const Rect.fromLTWH(116, 40, 17, 28),
      paint..color = const Color(0xFF447E67),
    );
    canvas.drawOval(
      const Rect.fromLTWH(98, 58, 35, 35),
      paint..color = const Color(0xFFDB795E),
    );
    final basket =
        Path()
          ..moveTo(22, 80)
          ..lineTo(134, 80)
          ..lineTo(124, 132)
          ..quadraticBezierTo(122, 141, 112, 141)
          ..lineTo(44, 141)
          ..quadraticBezierTo(34, 141, 32, 132)
          ..close();
    canvas.drawPath(basket, paint..color = AppColors.primary);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(16, 74, 124, 14),
        const Radius.circular(6),
      ),
      paint..color = AppColors.secondaryDark,
    );
    paint
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (double x = 54; x <= 102; x += 24) {
      canvas.drawLine(Offset(x, 103), Offset(x, 123), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BasketIllustration oldDelegate) => false;
}
