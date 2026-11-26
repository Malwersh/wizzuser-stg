import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/screens/personal_info_screen.dart';

void main() {
  Widget app(PersonalInfoScreen screen) => MaterialApp(
    home: Directionality(textDirection: TextDirection.rtl, child: screen),
  );
  testWidgets(
    'personal info has one notification destination and never saves implicit consent',
    (t) async {
      Map<String, dynamic>? submitted;
      await t.pumpWidget(
        app(
          PersonalInfoScreen(
            currentOwner: () => 'owner',
            profileLoader:
                (_) async => {
                  'name': 'محمد',
                  'gender': 'male',
                  'marketing_consent': false,
                  'newsletter_subscription': true,
                },
            profileSaver: (owner, fields) async {
              submitted = fields;
              return {'success': true};
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('العروض وإعدادات الإشعارات'), findsOneWidget);
      final save = find.widgetWithText(ElevatedButton, 'حفظ التغييرات');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(submitted?['name'], 'محمد');
      expect(submitted?.containsKey('marketing_consent'), false);
      expect(submitted?.containsKey('newsletter_subscription'), false);
    },
  );
  testWidgets(
    'failed load offers retry without fabricating editable defaults',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        app(
          PersonalInfoScreen(
            currentOwner: () => 'owner',
            profileLoader:
                (_) async =>
                    ++calls == 1 ? null : {'name': 'محمد', 'gender': 'male'},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      await t.tap(find.text('إعادة المحاولة'));
      await t.pumpAndSettle();
      expect(find.text('محمد'), findsOneWidget);
    },
  );
  testWidgets(
    'late response after identity change does not display previous profile',
    (t) async {
      String? owner = 'first';
      final result = Completer<Map<String, dynamic>?>();
      await t.pumpWidget(
        app(
          PersonalInfoScreen(
            currentOwner: () => owner,
            profileLoader: (_) => result.future,
          ),
        ),
      );
      await t.pump();
      owner = 'second';
      result.complete({'name': 'اسم الحساب القديم'});
      await t.pumpAndSettle();
      expect(find.text('اسم الحساب القديم'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    },
  );
}
