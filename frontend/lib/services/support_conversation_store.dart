import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SupportConversationStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Each account, backend and order has its own encrypted checkpoint. No tokens
/// or message history are stored here; history is fetched after authorization.
class SecureSupportConversationStore implements SupportConversationStore {
  SecureSupportConversationStore({
    required String ownerId,
    required String endpoint,
    String? orderId,
  }) : _key =
           'support_${sha256.convert(utf8.encode(jsonEncode([ownerId, endpoint, orderId])))}';
  final String _key;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  // Serialize operations across screen instances, including writes during exit.
  static Future<void> _pending = Future.value();
  @override
  Future<String?> read() async {
    await _pending;
    return _storage.read(key: _key);
  }

  @override
  Future<void> write(String value) {
    final operation = _pending.then(
      (_) => _storage.write(key: _key, value: value),
    );
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }
}
