import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/utils/iraqi_phone.dart';
import 'package:foodapp_user/utils/validation_helper.dart';
import 'package:foodapp_user/widgets/iraqi_mobile_field.dart';
import 'package:foodapp_user/widgets/iraqi_phone_input.dart';
import 'package:foodapp_user/screens/language_settings_screen.dart';
import 'package:foodapp_user/screens/country_settings_screen.dart';
import 'package:foodapp_user/services/browsing_location_service.dart';

Widget host(Widget child) => MaterialApp(
  home: Directionality(textDirection: TextDirection.rtl, child: child),
);
void main() {
  test(
    'all entry points agree on Arabic, Persian and international phone forms',
    () {
      for (final raw in [
        '07831367435',
        '7831367435',
        '+9647831367435',
        '009647831367435',
        '+964 (0783) 136-7435',
        '٠٧٨٣١٣٦٧٤٣٥',
        '۰۷۸۳۱۳۶۷۴۳۵',
      ]) {
        expect(IraqiPhone.normalize(raw), '+9647831367435');
        expect(ValidationHelper.isValidIraqiPhone(raw), isTrue);
        expect(
          ValidationHelper.convertToFullPhoneNumber(raw),
          '+9647831367435',
        );
      }
      for (final raw in ['', '+15551234567', '078313674350', '078abc67435']) {
        expect(IraqiPhone.valid(raw), isFalse);
      }
      expect(IraqiPhone.display('+15551234567'), '+15551234567');
      expect(IraqiPhone.display('+9647******35'), '+9647******35');
    },
  );
  testWidgets(
    'fixed prefix survives empty field and full-number paste, no truncation',
    (tester) async {
      final phone = TextEditingController();
      await tester.pumpWidget(
        host(Scaffold(body: IraqiMobileField(controller: phone))),
      );
      expect(find.text('🇮🇶 +964'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '٠٠٩٦٤٧٨٣١٣٦٧٤٣٥');
      expect(phone.text, '+9647831367435');
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '7831367435',
      );
      await tester.enterText(find.byType(TextFormField), '078313674350');
      expect(IraqiPhone.valid(phone.text), isFalse);
      expect(phone.text.length, 11);
      phone.text = '+9647831367435';
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '7831367435',
      );
      await tester.pumpWidget(const SizedBox());
      phone.dispose();
    },
  );
  testWidgets('display never repeats the country code', (tester) async {
    await tester.pumpWidget(
      host(const Scaffold(body: IraqiPhoneDisplay(phoneNumber: '07831367435'))),
    );
    expect(find.text('+9647831367435'), findsOneWidget);
    expect(find.text('🇮🇶 +964'), findsNothing);
  });
  testWidgets('language lists only functioning Arabic with no fake save', (
    tester,
  ) async {
    await tester.pumpWidget(host(const LanguageSettingsScreen()));
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('English'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets(
    'country uses actual delivery-region chooser without fake countries',
    (tester) async {
      var chosen = false;
      final service = BrowsingLocationService(owner: () => 'guest');
      await tester.pumpWidget(
        host(
          CountrySettingsScreen(
            browsingService: service,
            onChooseRegion: () => chosen = true,
          ),
        ),
      );
      expect(find.text('العراق'), findsOneWidget);
      expect(find.text('لم تُحدّد منطقة التوصيل بعد'), findsOneWidget);
      expect(find.text('السعودية'), findsNothing);
      await tester.tap(find.text('منطقة التوصيل'));
      expect(chosen, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );
}
