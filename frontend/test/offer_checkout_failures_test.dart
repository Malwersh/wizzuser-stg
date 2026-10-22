import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/offer_checkout_failures.dart';

void main() {
  test('only explicit precommit offer failures release an attempt', () {
    for (final code in rejectedOfferCodes) {
      expect(isDefinitiveOfferRejection(code, 409), true);
      for (final status in [200, 302, 500, 503]) {
        expect(isDefinitiveOfferRejection(code, status), false);
      }
    }
    for (final code in [null, 'OFFER_HISTORY_UNAVAILABLE', 'OFFER_ACCOUNT_REQUIRED', 'UNKNOWN']) {
      expect(isDefinitiveOfferRejection(code, 409), false);
    }
  });
}
