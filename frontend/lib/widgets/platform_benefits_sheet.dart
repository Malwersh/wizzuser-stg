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
    final canUse =
        ApiConfig.commercialPricingEnabled && ApiConfig.deliveryQuotesEnabled;
    return FutureBuilder<List<PlatformBenefit>>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text(
                    'تعذر تحميل مزاياك. تحقق من تسجيل الدخول والاتصال.',
                    'Unable to load benefits. Check your sign-in and connection.',
                  ),
                ),
                TextButton(
                  onPressed: () => setState(reload),
                  child: Text(text('إعادة المحاولة', 'Retry')),
                ),
              ],
            ),
          );
        final items = snapshot.data ?? [];
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.grey.shade300,
              ),
            ),
            Text(
              text('مزاياك من ويز', 'Your Wizz benefits'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                text(
                  'لا توجد مزايا متاحة لحسابك وعنوانك حالياً.',
                  'No benefits are available for this account and address.',
                ),
              ),
            for (final b in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (b.description.isNotEmpty) Text(b.description),
                      const SizedBox(height: 8),
                      Text(
                        b.kind == 'FREE_DELIVERIES'
                            ? text(
                              'متبقي ${b.remaining} توصيلات مجانية',
                              '${b.remaining} free deliveries remaining',
                            )
                            : text(
                              'خصم حتى ${b.amountIqd} د.ع ${b.isDelivery ? 'على التوصيل' : 'على المنتجات'}',
                              'Up to ${b.amountIqd} IQD off ${b.isDelivery ? 'delivery' : 'goods'}',
                            ),
                      ),
                      Text(
                        text(
                          'متاح: ${b.remaining} • قيد الاستخدام: ${b.reserved} • مستخدم: ${b.used}',
                          'Available: ${b.remaining} • In progress: ${b.reserved} • Used: ${b.used}',
                        ),
                      ),
                      Text(
                        text(
                          'الحد الأدنى للمنتجات: ${b.minimumGoodsIqd} د.ع',
                          'Minimum goods: ${b.minimumGoodsIqd} IQD',
                        ),
                      ),
                      if (b.isDelivery)
                        Text(
                          text(
                            'ضمن ${(b.maximumRoadMeters / 1000).toStringAsFixed(1)} كم • سقف الدعم ${b.maximumPerOrderIqd} د.ع',
                            'Within ${(b.maximumRoadMeters / 1000).toStringAsFixed(1)} km • Support cap ${b.maximumPerOrderIqd} IQD',
                          ),
                        ),
                      if (b.kind == 'GOODS_AMOUNT')
                        Text(
                          text(
                            'للطلب الواحد، ولا يُرحّل أي مبلغ غير مستخدم.',
                            'One order only. Any unused amount does not carry over.',
                          ),
                        ),
                      if (b.branchIds.isNotEmpty)
                        Text(
                          text(
                            'لدى المطاعم المشمولة فقط',
                            'Participating restaurants only',
                          ),
                        ),
                      Text(
                        text(
                          'يبدأ: ${b.startAt.toLocal().toString().substring(0, 16)}',
                          'Starts: ${b.startAt.toLocal().toString().substring(0, 16)}',
                        ),
                      ),
                      Text(
                        text(
                          'ينتهي: ${b.endAt.toLocal().toString().substring(0, 16)}',
                          'Expires: ${b.endAt.toLocal().toString().substring(0, 16)}',
                        ),
                      ),
                      if (!b.eligible)
                        Text(
                          text(
                            b.startAt.isAfter(DateTime.now())
                                ? 'لم يبدأ العرض بعد'
                                : _reason(b.reason),
                            'This benefit is currently unavailable.',
                          ),
                          style: const TextStyle(color: Colors.orange),
                        ),
                      FilledButton(
                        onPressed:
                            !canUse || !b.eligible || b.remaining == 0
                                ? null
                                : () {
                                  if (account !=
                                      SessionService.instance.currentUserId)
                                    return;
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
              ),
          ],
        );
      },
    );
  }

  String _reason(String? reason) => switch (reason) {
    'BENEFIT_EXHAUSTED' => 'اكتملت استخدامات هذه المنفعة',
    'BENEFIT_PAUSED' => 'العرض متوقف مؤقتاً',
    'BENEFIT_EXPIRED' => 'العرض غير سارٍ الآن',
    _ => 'المنفعة غير متاحة لهذا الطلب',
  };
}
