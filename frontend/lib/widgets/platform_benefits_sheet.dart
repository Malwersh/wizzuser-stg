import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../models/platform_benefit.dart';
import '../services/platform_benefits_service.dart';
import '../services/pending_offer.dart';
import '../services/session_service.dart';

Future<bool?> showPlatformBenefitsSheet(
  BuildContext context, {
  String? branchId,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  clipBehavior: Clip.antiAlias,
  builder:
      (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        minChildSize: .45,
        maxChildSize: .96,
        builder:
            (_, controller) => PlatformBenefitsSheet(
              branchId: branchId,
              controller: controller,
            ),
      ),
);

class PlatformBenefitsSheet extends StatefulWidget {
  final String? branchId;
  final ScrollController? controller;
  final Future<List<PlatformBenefit>> Function()? loader;
  const PlatformBenefitsSheet({
    super.key,
    this.branchId,
    this.controller,
    this.loader,
  });
  @override
  State<PlatformBenefitsSheet> createState() => _PlatformBenefitsSheetState();
}

class _PlatformBenefitsSheetState extends State<PlatformBenefitsSheet> {
  final service = PlatformBenefitsService();
  late Future<List<PlatformBenefit>> pending;
  late String? account;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    account = SessionService.instance.currentUserId;
    pending = widget.loader?.call() ?? service.load(branchId: widget.branchId);
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    String text(String a, String e) => ar ? a : e;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    String money(int value) =>
        '${localizations.formatDecimal(value)} ${text('د.ع', 'IQD')}';
    String date(DateTime value) {
      final local = value.toLocal();
      return '${localizations.formatMediumDate(local)}، ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    }

    final canUse =
        ApiConfig.commercialPricingEnabled && ApiConfig.deliveryQuotesEnabled;
    Widget detail(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Widget balance(String label, int value) => Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            localizations.formatDecimal(value),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: ListView(
        controller: widget.controller,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text('مزاياك من ويز', 'Your Wizz benefits'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      text(
                        'هداياك وخصوماتك، وتفاصيل استخدامها',
                        'Your rewards, discounts and how to use them',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: text('إغلاق', 'Close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<PlatformBenefit>>(
            future: pending,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 36,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        text(
                          'تعذر تحميل مزاياك. تحقق من تسجيل الدخول والاتصال.',
                          'Unable to load benefits. Check your sign-in and connection.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(reload),
                        child: Text(text('إعادة المحاولة', 'Retry')),
                      ),
                    ],
                  ),
                );
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.card_giftcard_rounded,
                        size: 44,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        text(
                          'لا توجد مزايا متاحة حالياً',
                          'No benefits available yet',
                        ),
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        text(
                          'ستظهر هنا المزايا المتاحة لحسابك وعنوانك.',
                          'Benefits available for your account and address will appear here.',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  b.isDelivery
                                      ? Icons.delivery_dining_rounded
                                      : Icons.card_giftcard_rounded,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b.title,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            height: 1.5,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      b.isDelivery
                                          ? text(
                                            'ميزة توصيل',
                                            'Delivery benefit',
                                          )
                                          : text(
                                            'خصم على المنتجات',
                                            'Goods discount',
                                          ),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (b.description.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              b.description,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.6,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer.withValues(
                                alpha: .45,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              b.kind == 'FREE_DELIVERIES'
                                  ? text(
                                    'متبقي ${localizations.formatDecimal(b.remaining)} توصيلات مجانية',
                                    '${b.remaining} free deliveries remaining',
                                  )
                                  : text(
                                    'خصم حتى ${money(b.amountIqd)} ${b.isDelivery ? 'على التوصيل' : 'على المنتجات'}',
                                    'Up to ${money(b.amountIqd)} off ${b.isDelivery ? 'delivery' : 'goods'}',
                                  ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              balance(text('متاح', 'Available'), b.remaining),
                              balance(
                                text('قيد الاستخدام', 'In progress'),
                                b.reserved,
                              ),
                              balance(text('مستخدم', 'Used'), b.used),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          detail(
                            Icons.shopping_bag_outlined,
                            text('الحد الأدنى للمنتجات', 'Minimum goods'),
                            money(b.minimumGoodsIqd),
                          ),
                          if (b.isDelivery) ...[
                            detail(
                              Icons.route_outlined,
                              text('نطاق التوصيل', 'Delivery distance'),
                              text(
                                'ضمن ${(b.maximumRoadMeters / 1000).toStringAsFixed(1)} كم',
                                'Within ${(b.maximumRoadMeters / 1000).toStringAsFixed(1)} km',
                              ),
                            ),
                            detail(
                              Icons.payments_outlined,
                              text(
                                'أقصى خصم للطلب',
                                'Maximum discount per order',
                              ),
                              money(b.maximumPerOrderIqd),
                            ),
                          ],
                          if (b.branchIds.isNotEmpty)
                            detail(
                              Icons.storefront_outlined,
                              text('المطاعم', 'Restaurants'),
                              text(
                                'لدى المطاعم المشمولة فقط',
                                'Participating restaurants only',
                              ),
                            ),
                          if (b.startAt.isAfter(DateTime.now()))
                            detail(
                              Icons.event_outlined,
                              text('يبدأ', 'Starts'),
                              date(b.startAt),
                            ),
                          detail(
                            Icons.schedule_rounded,
                            text('صالح لغاية', 'Expires'),
                            date(b.endAt),
                          ),
                          if (b.kind == 'GOODS_AMOUNT') ...[
                            const SizedBox(height: 8),
                            Text(
                              text(
                                'للطلب الواحد، ولا يُرحّل أي مبلغ غير مستخدم.',
                                'One order only. Any unused amount does not carry over.',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.6,
                              ),
                            ),
                          ],
                          if (!b.eligible) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                text(
                                  b.startAt.isAfter(DateTime.now())
                                      ? 'لم يبدأ العرض بعد'
                                      : _reason(b.reason),
                                  'This benefit is currently unavailable.',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onPressed:
                                !canUse || !b.eligible || b.remaining == 0
                                    ? null
                                    : () {
                                      if (account !=
                                          SessionService
                                              .instance
                                              .currentUserId) {
                                        return;
                                      }
                                      PendingOffer.select(
                                        PendingOffer(
                                          '',
                                          widget.branchId ??
                                              (b.branchIds.length == 1
                                                  ? b.branchIds.single
                                                  : ''),
                                          {
                                            'source': 'platform',
                                            'id': b.id,
                                            'title': b.title,
                                            'type': b.kind,
                                            'benefit': true,
                                          },
                                          b.endAt,
                                        ),
                                      );
                                      Navigator.of(context).pop(true);
                                    },
                            child: Text(text('استخدم العرض', 'Use benefit')),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _reason(String? reason) => switch (reason) {
    'BENEFIT_EXHAUSTED' => 'اكتملت استخدامات هذه المنفعة',
    'BENEFIT_PAUSED' => 'العرض متوقف مؤقتاً',
    'BENEFIT_EXPIRED' => 'العرض غير سارٍ الآن',
    _ => 'المنفعة غير متاحة لهذا الطلب',
  };
}
