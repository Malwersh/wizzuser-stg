/// App Store distribution is separate from the backend's historical stage name.
/// The owner explicitly chose the current services for public distribution.
class PublicReleaseConfig {
  static const enabled = bool.fromEnvironment('APP_STORE_RELEASE');
  static const values = <String, String>{
    'PUBLIC_BACKEND_APPROVED': String.fromEnvironment(
      'PUBLIC_BACKEND_APPROVED',
    ),
    'PUBLIC_BACKEND_ENVIRONMENT': String.fromEnvironment(
      'PUBLIC_BACKEND_ENVIRONMENT',
    ),
    'ENVIRONMENT': String.fromEnvironment('ENVIRONMENT'),
    'API_URL': String.fromEnvironment('API_URL'),
    'WEBSOCKET_URL': String.fromEnvironment('WEBSOCKET_URL'),
    'CENTRAL_PUSH_API_BASE_URL': String.fromEnvironment(
      'CENTRAL_PUSH_API_BASE_URL',
    ),
    'PHONE_AUTH_API_URL': String.fromEnvironment('PHONE_AUTH_API_URL'),
    'PHONE_LINK_API_URL': String.fromEnvironment('PHONE_LINK_API_URL'),
    'ORDER_SERVICE_URL': String.fromEnvironment('ORDER_SERVICE_URL'),
    'ACCOUNT_DELETION_API_URL': String.fromEnvironment(
      'ACCOUNT_DELETION_API_URL',
    ),
    'SLIDESHOW_API_URL': String.fromEnvironment('SLIDESHOW_API_URL'),
    'WALLET_TRANSFER_API_URL': String.fromEnvironment(
      'WALLET_TRANSFER_API_URL',
    ),
    'COGNITO_USER_POOL_ID': String.fromEnvironment('COGNITO_USER_POOL_ID'),
    'APP_CLIENT_ID': String.fromEnvironment('APP_CLIENT_ID'),
    'COGNITO_REGION': String.fromEnvironment('COGNITO_REGION'),
    'COMMERCIAL_PRICING_ENABLED': String.fromEnvironment(
      'COMMERCIAL_PRICING_ENABLED',
    ),
    'DELIVERY_QUOTES_ENABLED': String.fromEnvironment(
      'DELIVERY_QUOTES_ENABLED',
    ),
  };

  static void validate() {
    if (enabled) validateValues(values);
  }

  static void validateValues(Map<String, String> input) {
    if (input['PUBLIC_BACKEND_APPROVED'] != 'true' ||
        input['PUBLIC_BACKEND_ENVIRONMENT'] != input['ENVIRONMENT']) {
      throw StateError(
        'Public backend selection must be explicit and consistent',
      );
    }
    for (final name in values.keys) {
      final value = input[name] ?? '';
      if (value.trim().isEmpty || value.contains('YOUR_')) {
        throw StateError('Missing public configuration: $name');
      }
      if (name.endsWith('_URL')) {
        final uri = Uri.tryParse(value);
        final scheme = name == 'WEBSOCKET_URL' ? 'wss' : 'https';
        if (uri == null ||
            uri.scheme != scheme ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment ||
            ['localhost', '127.0.0.1', '::1'].contains(uri.host)) {
          throw StateError('Invalid public endpoint: $name');
        }
      }
    }
    for (final feature in [
      'COMMERCIAL_PRICING_ENABLED',
      'DELIVERY_QUOTES_ENABLED',
    ]) {
      if (input[feature] != 'true') {
        throw StateError(
          'Required current-service checkout feature disabled: $feature',
        );
      }
    }
  }
}
