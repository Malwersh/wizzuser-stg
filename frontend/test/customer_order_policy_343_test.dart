import 'package:foodapp_user/services/delivery_quote_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/customer_order_policy.dart';
import 'package:foodapp_user/screens/terms_conditions_screen.dart';
import 'package:foodapp_user/screens/customer_order_policy_screen.dart';

void main() {
  test(
    'policy validates digest across map key order; rejects substituted text',
    () {
      final p = CustomerOrderPolicy.current;
      expect(
        p.digest,
        '69033a3a53645485bf9de66ed024f4e8924ed52b3ae66d40a09fcb380c41e2e6',
      );
      final server = {...p.document, 'digest': p.digest};
      expect(CustomerOrderPolicy.parse(server).pin, p.pin);
      final changed = {...server, 'title': 'altered'};
      expect(() => CustomerOrderPolicy.parse(changed), throwsFormatException);
    },
  );
  test(
    'a policy change forces review again even when all amounts remain the same',
    () {
      final a = {
        'customerTotal': {'minorAmount': 1000},
        'customerPolicy': {'digest': 'old'},
      };
      expect(
        sameCommercialReview(a, {
          'customerTotal': {'minorAmount': 1000},
          'customerPolicy': {'digest': 'new'},
        }),
        false,
      );
      expect(
        sameCommercialReview(a, {
          'customerTotal': {'minorAmount': 1000},
          'customerPolicy': {'digest': 'old'},
        }),
        true,
      );
      expect(
        sameCommercialReview(a, {
          'customerTotal': {'minorAmount': 1000},
        }),
        false,
      );
    },
  );
  testWidgets(
    'cash policy is readable at large text size and terms have no invented contact details',
    (t) async {
      await t.binding.setSurfaceSize(const Size(375, 760));
      addTearDown(() => t.binding.setSurfaceSize(null));
      for (final screen in [
        const TermsConditionsScreen(),
        const CustomerOrderPolicyScreen(),
      ]) {
        await t.pumpWidget(
          MaterialApp(
            builder:
                (c, w) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(1.7)),
                  child: w!,
                ),
            home: screen,
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('legal@zad-app.com'), findsNothing);
        expect(find.text('+964 770 123 4567'), findsNothing);
      }
    },
  );
}
