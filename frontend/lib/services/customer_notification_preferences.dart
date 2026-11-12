import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'session_service.dart';

class CustomerNotificationPreferences {
  final bool orders, promotions;
  const CustomerNotificationPreferences({
    this.orders = true,
    this.promotions = true,
  });
  factory CustomerNotificationPreferences.fromJson(
    Map<dynamic, dynamic>? value,
  ) => CustomerNotificationPreferences(
    orders: value?['order_notifications'] != false,
    promotions: value?['promotion_notifications'] != false,
  );
  Map<String, bool> toJson() => {
    'order_notifications': orders,
    'promotion_notifications': promotions,
  };
  bool allows(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'campaign_offer') return promotions;
    if (type == 'order_update') return orders;
    return true; // Support/security and unknown operational messages are not marketing.
  }
}

class CustomerNotificationPreferencesService {
  final http.Client _client;
  final String? Function() _owner;
  final Future<String?> Function() _token;
  CustomerNotificationPreferencesService({
    http.Client? client,
    String? Function()? owner,
    Future<String?> Function()? token,
  }) : _client = client ?? http.Client(),
       _owner = owner ?? (() => SessionService.instance.currentUserId),
       _token = token ?? SessionService.instance.getToken;
  Future<CustomerNotificationPreferences> _request({
    CustomerNotificationPreferences? save,
  }) async {
    final owner = _owner();
    if (owner == null || owner.isEmpty) throw StateError('AUTH_REQUIRED');
    final token = await _token();
    if (_owner() != owner || token == null || token.isEmpty) {
      throw StateError('AUTH_REQUIRED');
    }
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final path =
        '${ApiConfig.baseUrl}/users/${Uri.encodeComponent(owner)}/${save == null ? 'profile' : 'preferences'}';
    final response = await (save == null
            ? _client.get(Uri.parse(path), headers: headers)
            : _client.put(
              Uri.parse(path),
              headers: headers,
              body: jsonEncode({'notification_settings': save.toJson()}),
            ))
        .timeout(const Duration(seconds: 15));
    if (_owner() != owner) throw StateError('ACCOUNT_CHANGED');
    if (response.statusCode != 200) throw StateError('PREFERENCES_UNAVAILABLE');
    final body = jsonDecode(response.body);
    final data = body is Map ? body['data'] : null;
    if (body is! Map ||
        body['success'] != true ||
        data is! Map ||
        data['id'] != owner) {
      throw StateError('PREFERENCES_INVALID_RESPONSE');
    }
    final settings = data['notification_settings'];
    if (settings != null && settings is! Map) {
      throw StateError('PREFERENCES_INVALID_RESPONSE');
    }
    return CustomerNotificationPreferences.fromJson(settings as Map?);
  }

  Future<CustomerNotificationPreferences> load() => _request();
  Future<CustomerNotificationPreferences> save(
    CustomerNotificationPreferences value,
  ) => _request(save: value);
  void close() => _client.close();
}
