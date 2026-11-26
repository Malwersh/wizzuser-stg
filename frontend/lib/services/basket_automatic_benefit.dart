import '../models/platform_benefit.dart';

/// Selects only a server-validated delivery entitlement, never a fabricated
/// saving or a replacement for an explicit coupon. Previews do not redeem it.
Future<
  ({PlatformBenefit benefit, Map<String, dynamic> invoice, int savingMinor})?
>
selectAutomaticDeliveryBenefit({
  required String branch,
  required Map<String, dynamic> baseline,
  required List<PlatformBenefit> benefits,
  required Future<Map<String, dynamic>?> Function(PlatformBenefit) preview,
  required bool Function() current,
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  int? minor(Map<String, dynamic> p, String key) =>
      p[key] is Map && p[key]['minorAmount'] is int
          ? p[key]['minorAmount'] as int
          : null;
  final total = minor(baseline, 'customerTotal'),
      goods = minor(baseline, 'goodsGross');
  final baselineExpiry = DateTime.tryParse(
    baseline['expiresAt']?.toString() ?? '',
  );
  if (total == null ||
      goods == null ||
      baselineExpiry == null ||
      !now().isBefore(baselineExpiry) ||
      !current())
    return null;
  final candidates =
      benefits
          .where(
            (b) =>
                b.isDelivery &&
                b.availableFor(branch, at: now()) &&
                goods >= b.minimumGoodsIqd * 1000,
          )
          .toList()
        ..sort((a, b) => b.maximumPerOrderIqd.compareTo(a.maximumPerOrderIqd));
  for (final b in candidates) {
    if (!current()) return null;
    final p = await preview(b);
    if (!current() || !now().isBefore(baselineExpiry)) return null;
    if (p == null || !b.availableFor(branch, at: now())) continue;
    final expires = DateTime.tryParse(p['expiresAt']?.toString() ?? '');
    final nextTotal = minor(p, 'customerTotal'),
        fee = minor(p, 'deliveryFee'),
        oldFee = minor(baseline, 'deliveryFee');
    if (expires == null ||
        !now().isBefore(expires) ||
        nextTotal == null ||
        fee == null ||
        oldFee == null ||
        nextTotal < 0 ||
        fee < 0 ||
        nextTotal >= total ||
        fee >= oldFee ||
        total - nextTotal != oldFee - fee)
      continue;
    return (benefit: b, invoice: p, savingMinor: total - nextTotal);
  }
  return null;
}
