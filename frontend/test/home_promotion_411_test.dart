import 'package:flutter/material.dart';
import 'package:foodapp_user/widgets/discovery/promotion_appearance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/home_promotion.dart';
import 'package:foodapp_user/models/home_slide.dart';
import 'package:foodapp_user/widgets/discovery/home_promotion_header.dart';
import 'package:foodapp_user/widgets/discovery/home_discovery_header.dart';

void main() {
  test('item backgrounds follow campaign colour and explicit override', () {
    const navy = Color(0xff00296b), gold = Color(0xfffdc500);
    expect(promotionItemBackground(navy).computeLuminance(), greaterThan(navy.computeLuminance()));
    expect(promotionItemBackground(gold).computeLuminance(), lessThan(gold.computeLuminance()));
    expect(promotionItemBackground(gold, override: '#4D6997'), const Color(0xff4d6997));
    expect(promotionItemBackground(navy, override: 'invalid'), promotionItemBackground(navy));
    expect(HomePromotionSettings.fromJson({'itemBackgroundColor': '#4D6997'}).itemBackgroundColor, '#4D6997');
  });

  test('selection accepts only configured source and identity', () {
    final s = HomePromotionSettings.fromJson({
      'enabled': true,
      'source': 'merchant',
      'selection': {'source': 'merchant', 'id': 'one'},
    });
    expect(s.accepts('merchant', 'one'), true);
    expect(s.accepts('platform', 'one'), false);
    expect(s.accepts('merchant', 'two'), false);
    expect(HomePromotionSettings.fromJson({}).active(DateTime.now()), false);
  });
  for (final width in [320.0, 390.0])
    for (final scale in [1.0, 2.0])
      testWidgets('rail layout and motion $width/$scale', (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var tapped = false;
        final item = HomePromotion.offer(
          HomeSlide(
            id: 'one',
            title: 'خصم على الوجبات المشمولة بالعرض',
            imageUrl: '',
            imageVersion: '1',
            actionType: 'campaign',
            targetId: 'one',
            endAt: DateTime(2090),
            offerSource: 'merchant',
          ),
        );
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1000),
                textScaler: TextScaler.linear(scale),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: HomeDiscoveryHeader(
                    address: 'مركز المناذرة',
                    unread: false,
                    onAddress: () {},
                    onNotifications: () {},
                    onAccount: () {},
                    onCart: () {},
                    background: const Color(0xff00296b),
                    promotion: HomePromotionRail(
                      items: [item],
                      title: 'مزايا ويز',
                      background: const Color(0xff00296b),
                      interval: 5,
                      onTap: () => tapped = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
        // Surrounding items have disappeared during the pulse, before copy opens.
        expect(
          t
              .widget<Opacity>(find.byKey(const ValueKey('promotion-side-1')))
              .opacity,
          0,
        );
        expect(
          t
              .widget<Opacity>(find.byKey(const ValueKey('promotion-copy')))
              .opacity,
          0,
        );
        final brandScale =
            t
                .widget<Transform>(
                  find.byKey(const ValueKey('promotion-brand-scale')),
                )
                .transform
                .getMaxScaleOnAxis();
        expect(brandScale, greaterThan(1));
        expect(brandScale, lessThanOrEqualTo(1.25));
        await t.pump(const Duration(seconds: 4));
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
        await t.tap(find.byType(HomePromotionRail));
        expect(tapped, true);
        await t.pumpWidget(const SizedBox());
      });
}
