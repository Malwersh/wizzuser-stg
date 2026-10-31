import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';

class RatingException implements Exception {
  final String code;
  const RatingException(this.code);
}

class OrderRatingService {
  static const defaultEndpoint = String.fromEnvironment('RATINGS_API_URL', defaultValue: 'https://hozgpdv0kg.execute-api.us-east-1.amazonaws.com/staging');
  final http.Client client;
  final Future<String?> Function() token;
  final String? Function() owner;
  final String endpoint;
  late final String? _owner;
  OrderRatingService({
    http.Client? client,
    Future<String?> Function()? token,
    String? Function()? owner,
    this.endpoint = defaultEndpoint,
  }) : client = client ?? http.Client(),
       token = token ?? (() => SessionService.instance.getToken()),
       owner =
           owner ??
           (() =>
               SessionService.instance.isLoggedIn &&
                       !SessionService.instance.isGuest
                   ? SessionService.instance.currentUserId
                   : null) {
    // Bind ownership at construction, not at the first delayed response.
    _owner = this.owner();
  }
  bool get sameOwner => _owner != null && owner() == _owner;
  Future<Map<String, dynamic>> load(String orderId) => _request(orderId, null);
  Future<Map<String, dynamic>> submit(
    String orderId, {
    required int merchantStars,
    int? driverStars,
    String comment = '',
  }) => _request(orderId, {
    'merchantStars': merchantStars,
    'driverStars': driverStars,
    'comment': comment.trim(),
  });
  Future<Map<String, dynamic>> _request(
    String orderId,
    Map<String, dynamic>? body,
  ) async {
    if (!sameOwner) throw const RatingException('UNAUTHORIZED');
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const RatingException('RATINGS_UNAVAILABLE');
    }
    final credential = await token();
    if (!sameOwner || credential == null || credential.isEmpty) {
      throw const RatingException('UNAUTHORIZED');
    }
    final url = Uri.parse(
      '${endpoint.replaceFirst(RegExp(r'/+$'), '')}/orders/${Uri.encodeComponent(orderId)}/rating',
    );
    final headers = {
      'Authorization': 'Bearer $credential',
      'Content-Type': 'application/json',
    };
    try {
      final response = await (body == null
              ? client.get(url, headers: headers)
              : client.post(url, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 20));
      if (!sameOwner) throw const RatingException('UNAUTHORIZED');
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          data is! Map<String, dynamic> ||
          data['success'] != true ||
          data['orderId'] != orderId) {
        throw RatingException(
          data is Map && data['code'] is String
              ? data['code']
              : 'RATINGS_UNAVAILABLE',
        );
      }
      if (body == null &&
          (data['driverEligible'] is! bool ||
              data['merchantName'] is! String ||
              data['driverName'] is! String)) {
        throw const RatingException('RATINGS_UNAVAILABLE');
      }
      return data;
    } on RatingException {
      rethrow;
    } catch (_) {
      throw const RatingException('RATINGS_UNAVAILABLE');
    }
  }

  void dispose() => client.close();
}
