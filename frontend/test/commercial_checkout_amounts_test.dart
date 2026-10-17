import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/delivery_quote_checkout.dart';

void main() {
  Map<String, dynamic> money(int amount) => {
    'currency': 'IQD',
    'scale': 1000,
    'moneySchemaVersion': 1,
    'minorAmount': amount,
  };
  Map<String, dynamic> preview() => {
    'goodsGross': money(3499000),
    'discount': money(1000000),
    'serviceFee': money(500000),
    'deliveryFee': money(2750000),
    'driverTip': money(750000),
    'customerTotal': money(6499000),
  };
  test(
    'consent validates service fee and tip once against the server quote',
    () {
      validateCommercialCheckoutAmounts(preview(), 2750000);
    },
  );
  test(
    'double tip, different delivery price and excess discount are rejected',
    () {
      for (final patch in [
        {'customerTotal': money(7249000)},
        {'deliveryFee': money(3000000)},
        {'discount': money(3500000)},
      ]) {
        expect(
          () => validateCommercialCheckoutAmounts({
            ...preview(),
            ...patch,
          }, 2750000),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'untrusted currency, fractional wallet money and unsafe integers fail',
    () {
      for (final amount in [
        money(500001),
        money(9007199254740992),
        {...money(500000), 'currency': 'SAR'},
      ]) {
        expect(
          () => validateCommercialCheckoutAmounts({
            ...preview(),
            'serviceFee': amount,
          }, 2750000),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'existing zero tip preview stays compatible without an implicit fee',
    () {
      final p = preview()..remove('driverTip');
      p['customerTotal'] = money(5749000);
      validateCommercialCheckoutAmounts(p, 2750000);
    },
  );
}
