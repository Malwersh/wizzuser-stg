import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/offer_replacement_sheet.dart';

void main() {
  for (final accept in [false, true]) {
    testWidgets(
      'comparison requires explicit ${accept ? 'replacement' : 'keep'} choice',
      (t) async {
        bool? result;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (c) => TextButton(
                      onPressed: () async {
                        result = await confirmOfferReplacement(
                          c,
                          title: 'عرض',
                          currentTotalMinor: 13500000,
                          replacementTotalMinor: 14000000,
                        );
                      },
                      child: const Text('open'),
                    ),
              ),
            ),
          ),
        );
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(
          find.text('الإجمالي سيزيد عند اختيار هذا العرض.'),
          findsOneWidget,
        );
        expect(result, isNull);
        await t.tap(
          find.text(accept ? 'استبدال العرض' : 'الاحتفاظ بخصم التوصيل'),
        );
        await t.pumpAndSettle();
        expect(result, accept);
      },
    );
  }
}
