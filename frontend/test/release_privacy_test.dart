import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/release/release_privacy_screen.dart';

void main() {
  test('policy exposes real support, deletion and role-specific data use', () {
    const text = ReleasePrivacyScreen.policyText;
    expect(text, contains('support@wiz-go.com'));
    expect(text, contains('حذف الحساب'));
    expect(text, contains('عناوين التوصيل'));
    expect(text, isNot(contains('coming soon')));
    expect(text, isNot(contains('123 4567')));
  });
}
