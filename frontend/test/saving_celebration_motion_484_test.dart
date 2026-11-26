import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/saving_celebration_motion.dart';

void main() {
  Widget app(
    String id, {
    ScrollController? scroll,
    bool reduce = false,
    double before = 0,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 750),
        disableAnimations: reduce,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              SizedBox(height: before),
              SavingCelebrationMotion(
                celebrationKey: id,
                child: const SizedBox(
                  width: 350,
                  height: 160,
                  child: Text('وفّرت 500 د.ع'),
                ),
              ),
              const SizedBox(height: 250),
            ],
          ),
        ),
      ),
    ),
  );
  double progress(WidgetTester t) =>
      (t
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('saving-confetti')),
                  )
                  .painter!
              as SavingConfettiPainter)
          .progress;
  testWidgets('visible card spreads animated ribbons and stops once', (
    t,
  ) async {
    await t.pumpWidget(app('visible-484'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(progress(t), greaterThan(0));
    expect(progress(t), lessThan(1));
    await t.pumpAndSettle();
    expect(progress(t), 1);
    await t.pumpWidget(app('visible-484'));
    await t.pump(const Duration(milliseconds: 100));
    expect(progress(t), 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('animation waits until scrolling card into view', (t) async {
    final scroll = ScrollController();
    await t.pumpWidget(app('scrolled-484', scroll: scroll, before: 900));
    await t.pump(const Duration(seconds: 1));
    expect(progress(t), 0);
    scroll.jumpTo(650);
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(progress(t), greaterThan(0));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'reduce motion keeps confirmed saving readable without confetti',
    (t) async {
      await t.pumpWidget(app('reduced-484', reduce: true));
      await t.pumpAndSettle();
      expect(progress(t), 0);
      expect(find.text('وفّرت 500 د.ع'), findsOneWidget);
    },
  );
}
