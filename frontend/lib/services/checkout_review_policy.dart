import 'dart:convert';

/// A tap on payment confirms only the exact, unexpired server invoice shown.
/// A changed quote or selection always retains the explicit review sheet.
bool canConfirmDisplayedInvoice({
  required Map<String, dynamic>? displayed,
  required Map<String, dynamic> proposed,
  required bool sameScope,
  DateTime? now,
}) {
  if (!sameScope || displayed == null) return false;
  final expiry = DateTime.tryParse(proposed['expiresAt']?.toString() ?? '');
  if (expiry == null || !expiry.isAfter(now ?? DateTime.now())) return false;
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return jsonEncode(canonical(displayed)) == jsonEncode(canonical(proposed));
}
