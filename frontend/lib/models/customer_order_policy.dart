import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'customer_order_policy_data_343.dart';

class CustomerOrderPolicy {
  final Map<String, dynamic> document;
  final String digest;
  CustomerOrderPolicy._(this.document, this.digest);
  static dynamic _canonical(dynamic value) {
    if (value is List) return value.map(_canonical).toList();
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    return value;
  }

  factory CustomerOrderPolicy.parse(
    dynamic value, {
    bool requireDigest = true,
  }) {
    if (value is! Map) throw const FormatException('INVALID_CUSTOMER_POLICY');
    final data = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
    final digest = data.remove('digest');
    if (data.keys.toSet().difference({
          'schemaVersion',
          'policyId',
          'version',
          'locale',
          'title',
          'sections',
        }).isNotEmpty ||
        data['schemaVersion'] != 1 ||
        data['policyId'] != 'CASH_ORDER_CUSTOMER' ||
        data['version'] is! int ||
        data['version'] < 1 ||
        data['locale'] != 'ar-IQ' ||
        data['title'] is! String ||
        data['sections'] is! List ||
        data['sections'].isEmpty ||
        data['sections'].length > 12)
      throw const FormatException('INVALID_CUSTOMER_POLICY');
    for (final section in data['sections']) {
      if (section is! Map ||
          section.length != 3 ||
          !['id', 'title', 'body'].every(
            (k) =>
                section[k] is String &&
                (section[k] as String).isNotEmpty &&
                (section[k] as String).length < 2500,
          ))
        throw const FormatException('INVALID_CUSTOMER_POLICY');
    }
    final computed =
        sha256.convert(utf8.encode(jsonEncode(_canonical(data)))).toString();
    if (requireDigest && digest != computed)
      throw const FormatException('INVALID_CUSTOMER_POLICY_DIGEST');
    return CustomerOrderPolicy._(data, computed);
  }
  static CustomerOrderPolicy get current => CustomerOrderPolicy.parse(
    jsonDecode(customerOrderPolicyData343),
    requireDigest: false,
  );
  String get title => document['title'];
  int get version => document['version'];
  List<Map<String, dynamic>> get sections =>
      (document['sections'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Map<String, dynamic> get pin => {
    'policyId': document['policyId'],
    'version': version,
    'digest': digest,
  };
}
