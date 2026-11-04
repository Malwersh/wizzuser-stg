class PlatformBenefit {
  final String id, title, description, kind;
  final DateTime startAt, endAt;
  final int amountIqd, maximumPerOrderIqd, minimumGoodsIqd, maximumRoadMeters;
  final int granted, reserved, used, remaining;
  final bool eligible;
  final String? reason;
  final List<String> branchIds;
  const PlatformBenefit({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.startAt,
    required this.endAt,
    required this.amountIqd,
    required this.maximumPerOrderIqd,
    required this.minimumGoodsIqd,
    required this.maximumRoadMeters,
    required this.granted,
    required this.reserved,
    required this.used,
    required this.remaining,
    required this.eligible,
    required this.reason,
    required this.branchIds,
  });
  bool get isDelivery => kind != 'GOODS_AMOUNT';
  factory PlatformBenefit.fromJson(Map<String, dynamic> row) {
    int number(String key) {
      final value = row[key];
      if (value is! int || value < 0)
        throw const FormatException('Invalid benefit balance');
      return value;
    }

    final kind = row['kind'];
    if (row['schemaVersion'] != 1 ||
        ![
          'FREE_DELIVERIES',
          'GOODS_AMOUNT',
          'DELIVERY_AMOUNT',
        ].contains(kind) ||
        row['id'] is! String ||
        row['title'] is! String ||
        row['description'] is! String ||
        row['eligible'] is! bool)
      throw const FormatException('Invalid benefit');
    final granted = number('granted'),
        reserved = number('reserved'),
        used = number('used'),
        remaining = number('remaining');
    if (granted != reserved + used + remaining)
      throw const FormatException('Invalid benefit balance');
    return PlatformBenefit(
      id: row['id'],
      title: row['title'],
      description: row['description'],
      kind: kind,
      startAt: DateTime.parse(row['startAt']),
      endAt: DateTime.parse(row['endAt']),
      amountIqd: number('amountIqd'),
      maximumPerOrderIqd: number('maximumPerOrderIqd'),
      minimumGoodsIqd: number('minimumGoodsIqd'),
      maximumRoadMeters: number('maximumRoadMeters'),
      granted: granted,
      reserved: reserved,
      used: used,
      remaining: remaining,
      eligible: row['eligible'],
      reason: row['reason'] as String?,
      branchIds: List<String>.from(row['branchIds'] as List),
    );
  }
}
