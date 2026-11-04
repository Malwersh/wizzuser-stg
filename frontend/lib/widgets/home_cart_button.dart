import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class HomeCartButton extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  const HomeCartButton({super.key, required this.count, required this.onTap});
  @override
  State<HomeCartButton> createState() => _HomeCartButtonState();
}

class _HomeCartButtonState extends State<HomeCartButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  Timer? _timer;
  bool _foreground = true;
  int get count => widget.count;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 55,
      ),
    ]).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronize();
  }

  @override
  void didUpdateWidget(covariant HomeCartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != count) _synchronize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _synchronize();
  }

  void _synchronize() {
    _timer?.cancel();
    if (count <= 0 ||
        !_foreground ||
        !TickerMode.of(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      _controller.reset();
      return;
    }
    _controller.forward(from: 0);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return ScaleTransition(
      scale: _scale,
      child: Semantics(
        button: true,
        label: 'فتح السلة، $count قطعة',
        child: Tooltip(
          message: 'فتح السلة',
          child: SizedBox(
            width: 56,
            height: 56,
            child: Material(
              color: AppColors.secondaryDark,
              elevation: 5,
              shadowColor: const Color(0x3300296B),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: Center(
                  child: Badge(
                    backgroundColor: Colors.white,
                    textColor: AppColors.secondaryDark,
                    label: Text(count > 99 ? '99+' : '$count'),
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
