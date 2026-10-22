import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/platform_benefit.dart';
import 'session_service.dart';
import 'delivery_address_manager.dart';

class PlatformBenefitsService {
  final http.Client _client;
  PlatformBenefitsService({http.Client? client})
    : _client = client ?? http.Client();
  void dispose() => _client.close();
  Future<List<PlatformBenefit>> load({String? branchId}) async {
    final session = SessionService.instance, account = session.currentUserId;
    final token = await session.getToken();
    if (!session.isLoggedIn || account == null || token == null)
      throw StateError('BENEFIT_LOGIN_REQUIRED');
    final addressId = DeliveryAddressManager.instance.activeAddress?.addressId;
    final response = await _client
        .get(
          Uri.parse('${ApiConfig.baseUrl}/promo-codes/active').replace(
            queryParameters: {
              'benefits': '1',
              'userId': account,
              if (addressId != null) 'addressId': addressId,
              if (branchId != null) 'businessId': branchId,
            },
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (account != session.currentUserId ||
        addressId != DeliveryAddressManager.instance.activeAddress?.addressId)
      throw StateError('BENEFIT_CONTEXT_CHANGED');
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        data is! Map ||
        data['success'] != true ||
        data['benefits'] is! List)
      throw StateError('BENEFIT_UNAVAILABLE');
    return (data['benefits'] as List)
        .map((x) => PlatformBenefit.fromJson(Map<String, dynamic>.from(x)))
        .toList();
  }
}
