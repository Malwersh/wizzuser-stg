import 'dart:convert';
import '../config/api_config.dart';

/// One preapproved confirmation for an explicitly built Staging test client.
/// This selects an attempt; only the server can admit its authenticated subject.
class ScopedCheckoutAttempt {
  final String userId, branchId, requestId;
  const ScopedCheckoutAttempt._(this.userId, this.branchId, this.requestId);

  static ScopedCheckoutAttempt? fromBuild() => ApiConfig.generalStagingFinance ? null : parse(
    const String.fromEnvironment('FINANCE_TEST_CHECKOUT_ATTEMPT'),
    environment: ApiConfig.environment,
    quotesEnabled: ApiConfig.deliveryQuotesEnabled,
    commercialEnabled: ApiConfig.commercialPricingEnabled,
    apiUrl: ApiConfig.baseUrl,
  );

  static ScopedCheckoutAttempt? parse(
    String raw, {
    required String environment,
    required bool quotesEnabled,
    required bool commercialEnabled,
    required String apiUrl,
  }) {
    if (raw.isEmpty) return null;
    final row = jsonDecode(raw);
    final id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:#-]{0,149}$');
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    if (environment != 'staging' ||
        !quotesEnabled ||
        !commercialEnabled ||
        apiUrl !=
            'https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging' ||
        row is! Map ||
        row.length != 4 ||
        row['schemaVersion'] != 1 ||
        row['userId'] is! String ||
        row['userId'] == 'guest' ||
        !id.hasMatch(row['userId']) ||
        row['branchId'] is! String ||
        !id.hasMatch(row['branchId']) ||
        row['requestId'] is! String ||
        !uuid.hasMatch(row['requestId'])) {
      throw const FormatException('INVALID_SCOPED_CHECKOUT_BUILD');
    }
    return ScopedCheckoutAttempt._(
      row['userId'],
      row['branchId'],
      row['requestId'],
    );
  }

  void check(String owner, String branch) {
    if (owner != userId || branch != branchId) {
      throw StateError('هذا الحساب أو النشاط خارج عينة الاختبار المعتمدة');
    }
  }
}
