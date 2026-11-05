import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/config/public_release_config.dart';

void main() {
  late Map<String, String> config;
  setUp(() {
    config = Map<String, String>.from(
      jsonDecode(
            File('config/appstore-current-services.json').readAsStringSync(),
          )
          as Map,
    );
  });
  test('approved current public services retain checkout capabilities', () {
    expect(() => PublicReleaseConfig.validateValues(config), returnsNormally);
  });
  test('mixed backend decision is rejected', () {
    config['ENVIRONMENT'] = 'production';
    expect(() => PublicReleaseConfig.validateValues(config), throwsStateError);
  });
  test('missing endpoint is rejected', () {
    config.remove('ACCOUNT_DELETION_API_URL');
    expect(() => PublicReleaseConfig.validateValues(config), throwsStateError);
  });
  test('cleartext and local endpoints are rejected', () {
    for (final url in [
      'http://example.com',
      'https://localhost',
      'https://user@example.com',
    ]) {
      config['API_URL'] = url;
      expect(
        () => PublicReleaseConfig.validateValues(config),
        throwsStateError,
      );
    }
  });
  test(
    'current checkout features cannot silently disappear in public build',
    () {
      config['DELIVERY_QUOTES_ENABLED'] = 'false';
      expect(
        () => PublicReleaseConfig.validateValues(config),
        throwsStateError,
      );
    },
  );
}
