import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/customer_phone_auth_service.dart';

void main() {
  test('Iraqi local and international formats resolve to one identity', () {
    for (final p in [
      '07831367435',
      '7831367435',
      '+9647831367435',
      '009647831367435',
      '9647831367435',
      '٠٧٨٣١٣٦٧٤٣٥',
      '۰۷۸۳۱۳۶۷۴۳۵',
    ]) {
      expect(CustomerPhoneAuthService.normalizePhone(p), '+9647831367435');
    }
  });
  test('invalid or foreign numbers cannot be submitted', () {
    for (final p in [
      '',
      '123456',
      '+15551234567',
      '+9641234567890',
      '078313674350',
    ]) {
      expect(
        () => CustomerPhoneAuthService.normalizePhone(p),
        throwsA(isA<CustomerPhoneAuthException>()),
      );
    }
  });
}
