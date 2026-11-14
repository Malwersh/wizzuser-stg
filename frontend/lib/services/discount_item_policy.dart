import 'dart:convert';

const unsupportedDiscountItemsMessage =
    'تعذر التحقق من خيارات هذا الصنف. حدّث اختياراتك من قائمة المتجر ثم أعد المحاولة.';
const _selectionFields = [
  'modifiers',
  'customizations',
  'selectedOptions',
  'selected_options',
  'variantId',
  'variant_id',
  'sizeId',
  'size_id',
];

bool _populated(dynamic value, [int depth = 0]) {
  if (value == null || value == '' || value == false) return false;
  if (depth > 8) return true;
  if (value is List) return value.isNotEmpty;
  if (value is Map) return value.values.any((v) => _populated(v, depth + 1));
  return true;
}

bool hasDiscountCustomizations(List<Map<String, dynamic>> items) => items.any((item) {
  if ((item['modifiers'] != null && item['modifiers'] is! List) ||
      ['modifiers', 'variantId', 'variant_id', 'sizeId', 'size_id'].any((key) => _populated(item[key]))) return true;
  String? selection;
  final id = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
  for (final key in ['selectedOptions', 'selected_options', 'customizations']) {
    final value = item[key];
    if (!_populated(value) && value is! Map) continue;
    if (value is! Map || value.length > 20 || value.keys.any((k) => k is! String)) return true;
    final normalized = <String, List<String>>{};
    final groups = value.keys.cast<String>().toList()..sort();
    for (final group in groups) {
      final ids = value[group];
      if (!id.hasMatch(group) || ids is! List || ids.length > 40 || ids.any((v) => v is! String || !id.hasMatch(v)) || ids.toSet().length != ids.length) return true;
      if (ids.isNotEmpty) normalized[group] = ids.cast<String>().toList()..sort();
    }
    final encoded = jsonEncode(normalized);
    if (selection != null && selection != encoded) return true;
    selection = encoded;
  }
  return false;
});

/// Preserve every selection alias so an order serializer cannot hide a choice.
Map<String, dynamic> discountSelectionFields(Map<String, dynamic> item) => {
  for (final field in _selectionFields)
    if (item.containsKey(field)) field: item[field],
};
