import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/checkout_review_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4);
  Map<String, dynamic> invoice() => {
    'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
    'customerTotal': {'minorAmount': 14000000, 'currency': 'IQD'},
    'discount': {'minorAmount': 500000},
    'quoteId': 'quote-a',
  };
  test(
    'confirm unchanged displayed server invoice; key order does not change meaning',
    () {
      final p = invoice();
      expect(
        canConfirmDisplayedInvoice(
          displayed: p,
          proposed: {for (final k in p.keys.toList().reversed) k: p[k]},
          sameScope: true,
          now: now,
        ),
        true,
      );
    },
  );
  test('price changes and new quote require explicit review', () {
    final displayed = invoice();
    for (final p in [
      invoice()
        ..['customerTotal'] = {'minorAmount': 15000000, 'currency': 'IQD'},
      invoice()..['quoteId'] = 'quote-b',
    ]) {
      expect(
        canConfirmDisplayedInvoice(
          displayed: displayed,
          proposed: p,
          sameScope: true,
          now: now,
        ),
        false,
      );
    }
  });
  test(
    'changed customer selection, missing preview and expired invoice cannot skip review',
    () {
      expect(
        canConfirmDisplayedInvoice(
          displayed: invoice(),
          proposed: invoice(),
          sameScope: false,
          now: now,
        ),
        false,
      );
      expect(
        canConfirmDisplayedInvoice(
          displayed: null,
          proposed: invoice(),
          sameScope: true,
          now: now,
        ),
        false,
      );
      expect(
        canConfirmDisplayedInvoice(
          displayed: invoice(),
          proposed: invoice(),
          sameScope: true,
          now: now.add(const Duration(minutes: 3)),
        ),
        false,
      );
    },
  );
}
