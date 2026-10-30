import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('campaign GIF decodes consecutive animation frames in Flutter', () async {
    final bytes = await File('test/fixtures/animated_campaign.gif').readAsBytes();
    // Image.network in the offer sheet uses Flutter's multi-frame image codec.
    final codec = await ui.instantiateImageCodec(bytes);
    expect(codec.frameCount, 2);
    final first = await codec.getNextFrame();
    final second = await codec.getNextFrame();
    expect(first.duration.inMilliseconds, 100);
    expect(second.duration.inMilliseconds, 100);
    final firstPixels = await first.image.toByteData();
    final secondPixels = await second.image.toByteData();
    expect(firstPixels!.getUint8(0), isNot(secondPixels!.getUint8(0)));
    first.image.dispose();
    second.image.dispose();
    codec.dispose();
  });
}
