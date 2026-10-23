import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/platform_benefit.dart';
import '../services/platform_benefits_service.dart';
import '../services/session_service.dart';

/// Selecting here previews a benefit. Reservation happens only at order confirmation.
class CheckoutBenefitsSheet extends StatefulWidget {
  final String branchId;
  final Future<List<PlatformBenefit>> Function()? loader;
  const CheckoutBenefitsSheet({super.key, required this.branchId, this.loader});

  @override
  State<CheckoutBenefitsSheet> createState() => _CheckoutBenefitsSheetState();
}

class _CheckoutBenefitsSheetState extends State<CheckoutBenefitsSheet> {
  final _service = PlatformBenefitsService();
  late Future<List<PlatformBenefit>> _pending;
  late final String? _account;

  @override
  void initState() {
    super.initState();
    _account = SessionService.instance.currentUserId;
    _reload();
  }

  void _reload() {
    _pending =
        widget.loader?.call() ?? _service.load(branchId: widget.branchId);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  String _reason(PlatformBenefit b) => switch (b.reason) {
    'BENEFIT_EXHAUSTED' => 'اكتملت استخدامات هذه الميزة',
    'BENEFIT_WRONG_BRANCH' => 'غير متاحة لهذا المطعم',
    'BENEFIT_WRONG_REGION' => 'عنوان التوصيل غير مشمول',
    'BENEFIT_PAUSED' => 'متوقفة مؤقتًا',
    'BENEFIT_EXPIRED' => 'انتهت مدة الميزة',
    _ => 'غير متاحة لهذا الطلب حاليًا',
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'مزايا المنصة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text(
            'اختر ميزة واحدة لهذا الطلب. نتحقق من شروطها وإجمالي الطلب قبل التأكيد.',
          ),
          const SizedBox(height: 16),
          Flexible(
            child: FutureBuilder<List<PlatformBenefit>>(
              future: _pending,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError ||
                    _account != SessionService.instance.currentUserId) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'تعذر تحميل مزاياك. تحقق من تسجيل الدخول والاتصال ثم أعد المحاولة.',
                      ),
                      TextButton(
                        onPressed: () => setState(_reload),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  );
                }
                final benefits = snapshot.data ?? [];
                if (benefits.isEmpty)
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'لا توجد مزايا متاحة لحسابك في هذا المطعم حاليًا.',
                    ),
                  );
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: benefits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final b = benefits[index];
                    final available =
                        b.eligible &&
                        b.remaining > 0 &&
                        (b.branchIds.isEmpty ||
                            b.branchIds.contains(widget.branchId));
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            b.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (b.description.isNotEmpty) Text(b.description),
                          const SizedBox(height: 8),
                          Text(
                            b.kind == 'FREE_DELIVERIES'
                                ? 'توصيل مجاني حتى ${b.maximumPerOrderIqd} د.ع'
                                : 'خصم ${b.amountIqd} د.ع على ${b.isDelivery ? 'التوصيل' : 'الأصناف'}',
                          ),
                          Text('الحد الأدنى للأصناف: ${b.minimumGoodsIqd} د.ع'),
                          Text('الاستخدامات المتبقية: ${b.remaining}'),
                          if (!available)
                            Text(
                              _reason(b),
                              style: const TextStyle(color: Colors.red),
                            ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.secondary,
                            ),
                            onPressed:
                                available
                                    ? () {
                                      if (_account ==
                                          SessionService.instance.currentUserId)
                                        Navigator.pop(context, b);
                                    }
                                    : null,
                            child: const Text('اختيار الميزة'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
