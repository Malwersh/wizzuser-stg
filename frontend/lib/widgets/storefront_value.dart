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
  const StorefrontValue({
    super.key,
    required this.branchId,
    required this.field,
    this.items,
    this.style,
    this.hasGoodsDiscount = false,
    this.initialPreparationMinutes,
  });
  @override
  State<StorefrontValue> createState() => _StorefrontValueState();
}

class _StorefrontValueState extends State<StorefrontValue> {
  final pricing = StorefrontPricing.instance;
  String? _requested;
  bool _loading = false;
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
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          unawaited(
            pricing
                .load(
                  widget.branchId,
                  items,
                  hasGoodsDiscount: widget.hasGoodsDiscount,
                )
                .whenComplete(() {
                  if (mounted) setState(() => _loading = false);
                }),
          );
      });
    }
    String text = key == null ? 'اختر عنوان التوصيل' : '—';
    if (widget.field == StorefrontField.preparation &&
        widget.initialPreparationMinutes != null)
      text = 'نحو ${widget.initialPreparationMinutes} دقيقة';
    if (p != null) {
      text = switch (widget.field) {
        StorefrontField.fee => p.feeText,
        StorefrontField.preparation => p.preparationText,
        StorefrontField.arrival => p.arrivalText,
        StorefrontField.distance => p.distanceText,
      };
    }
    if (error != null && p == null)
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
        final minimum =
            StorefrontPricing.instance
                .peek(branchId, items)
                ?.minimumOrderAmountIqd;
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
