import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/readable_colors.dart';

void main() {
  test('foreground remains readable on brand fills and translucent surfaces', () {
    for (final background in <Color?>[const Color(0xFF00296B), const Color(0xFF00509D), const Color(0xFFFDC500), const Color(0xFFEDF2FA), Colors.white, Colors.black, Colors.red, Colors.green, const Color(0x3300296B), null]) {
      final fill = Color.alphaBlend(background ?? Colors.white, Colors.white);
      final foreground = readableForeground(background);
      final a = foreground.computeLuminance(), b = fill.computeLuminance();
      final contrast = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: '$background');
    }
  });
}
