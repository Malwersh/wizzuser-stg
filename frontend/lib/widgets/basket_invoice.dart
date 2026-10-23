import '../config/api_config.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/checkout_invoice_store.dart';
import '../services/delivery_address_manager.dart';
import '../services/session_service.dart';
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
        CheckoutInvoiceStore.instance.warmBasket(
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
  const BasketInvoiceDelivery({
    super.key,
    required this.branch,
    required this.items,
    required this.fallback,
    this.store,
  });
  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.commercialPricingEnabled) return fallback;
    final source = store ?? CheckoutInvoiceStore.instance;
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final request = source.basketRequest(branch, items);
        final invoice = request == null ? null : source.peek(request);
        return invoice == null
            ? Text(
              request == null ? 'اختر عنوان التوصيل' : 'تُحدّد مع الفاتورة',
              style: const TextStyle(color: AppColors.textSecondary),
            )
            : Text(
              basketMoney(
                (invoice.proposal['deliveryFee']['minorAmount'] as num) / 1000,
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            );
      },
    );
  }
}
