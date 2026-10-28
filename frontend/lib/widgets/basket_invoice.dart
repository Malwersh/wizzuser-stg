import '../services/point_invoice_321.dart';
import '../services/browsing_location_service.dart';
import '../config/api_config.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/checkout_invoice_store.dart';
import '../services/delivery_address_manager.dart';
import '../services/session_service.dart';
import '../services/storefront_pricing.dart';
import 'basket_line_card.dart' show basketMoney;

/// Prepares only the current basket while its screen is visible. The same
/// scoped result is consumed by cart, checkout and final review.
class BasketInvoiceWarmup extends StatefulWidget {
  final String branch, storeName;
  final List<Map<String, dynamic>> items;
  final Widget child;
  const BasketInvoiceWarmup({
    super.key,
    required this.branch,
    required this.items,
    required this.child,
    this.storeName = 'المطعم',
  });
  @override
  State<BasketInvoiceWarmup> createState() => _BasketInvoiceWarmupState();
}

class _BasketInvoiceWarmupState extends State<BasketInvoiceWarmup> {
  Timer? _debounce, _refresh;
  StreamSubscription? _address, _session;
  @override
  void initState() {
    super.initState();
    BrowsingLocationService.instance.addListener(_schedule);
    _address = DeliveryAddressManager.instance.addressStream.listen(
      (_) => _schedule(),
    );
    _session = SessionService.instance.sessionStateStream.listen(
      (_) => _schedule(),
    );
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) => _schedule());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant BasketInvoiceWarmup old) {
    super.didUpdateWidget(old);
    if (old.branch != widget.branch ||
        jsonEncode(old.items) != jsonEncode(widget.items))
      _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
        return;
      unawaited(
        PointInvoice321.instance.warmBasket(
          widget.branch,
          widget.items,
          storeName: widget.storeName,
        ),
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _refresh?.cancel();
    _address?.cancel();
    _session?.cancel();
    BrowsingLocationService.instance.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class BasketInvoiceTotals extends StatelessWidget {
  final String branch, storeName;
  final List<Map<String, dynamic>> items;
  final CheckoutInvoiceStore? store;
  const BasketInvoiceTotals({
    super.key,
    required this.branch,
    required this.items,
    this.storeName = 'المطعم',
    this.store,
  });
  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.commercialPricingEnabled) return const SizedBox.shrink();
    if(store==null){
      final r=PointInvoice321.basketRequest(branch,items,storeName:storeName);
      if(r==null)return const SizedBox.shrink();
      return ListenableBuilder(listenable:PointInvoice321.instance,builder:(context,_){
        final p=PointInvoice321.instance.peek(r);if(p==null)return const SizedBox.shrink();
        return Column(children:[
          Padding(padding:const EdgeInsets.only(top:10),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('رسوم الخدمة'),Text(basketMoney((p['serviceFee']['minorAmount']as num)/1000),style:const TextStyle(color:AppColors.secondary))])),
          Padding(padding:const EdgeInsets.only(top:10),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('المجموع الكلي',style:TextStyle(fontWeight:FontWeight.bold)),Text(basketMoney((p['customerTotal']['minorAmount']as num)/1000),style:const TextStyle(color:AppColors.secondary,fontWeight:FontWeight.bold))])),
        ]);
      });
    }
    final source = store ?? CheckoutInvoiceStore.instance;
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final request = source.basketRequest(
          branch,
          items,
          storeName: storeName,
        );
        if (request == null) return const SizedBox.shrink();
        final invoice = source.peek(request);
        Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: AppColors.secondary,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ],
          ),
        );
        if (invoice != null) {
          final p = invoice.proposal;
          return Column(
            children: [
              row(
                'رسوم الخدمة',
                basketMoney((p['serviceFee']['minorAmount'] as num) / 1000),
              ),
              row(
                'المجموع الكلي',
                basketMoney((p['customerTotal']['minorAmount'] as num) / 1000),
                bold: true,
              ),
            ],
          );
        }
        final error = source.error(request);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  error ?? 'جارٍ تجهيز الفاتورة…',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              if (error != null && !error.startsWith('أكمل'))
                TextButton(
                  onPressed: () => source.ensure(request, retry: true),
                  child: const Text('إعادة المحاولة'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class BasketInvoiceDelivery extends StatelessWidget {
  final String branch;
  final List<Map<String, dynamic>> items;
  final Widget fallback;
  final CheckoutInvoiceStore? store;
  final StorefrontPricing? pricing;
  const BasketInvoiceDelivery({
    super.key,
    required this.branch,
    required this.items,
    required this.fallback,
    this.store,
    this.pricing,
  });
  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.commercialPricingEnabled) return fallback;
    final source = store ?? CheckoutInvoiceStore.instance;
    final display = pricing ?? StorefrontPricing.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([source, display,PointInvoice321.instance]),
      builder: (context, _) {
        final request = source.basketRequest(branch, items);
        final invoice = request == null ? null : source.peek(request);
        final pointRequest=store==null?PointInvoice321.basketRequest(branch,items):null;
        final proposal=(pointRequest==null?null:PointInvoice321.instance.peek(pointRequest))??invoice?.proposal;
        final cachedFee = request == null ? display.browsingPointFeeIqd(branch, items) : display.cachedDisplayFeeIqd(branch, items);
        return proposal == null
            ? Text(
              request == null ? (cachedFee!=null?basketMoney(cachedFee):'يُحسب بعد إكمال عنوان التوصيل') :
                  cachedFee != null ? '${basketMoney(cachedFee)} (تقديري)' : 'بانتظار سعر التوصيل',
              style: const TextStyle(color: AppColors.textSecondary),
            )
            : Text(
              basketMoney(
                (proposal['deliveryFee']['minorAmount'] as num) / 1000,
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            );
      },
    );
  }
}
