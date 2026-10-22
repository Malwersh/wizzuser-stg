import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storefront_pricing.dart';

enum StorefrontField { fee, preparation, arrival, distance }

class StorefrontValue extends StatefulWidget {
  final String branchId;
  final StorefrontField field;
  final List<dynamic>? items;
  final TextStyle? style;
  final bool hasGoodsDiscount;
  final int? initialPreparationMinutes;
  final StorefrontPricing? pricing;
  final Duration requestDebounce;
  const StorefrontValue({
    super.key,
    required this.branchId,
    required this.field,
    this.items,
    this.style,
    this.hasGoodsDiscount = false,
    this.initialPreparationMinutes,
    this.pricing,
    this.requestDebounce = Duration.zero,
  });
  @override
  State<StorefrontValue> createState() => _StorefrontValueState();
}

class _StorefrontValueState extends State<StorefrontValue> {
  late final pricing = widget.pricing ?? StorefrontPricing.instance;
  String? _requested;
  bool _loading = false;
  Timer? _requestTimer;
  @override
  void initState() {
    super.initState();
    pricing.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _requestTimer?.cancel();
    pricing.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items =
        widget.items ??
        context
            .watch<AppStateProvider>()
            .cartItems
            .where((item) => item['store_id'] == widget.branchId)
            .toList();
    final key = pricing.key(
      widget.branchId,
      items,
      hasGoodsDiscount: widget.hasGoodsDiscount,
    );
    final p = pricing.peek(
          widget.branchId,
          items,
          hasGoodsDiscount: widget.hasGoodsDiscount,
        ),
        error = pricing.error(
          widget.branchId,
          items,
          hasGoodsDiscount: widget.hasGoodsDiscount,
        );
    if (key != _requested ||
        (p == null && error == null && !_loading && key != null)) {
      _requested = key;
      _requestTimer?.cancel();
      _loading = key != null;
      if (key != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _requested != key) return;
          _requestTimer = Timer(widget.requestDebounce, () {
            if (!mounted || _requested != key) return;
            unawaited(
              pricing
                  .load(
                    widget.branchId,
                    items,
                    hasGoodsDiscount: widget.hasGoodsDiscount,
                  )
                  .whenComplete(() {
                    if (mounted && _requested == key)
                      setState(() => _loading = false);
                  }),
            );
          });
        });
      }
    }

    String text = key == null ? 'اختر عنوان التوصيل' : '—';
    if (widget.field == StorefrontField.preparation &&
        widget.initialPreparationMinutes != null)
      text = 'نحو ${widget.initialPreparationMinutes} دقيقة';
    final display = p ?? pricing.peekRoute(widget.branchId);
    if (display != null) {
      text = switch (widget.field) {
        StorefrontField.fee => p?.feeText ?? text,
        StorefrontField.preparation => display.preparationText,
        StorefrontField.arrival => display.arrivalText,
        StorefrontField.distance => display.distanceText,
      };
    }
    final fee = pricing.feeIqd(
      widget.branchId,
      items,
      hasGoodsDiscount: widget.hasGoodsDiscount,
    );
    if (widget.field == StorefrontField.fee && fee != null)
      text =
          fee == 0
              ? 'توصيل مجاني'
              : '${fee.toStringAsFixed(fee == fee.roundToDouble() ? 0 : 3)} د.ع';
    if (error != null &&
        p == null &&
        !(display != null && widget.field != StorefrontField.fee) &&
        !(widget.field == StorefrontField.fee && fee != null))
      return TextButton(
        onPressed:
            () => pricing.load(
              widget.branchId,
              items,
              hasGoodsDiscount: widget.hasGoodsDiscount,
              force: true,
            ),
        child: Text('إعادة حساب التوصيل', style: widget.style),
      );
    return Text(
      text,
      style: widget.style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Takes no space when the branch has no configured minimum.
class StorefrontMinimum extends StatelessWidget {
  final String branchId;
  const StorefrontMinimum({super.key, required this.branchId});
  @override
  Widget build(BuildContext context) {
    final items =
        context
            .watch<AppStateProvider>()
            .cartItems
            .where((item) => item['store_id'] == branchId)
            .toList();
    return ListenableBuilder(
      listenable: StorefrontPricing.instance,
      builder: (context, _) {
        final minimum = StorefrontPricing.instance.minimumIqd(branchId, items);
        if (minimum == null) return const SizedBox.shrink();
        return Expanded(
          child: Column(
            children: [
              const Text(
                'الحد الأدنى',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text('$minimum د.ع', style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}
