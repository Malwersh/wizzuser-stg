import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/home_promotion.dart';
import 'package:foodapp_user/models/home_slide.dart';
import 'package:foodapp_user/widgets/discovery/home_discovery_scroll.dart';

void main() {
  HomePromotion offer(String id, String source, String merchant) =>
      HomePromotion.offer(
        HomeSlide(
          id: id,
          title: id,
          imageUrl: '',
          imageVersion: '',
          actionType: 'campaign',
          targetId: id,
          offerSource: source,
          endAt: DateTime(2090),
          scene:
              source == 'merchant'
                  ? {
                    'id': merchant,
                    'name': merchant,
                    'logoUrl': '',
                    'products': [
                      {
                        'id': 'p',
                        'name': 'Pizza',
                        'imageUrl': 'https://example.com/p.jpg',
                      },
                    ],
                  }
                  : null,
        ),
      );
  test(
    'scenes group platform first then restaurant; custom text and pause do not invent offers',
    () {
      final settings = HomePromotionSettings.fromJson({
        'enabled': true,
        'subtitle': 'مناسبة خاصة',
        'scenes': [
          {
            'id': 'f',
            'enabled': true,
            'title': 'مطعم فتوش',
            'subtitle': 'الكثير من العروض',
          },
          {'id': 'empty', 'enabled': true, 'title': 'must not appear'},
        ],
      });
      final scenes = HomePromotionScene.build([
        offer('m1', 'merchant', 'f'),
        offer('m2', 'merchant', 'f'),
        offer('p', 'platform', ''),
      ], settings);
      expect(scenes.map((s) => s.id), ['platform', 'f']);
      expect(scenes[0].subtitle, 'مناسبة خاصة');
      expect(scenes[1].title, 'مطعم فتوش');
      expect(scenes[1].offers.length, 2);
      expect(scenes[1].products.length, 1);
      final paused = HomePromotionSettings.fromJson({
        'scenes': [
          {'id': 'f', 'enabled': false},
        ],
      });
      expect(
        HomePromotionScene.build([offer('m', 'merchant', 'f')], paused),
        isEmpty,
      );
    },
  );
  for (final width in [320.0, 390.0])
    testWidgets('address and filters stay while ad scrolls $width', (t) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final controller = ScrollController();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeDiscoveryScroll(
              controller: controller,
              promotionBackground: const Color(0xFF00296B),
              headerBuilder: (visible) => SizedBox(
                key: const Key('address'),
                height: 80,
                child: Text(visible ? 'advertisement header' : 'white header'),
              ),
              header: const SizedBox(
                key: Key('address'),
                height: 80,
                child: Text('العنوان والإشعارات'),
              ),
              filters: const SizedBox(
                key: Key('filters'),
                height: 48,
                child: Text('عروض • مفتوح الآن'),
              ),
              promotion: const SizedBox(
                key: Key('ad'),
                height: 128,
                child: Text('الإعلان'),
              ),
              content: const SizedBox(height: 1600),
            ),
          ),
        ),
      );
      expect(find.text('advertisement header'), findsOneWidget);
      controller.jumpTo(-40);
      await t.pump();
      final fill = find.byKey(const Key('promotion-overscroll-background'));
      expect(fill, findsOneWidget);
      expect(t.widget<ColoredBox>(fill).color, const Color(0xFF00296B));
      controller.jumpTo(0);
      await t.pumpAndSettle();
      final address = t.getTopLeft(find.byKey(const Key('address'))).dy;
      controller.jumpTo(350);
      await t.pump();
      expect(t.getTopLeft(find.byKey(const Key('address'))).dy, address);
      expect(t.getTopLeft(find.byKey(const Key('filters'))).dy, address + 80);
      expect(find.byKey(const Key('ad')), findsNothing);
      expect(find.text('white header'), findsOneWidget);
      controller.jumpTo(0);
      await t.pumpAndSettle();
      expect(find.text('advertisement header'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      controller.dispose();
    });
}
