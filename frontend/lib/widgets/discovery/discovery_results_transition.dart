import 'package:flutter/material.dart';

/// Only the incoming results animate; old results cannot remain tappable.
class DiscoveryResultsTransition extends StatelessWidget {
  final String selection;
  final Widget child;
  const DiscoveryResultsTransition({
    super.key,
    required this.selection,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(selection),
    tween: Tween(begin: 0, end: 1),
    duration:
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    child: child,
    builder:
        (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 5 * (1 - value)),
            child: child,
          ),
        ),
  );
}
