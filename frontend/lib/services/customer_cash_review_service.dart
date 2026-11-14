import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';

class CustomerCashReviewService {
  final http.Client client;
  final Future<String?> Function() token;
  static const base = String.fromEnvironment(
    'ORDER_SERVICE_URL',
    defaultValue:
        'https://mqwom78d3c.execute-api.us-east-1.amazonaws.com/staging',
  );
  CustomerCashReviewService({
    http.Client? client,
    Future<String?> Function()? token,
  }) : client = client ?? http.Client(),
       token = token ?? (() async => SessionService.instance.accessToken);
  Future<Map<String, dynamic>> call(
    String orderId,
    Map<String, dynamic> body,
  ) async {
    final credential = await token();
    if (credential == null || credential.isEmpty) {
      throw Exception('UNAUTHORIZED');
    }
    final response = await client
        .post(
          Uri.parse('$base/order/cancel'),
          headers: {
            'Authorization': 'Bearer $credential',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            ...body,
            'orderId': orderId,
            'workflow': 'CUSTOMER_CASH_REVIEW',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (await token() != credential) throw Exception('UNAUTHORIZED');
    final value = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        value is! Map<String, dynamic> ||
        value['success'] != true ||
        value['orderId'] != orderId) {
      throw Exception(value is Map ? value['code'] : 'CASH_REVIEW_UNAVAILABLE');
    }
    return value;
  }
}
