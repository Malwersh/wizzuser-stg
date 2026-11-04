import 'dart:convert';
import 'package:crypto/crypto.dart';

class CustomerLegalBundle {
  final Map<String, dynamic> _data;
  CustomerLegalBundle._(this._data);
  static dynamic canonical(dynamic v) {
    if (v is List) return v.map(canonical).toList();
    if (v is Map) {
      final k = v.keys.cast<String>().toList()..sort();
      return {for (final key in k) key: canonical(v[key])};
    }
    return v;
  }

  factory CustomerLegalBundle.fromJson(dynamic input) {
    if (input is! Map) throw const FormatException('INVALID_LEGAL_DOCUMENTS');
    final m = Map<String, dynamic>.from(jsonDecode(jsonEncode(input)));
    final digest = m.remove('digest');
    if (!['CUSTOMER', 'DRIVER', 'MERCHANT'].contains(m['audience']) ||
        m['schemaVersion'] != 1 ||
        m['revision'] is! int ||
        m['revision'] < 1 ||
        DateTime.tryParse(m['publishedAt']?.toString() ?? '') == null ||
        m['brand'] is! Map ||
        m['documents'] is! List ||
        m['documents'].length != 4)
      throw const FormatException('INVALID_LEGAL_DOCUMENTS');
    final computed =
        sha256.convert(utf8.encode(jsonEncode(canonical(m)))).toString();
    if (digest != computed) throw const FormatException('INVALID_LEGAL_DIGEST');
    final ids = <String>{};
    for (final d in m['documents']) {
      if (d is! Map ||
          !['USAGE', 'TERMS', 'PRIVACY', 'CANCELLATION'].contains(d['id']) ||
          !ids.add(d['id']) ||
          d['title'] is! String ||
          d['sections'] is! List ||
          d['sections'].isEmpty)
        throw const FormatException('INVALID_LEGAL_DOCUMENTS');
      for (final s in d['sections']) {
        if (s is! Map || s['heading'] is! String || s['body'] is! String)
          throw const FormatException('INVALID_LEGAL_DOCUMENTS');
      }
    }
    for (final f in [
      'appName',
      'companyName',
      'logoKey',
      'supportPhone',
      'supportEmail',
    ]) {
      if (m['brand'][f] is! String)
        throw const FormatException('INVALID_LEGAL_BRAND');
    }
    return CustomerLegalBundle._({...m, 'digest': digest});
  }
  String get audience => _data['audience'];
  int get revision => _data['revision'];
  String get publishedAt => _data['publishedAt'];
  Map<String, dynamic> get brand => Map<String, dynamic>.from(_data['brand']);
  Map<String, dynamic> get pin => {
    'revision': revision,
    'digest': _data['digest'],
  };
  List<Map<String, dynamic>> get documents =>
      (_data['documents'] as List)
          .map((e) => Map<String, dynamic>.from(jsonDecode(jsonEncode(e))))
          .toList();
  Map<String, dynamic> document(String id) =>
      documents.firstWhere((d) => d['id'] == id);
}
