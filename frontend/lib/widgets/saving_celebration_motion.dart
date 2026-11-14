import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// A single visible celebration. Scroll/lifecycle events trigger visibility
/// checks; no timer or network polling is involved.
class SavingCelebrationMotion extends StatefulWidget {
  final String celebrationKey;
  final Widget child;
  const SavingCelebrationMotion({
    super.key,
    required this.celebrationKey,
    required this.child,
  });
  @override
  State<SavingCelebrationMotion> createState() =>
      _SavingCelebrationMotionState();
}

class _SavingCelebrationMotionState extends State<SavingCelebrationMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static final _seen = <String>{};
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  ScrollPosition? _scroll;
  bool _queued = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (_scroll != position) {
      _scroll?.removeListener(_queue);
      _scroll = position;
      _scroll?.addListener(_queue);
    }
    _queue();
  }

  @override
  void didUpdateWidget(covariant SavingCelebrationMotion old) {
    super.didUpdateWidget(old);
    if (old.celebrationKey != widget.celebrationKey) _motion.reset();
    _queue();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _queue();
  }

  void _queue() {
    if (_queued || !mounted) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted ||
          _seen.contains(widget.celebrationKey) ||
          ModalRoute.of(context)?.isCurrent == false ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused)
        return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final media = MediaQuery.of(context);
      final visible =
          math.min(
            top + box.size.height,
            media.size.height - media.padding.bottom - 90,
          ) -
          math.max(top, media.padding.top);
      if (visible < math.min(box.size.height * .6, 100)) return;
      if (_seen.length >= 40) _seen.remove(_seen.first);
      _seen.add(widget.celebrationKey);
      if (!media.disableAnimations) _motion.forward(from: 0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll?.removeListener(_queue);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.center,
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _motion,
              builder:
                  (_, __) => CustomPaint(
                    key: const ValueKey('saving-confetti'),
                    painter: SavingConfettiPainter(_motion.value),
                  ),
            ),
          ),
        ),
      ),
    ],
  );
}

class SavingConfettiPainter extends CustomPainter {
  final double progress;
  SavingConfettiPainter(this.progress);
  static const _colors = [
    AppColors.primary,
    Color(0xffef5e68),
    Color(0xff28bfae),
    AppColors.secondaryDark,
    Color(0xff5cbe75),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    // Staggered bursts, larger visible pieces, and a slow fade at the end.
    for (var i = 0; i < 34; i++) {
      final delay = (i % 4) * .055;
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final direction = i.isEven ? -1.0 : 1.0;
      final spread = .12 + (i % 9) * .044;
      final x =
          size.width * .5 +
          direction * size.width * spread * Curves.easeOut.transform(t);
      final y =
          size.height * .28 -
          (32 + i % 6 * 12) * math.sin(math.pi * t) +
          (50 + i % 5 * 11) * t * t;
      final opacity = t < .72 ? 1.0 : (1 - t) / .28;
      final paint =
          Paint()
            ..color = _colors[i % _colors.length].withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(direction * (t * 5 + i));
      if (i % 3 == 0) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.3
          ..strokeCap = StrokeCap.round;
        final ribbon =
            Path()
              ..moveTo(-4, -14)
              ..cubicTo(9, -10, -9, -3, 3, 2)
              ..cubicTo(12, 6, -7, 10, 3, 17);
        canvas.drawPath(ribbon, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: i % 2 == 0 ? 5 : 7,
              height: i % 2 == 0 ? 10 : 5,
            ),
            const Radius.circular(1),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SavingConfettiPainter old) => old.progress != progress;
}
