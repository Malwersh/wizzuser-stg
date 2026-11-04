import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/discovery/restaurant_feed_tile.dart';

void main() {
  testWidgets(
    'full-width restaurant photo preserves RTL hierarchy and separate favorite action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0, saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: RestaurantFeedTile(
                name: 'فروج المدينة',
                photo: const ColoredBox(
                  key: ValueKey('photo'),
                  color: Colors.grey,
                ),
                favorite: IconButton(
                  onPressed: () => saved++,
                  icon: const Icon(Icons.favorite_border),
                ),
                metadata: const Text('— · ٢٢–٢٧ دقيقة'),
                delivery: const Text('التوصيل ١٥٠٠ د.ع'),
                onTap: () => opened++,
              ),
            ),
          ),
        ),
      );
      final photo = tester.getSize(find.byKey(const ValueKey('photo')));
      expect(photo.width, 280);
      expect(photo.width / photo.height, closeTo(1.55, 0.01));
      expect(
        tester.getTopLeft(find.text('فروج المدينة')).dy,
        greaterThan(photo.height),
      );
      await tester.tap(find.byIcon(Icons.favorite_border));
      expect(saved, 1);
      expect(opened, 0);
      await tester.tap(find.text('فروج المدينة'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
