import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class BusinessStatusBatchService {
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  /// يستدعي المسار الدفعي لإرجاع حالات عدة مطاعم دفعة واحدة
  /// body: { "businessIds": ["id1","id2", ...] }
  /// response: { statuses: { id: { currentStatus, isClosed, isAvailableNow, acceptingOrders, ... } }, timestamp }
  static Future<Map<String, dynamic>> fetchStatuses(List<String> businessIds) async {
    if (businessIds.isEmpty) return {};
    try {
      final uri = Uri.parse('$_baseUrl/businesses/status');
      final body = json.encode({ 'businessIds': businessIds });
      developer.log('📡 Batch status request for ${businessIds.length} businesses');

      final res = await http
          .post(
            uri,
            headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        debugPrint('📦 API Response: ${json.encode(data)}');
        final statuses = (data['statuses'] as Map?)?.cast<String, dynamic>() ?? {};
        debugPrint('✅ Received ${statuses.length} statuses from ${businessIds.length} IDs');
        if (statuses.isEmpty) {
          debugPrint('⚠️ Batch endpoint returned empty statuses!');
          debugPrint('📋 Requested IDs: ${businessIds.take(3).join(", ")}...');
          debugPrint('📄 Response keys: ${data.keys.toList()}');
        } else {
          debugPrint('📊 Status IDs returned: ${statuses.keys.take(3).join(", ")}...');
        }
        return statuses;
      }

      developer.log('⚠️ Batch status request failed: ${res.statusCode}');
      return {};
    } catch (e) {
      developer.log('❌ Batch status error: $e');
      return {};
    }
  }
}

