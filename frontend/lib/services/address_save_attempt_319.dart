import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddressSaveAttempt319 {
  static dynamic _canonical(dynamic v) =>
      v is Map
          ? {
            for (final k in (v.keys.map((x) => x.toString()).toList()..sort()))
              k: _canonical(v[k]),
          }
          : v is List
          ? v.map(_canonical).toList()
          : v;
  static String signature(String owner, Map<String, dynamic> body) {
    final data = Map<String, dynamic>.from(body)..remove('idempotency_key');
    return sha256
        .convert(utf8.encode(jsonEncode([owner, _canonical(data)])))
        .toString();
  }

  static Future<String> key(
    String owner,
    Map<String, dynamic> body, {
    String? suggested,
  }) async {
    final prefs = await SharedPreferences.getInstance(),
        slot = 'address_attempt_319_${signature(owner, body)}';
    final saved = prefs.getString(slot);
    if (saved != null) return saved;
    final random = Random.secure();
    final key =
        suggested ??
        List.generate(
          24,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    if (!await prefs.setString(slot, key))
      throw StateError('Could not preserve save attempt');
    return key;
  }

  static Future<void> confirmed(
    String owner,
    Map<String, dynamic> body,
    String key,
  ) async {
    final prefs = await SharedPreferences.getInstance(),
        slot = 'address_attempt_319_${signature(owner, body)}';
    if (prefs.getString(slot) == key) await prefs.remove(slot);
  }
}
