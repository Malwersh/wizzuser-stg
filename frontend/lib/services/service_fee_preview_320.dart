import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Public, short-lived informational base charge. Never authorizes an invoice.
class ServiceFeePreview320 extends ChangeNotifier {
  static final instance = ServiceFeePreview320();
  final http.Client client;
  final DateTime Function() now;
  final _cache = <String, Map<String, dynamic>>{};
  final _running = <String, Future<void>>{};
  ServiceFeePreview320({http.Client? client, DateTime Function()? now})
    : client = client ?? http.Client(),
      now = now ?? DateTime.now;
  double? baseIqd(String branch) {
    final row = _cache[branch];
    if (row == null || !now().isBefore(DateTime.parse(row['expiresAt'])))
      return null;
    final m = row['baseServiceFee'];
    return m == null ? null : (m['minorAmount'] as int) / 1000;
  }

  Future<void> ensure(String branch) {
    if (branch.isEmpty || baseIqd(branch) != null) return Future.value();
    return _running[branch] ??= _load(branch).whenComplete(() {
      _running.remove(branch);
    });
  }

  Future<void> _load(String branch) async {
    try {
      final response = await client
          .post(
            Uri.parse(ApiConfig.buildUrl('/storefront-point-preview')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'service_fee_preview',
              'branchId': branch,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final p = jsonDecode(utf8.decode(response.bodyBytes))['preview'];
      final expires = DateTime.tryParse(p?['expiresAt'] ?? ''),
          m = p?['baseServiceFee'];
      if (p is! Map ||
          p['kind'] != 'SERVICE_FEE_PREVIEW' ||
          p['schemaVersion'] != 1 ||
          p['branchId'] != branch ||
          p['informationalOnly'] != true ||
          p['requiresFinalConfirmation'] != true ||
          expires == null ||
          !now().isBefore(expires) ||
          expires.difference(now()).inSeconds > 120)
        return;
      if (m != null &&
          (m is! Map ||
              m['moneySchemaVersion'] != 1 ||
              m['currency'] != 'IQD' ||
              m['scale'] != 1000 ||
              m['minorAmount'] is! int ||
              m['minorAmount'] < 0))
        return;
      if (_cache.length >= 50) _cache.remove(_cache.keys.first);
      _cache[branch] = Map<String, dynamic>.from(p);
      notifyListeners();
    } catch (_) {}
  }
}
