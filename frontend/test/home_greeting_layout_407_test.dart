import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/discovery/home_discovery_header.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.8, 2.0]) {
      for (final greeting in [null, 'أهلًا Mohammed، تشعر بالجوع؟']) {
        testWidgets('greeting fits $width/$scale/${greeting != null}', (
          t,
        ) async {
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: HomeDiscoveryHeader(
                      address: 'مركز المناذرة',
                      greeting: greeting,
                      onAddress: () {},
                      onAccount: () {},
                      onCart: () {},
                      onNotifications: () {},
                      unread: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(t.takeException(), isNull);
          if (greeting != null)
            expect(t.widget<Text>(find.text(greeting)).style?.fontSize, 18);
        });
      }
    }
  }
}
