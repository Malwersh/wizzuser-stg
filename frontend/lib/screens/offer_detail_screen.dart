import 'package:flutter/material.dart';
import '../models/home_slide.dart';
import '../services/home_slideshow_service.dart';
import '../services/pending_offer.dart';
import '../services/session_service.dart';
import '../services/delivery_address_manager.dart';

Future<void> showOfferSheet(
  BuildContext context, {
  required HomeSlide slide,
  required Future<void> Function(String) openMerchant,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  clipBehavior: Clip.antiAlias,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder:
      (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .88,
        minChildSize: .5,
        maxChildSize: .96,
        builder:
            (_, controller) => OfferDetailScreen(
              slide: slide,
              openMerchant: openMerchant,
              scrollController: controller,
            ),
      ),
);

class OfferDetailScreen extends StatefulWidget {
  final HomeSlide slide;
  final Future<void> Function(String merchantId) openMerchant;
  final ScrollController? scrollController;
  const OfferDetailScreen({
    super.key,
    required this.slide,
    required this.openMerchant,
    this.scrollController,
  });
  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  final _service = HomeSlideshowService();
  Map<String, dynamic>? data;
  String? merchant, error, scope;
  bool busy = false;
  int request = 0;
  String contextKey() =>
      '${SessionService.instance.currentUserId}|${DeliveryAddressManager.instance.activeAddress?.regionId}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({String? merchantId}) async {
    final n = ++request, context = contextKey();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await _service.details(
        widget.slide.id,
        standalone: widget.slide.standalone,
        merchantId: merchantId,
      );
      if (!mounted || n != request) return;
      if (context != contextKey())
        throw StateError('تغير الحساب أو العنوان، يرجى تحديث العرض');
      setState(() {
        data = result;
        merchant = merchantId;
        scope = context;
      });
    } catch (e) {
      if (mounted && n == request)
        setState(
          () =>
              error =
                  'تعذر تحميل العرض. قد يكون انتهى أو لا ينطبق على حسابك أو عنوانك.',
        );
    } finally {
      if (mounted && n == request) setState(() => busy = false);
    }
  }

  String _date(dynamic value) {
    final d = DateTime.tryParse(value.toString())?.toLocal();
    return d == null ? '—' : '${d.day}/${d.month}/${d.year}';
  }

  Widget _term(IconData icon, String label, String value) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final offer = data?['offer'] as Map?;
    final merchants = data?['merchants'] as List? ?? [];
    final products = data?['products'] as List? ?? [];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Center(
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body:
          busy
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => load(merchantId: merchant),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              )
              : offer == null
              ? const SizedBox.shrink()
              : ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(
                      (offer['imageUrl'] as String?)?.isNotEmpty == true
                          ? offer['imageUrl'] as String
                          : widget.slide.imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, _, _) => const SizedBox(
                            height: 160,
                            child: Center(
                              child: Icon(Icons.local_offer_outlined, size: 72),
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    offer['title'] ?? widget.slide.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(offer['description'] ?? ''),
                  const SizedBox(height: 12),
                  Text(
                    offer['type'] == 'percentage'
                        ? 'خصم ${offer['value']}%'
                        : offer['type'] == 'freeDelivery'
                        ? 'توصيل مجاني'
                        : 'خصم ${offer['value']} د.ع',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _term(
                        Icons.shopping_bag_outlined,
                        'الحد الأدنى',
                        '${offer['minimumOrder'] ?? 0} د.ع',
                      ),
                      if (offer['maximumSavings'] != null)
                        _term(
                          Icons.savings_outlined,
                          'أقصى توفير',
                          '${offer['maximumSavings']} د.ع',
                        ),
                      _term(
                        Icons.calendar_month_outlined,
                        'صالح حتى',
                        _date(offer['endAt']),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  for (final condition in offer['conditions'] as List? ?? [])
                    Text(condition.toString()),
                  if (offer['firstOrderOnly'] == true)
                    const Text('لأول طلب فقط'),
                  if (offer['perCustomerLimit'] != null)
                    Text(
                      'عدد الاستخدامات لكل عميل: ${offer['perCustomerLimit']}',
                    ),
                  if (offer['applicability'] == 'specificItems' ||
                      offer['applicability'] == 'specificCategories')
                    const Text(
                      'الخصم على المنتجات المشمولة فقط. باقي المنتجات بسعرها المعتاد.',
                    ),
                  const Text(
                    'يتم التحقق من الأهلية وحساب الخصم النهائي عند إتمام الطلب. لا يجمع مع عرض آخر.',
                  ),
                  const Divider(height: 32),
                  const Text('اختر المتجر لعرض المنتجات المشمولة'),
                  for (final m in merchants)
                    ListTile(
                      title: Text(m['name']),
                      selected: merchant == m['id'],
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => load(merchantId: m['id']),
                    ),
                  if (merchants.isEmpty)
                    const Text('لا توجد متاجر متاحة لهذا العنوان حالياً.'),
                  if (merchant != null) ...[
                    const Divider(),
                    const Text('المنتجات المشمولة'),
                    if (products.isEmpty)
                      const Text('لا توجد منتجات متاحة لهذا العرض حالياً.'),
                    for (final p in products)
                      ListTile(
                        title: Text(p['name']),
                        subtitle: Text('${p['price']} د.ع قبل الخصم'),
                      ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
      bottomNavigationBar:
          merchant != null && offer != null && !busy && error == null
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed:
                        products.isEmpty
                            ? null
                            : () async {
                              if (scope != contextKey() ||
                                  !DateTime.parse(
                                    offer['endAt'],
                                  ).isAfter(DateTime.now())) {
                                await load(merchantId: merchant);
                                return;
                              }
                              PendingOffer.select(
                                PendingOffer(
                                  widget.slide.standalone
                                      ? ''
                                      : widget.slide.id,
                                  merchant!,
                                  Map<String, dynamic>.from(offer),
                                  DateTime.parse(offer['endAt']),
                                ),
                              );
                              await widget.openMerchant(merchant!);
                            },
                    child: const Text('استخدم العرض وتسوق'),
                  ),
                ),
              )
              : null,
    );
  }
}
