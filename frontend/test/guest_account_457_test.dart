import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/account_overview.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'guest account fits enlarged Arabic and preserves navigation $width',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var destination = '';
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: GuestAccountOverview(
                        onLogin: () => destination = 'login',
                        onRegister: () => destination = 'register',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final action in [
          ('تسجيل الدخول', 'login'),
          ('جديد في ويز؟ إنشاء حساب', 'register'),
        ]) {
          await t.ensureVisible(find.text(action.$1));
          await t.tap(find.text(action.$1));
          expect(destination, action.$2);
        }
        for (final label in ['المفضلة', 'المحفظة', 'الطلبات']) {
          expect(find.text(label), findsNothing);
        }
        expect(find.text('مستخدم ضيف'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}
