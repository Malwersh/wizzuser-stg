import 'package:flutter/material.dart';

/// Choose a readable foreground after compositing a translucent fill on its surface.
Color readableForeground(Color? background, {Color surface = Colors.white}) {
  final fill = Color.alphaBlend(background ?? surface, surface);
  const navy = Color(0xFF00296B);
  double ratio(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
  }

  if (ratio(navy, fill) >= 4.5) return navy;
  if (ratio(Colors.white, fill) >= 4.5) return Colors.white;
  return Colors.black;
}
