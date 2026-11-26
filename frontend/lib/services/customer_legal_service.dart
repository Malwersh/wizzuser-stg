import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/customer_legal_bundle.dart';
import 'customer_phone_auth_service.dart';

class CustomerLegalService {
  static final instance = CustomerLegalService();
  final http.Client _client;
  final String baseUrl;
  final String audience;
  CustomerLegalBundle? _cached;
  DateTime? _loadedAt;
  CustomerLegalService({
    http.Client? client,
    this.baseUrl = CustomerPhoneAuthService.baseUrl,
    this.audience = 'CUSTOMER',
  }) : _client = client ?? http.Client();
  Future<CustomerLegalBundle> load({bool refresh = false}) async {
    if (!refresh &&
        _cached != null &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 2))
      return _cached!;
    final r = await _client
        .get(
          Uri.parse(
            '$baseUrl/legal',
          ).replace(queryParameters: {'audience': audience}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200)
      throw StateError('تعذر تحميل السياسات المنشورة. أعد المحاولة.');
    final bundle = CustomerLegalBundle.fromJson(
      jsonDecode(utf8.decode(r.bodyBytes))['bundle'],
    );
    if (bundle.audience != audience)
      throw const FormatException('WRONG_LEGAL_AUDIENCE');
    _cached = bundle;
    _loadedAt = DateTime.now();
    return bundle;
  }
}
