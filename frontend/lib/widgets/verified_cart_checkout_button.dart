import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/storefront_pricing.dart';

/// Checkout advances only after the current account/address/basket is priced.
class VerifiedCartCheckoutButton extends StatefulWidget {
  final String branchId;
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final StorefrontPricing pricing;
  final VoidCallback onVerified;
  const VerifiedCartCheckoutButton({
    super.key,
    required this.branchId,
    required this.items,
    required this.subtotal,
    required this.pricing,
    required this.onVerified,
  });
  @override
  State<VerifiedCartCheckoutButton> createState() =>
      _VerifiedCartCheckoutButtonState();
}

class _VerifiedCartCheckoutButtonState
    extends State<VerifiedCartCheckoutButton> {
  bool _checking = false;
  Future<void> _continue() async {
    if (_checking) return;
    final key = widget.pricing.key(widget.branchId, widget.items);
    setState(() => _checking = true);
    try {
      final preview = await widget.pricing.load(widget.branchId, widget.items);
      if (!mounted) return;
      if (key != widget.pricing.key(widget.branchId, widget.items)) {
        _message('تغيرت السلة أو عنوان التوصيل. تحقق من التفاصيل مجددًا.');
        return;
      }
      if (preview == null) {
        _message(
          widget.pricing.error(widget.branchId, widget.items) ??
              'تعذر التحقق من تفاصيل الطلب. تحقق من الحساب والعنوان ثم أعد المحاولة.',
        );
        return;
      }
      final minimum = preview.minimumOrderAmountIqd ?? 0;
      final gross = preview.data['goodsGross'];
      final subtotal =
          gross is Map && gross['minorAmount'] is int
              ? (gross['minorAmount'] as int) / 1000
              : widget.subtotal;
      if (subtotal < minimum) {
        _message(
          'الحد الأدنى للطلب $minimum د.ع. أضف ${(minimum - subtotal).ceil()} د.ع إضافية.',
        );
        return;
      }
      widget.onVerified();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), backgroundColor: Colors.amber.shade800),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.pricing,
    builder: (context, _) {
      final preview = widget.pricing.peek(widget.branchId, widget.items);
      final minimum = preview?.minimumOrderAmountIqd ?? 0;
      final remaining = minimum - widget.subtotal;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (preview != null && remaining > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'الحد الأدنى للطلب $minimum د.ع. أضف ${remaining.ceil()} د.ع إضافية.',
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _checking ? null : _continue,
                  child:
                      _checking
                          ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('جارٍ التحقق من تفاصيل الطلب…'),
                            ],
                          )
                          : Text(
                            preview == null
                                ? 'التحقق من تفاصيل الطلب'
                                : remaining > 0
                                ? 'أضف ${remaining.ceil()} د.ع للمتابعة'
                                : 'متابعة الطلب',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
