import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted account/backend scoped metadata. No credentials or message history.
class SupportConversationCheckpoint {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static Future<void> _pending = Future.value();
  static String _key(String scope) =>
      'support_v3_${sha256.convert(utf8.encode(scope))}';
  static Future<String?> read(String scope) async {
    await _pending;
    return _storage.read(key: _key(scope));
  }

  static Future<void> write(String scope, String value) {
    final operation = _pending.then(
      (_) => _storage.write(key: _key(scope), value: value),
    );
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }
}
