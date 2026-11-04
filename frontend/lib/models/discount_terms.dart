/// Shared customer-facing redemption terms. Amounts are in IQD.
String formatDiscountNumber(double value) =>
    value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

class DiscountTerms {
  final double? maxDiscountAmount;
  final List<String> applicableCategoryIds;
  final bool firstOrderOnly;
  final bool newCustomerOnly;
  final bool singleUse;
  final int? perCustomerLimit;
  final List<String> customerSegments;

  const DiscountTerms({this.maxDiscountAmount,
    this.applicableCategoryIds = const [], this.firstOrderOnly = false, this.newCustomerOnly = false,
    this.singleUse = false, this.perCustomerLimit,
    this.customerSegments = const []});

  factory DiscountTerms.fromJson(Map<String, dynamic> json) => DiscountTerms(
    maxDiscountAmount: double.tryParse((json['maxDiscountAmount'] ?? json['maxDiscount'] ?? '').toString()),
    applicableCategoryIds: ((json['applicable_category_ids'] ?? json['applicableCategoryIds']) as List?)?.map((e) => e.toString()).toList() ?? const [],
    firstOrderOnly: json['firstOrderOnly'] == true || ['first-order', 'first_order'].contains(json['campaignType']),
    newCustomerOnly: json['newCustomerOnly'] == true || ['new-customer', 'new_customer'].contains(json['campaignType']),
    singleUse: json['singleUse'] == true,
    perCustomerLimit: (json['perCustomerLimit'] as num?)?.toInt(),
    customerSegments: (json['customerSegments'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  String summary({required double minimum, String applicability = 'allItems', DateTime? end}) {
    final parts = <String>[];
    if (applicability == 'specificItems') parts.add('على أصناف محددة');
    if (applicability == 'specificCategories') parts.add('على فئات محددة');
    if (minimum > 0) parts.add('الحد الأدنى ${formatDiscountNumber(minimum)} د.ع');
    if (maxDiscountAmount != null) parts.add('أقصى خصم ${formatDiscountNumber(maxDiscountAmount!)} د.ع');
    if (firstOrderOnly) parts.add('لأول طلب فقط');
    if (newCustomerOnly) parts.add('للحسابات التي أُنشئت قبل أقل من 7 أيام');
    if (singleUse || perCustomerLimit == 1) {
      parts.add('مرة واحدة لكل عميل');
    } else if (perCustomerLimit != null) {
      parts.add('حتى $perCustomerLimit مرات لكل عميل');
    }
    // Segments are alternatives; listing them as independent requirements is misleading.
    if (customerSegments.isNotEmpty && !customerSegments.contains('all')) {
      const labels = {'registered': 'المسجلون', 'guests': 'الضيوف', 'new': 'العملاء الجدد',
        'returning': 'العملاء السابقون', 'vip': 'العملاء المميزون', 'inactive': 'العملاء غير النشطين'};
      parts.add('للعملاء المؤهلين: ${customerSegments.map((s) => labels[s] ?? s).join(' أو ')}');
    }
    if (end != null) {
      final baghdad = end.toUtc().add(const Duration(hours: 3));
      String two(int n) => n.toString().padLeft(2, '0');
      parts.add('ينتهي ${baghdad.year}/${two(baghdad.month)}/${two(baghdad.day)} ${two(baghdad.hour)}:${two(baghdad.minute)} بتوقيت بغداد');
    }
    return parts.join(' • ');
  }
}
