import 'package:flutter/material.dart';

Color promotionForeground(Color background) {
  const navy = Color(0xff00296b);
  final luminance = background.computeLuminance();
  final whiteContrast = 1.05 / (luminance + .05);
  final navyContrast = (luminance + .05) / (navy.computeLuminance() + .05);
  return whiteContrast >= navyContrast ? Colors.white : navy;
}

/// A contrasting tone of the chosen campaign colour, without changing its hue.
Color promotionItemBackground(Color background, {String? override}) {
  if (override != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(override)) {
    return Color(0xff000000 | int.parse(override.substring(1), radix: 16));
  }
  return Color.lerp(
    background,
    background.computeLuminance() > .45 ? Colors.black : Colors.white,
    background.computeLuminance() > .45 ? .12 : .22,
  )!;
}
