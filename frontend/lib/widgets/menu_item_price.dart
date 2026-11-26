import 'package:flutter/material.dart';
import '../services/menu_offer_pricing.dart';
import 'package:intl/intl.dart';

String _money(num v) => '${NumberFormat('#,##0.###', 'en').format(v)} د.ع';

class MenuItemPrice extends StatelessWidget {
  final String branch, product;
  final num original;
  final int quantity;
  final bool basket;
  const MenuItemPrice({
    super.key,
    required this.branch,
    required this.product,
    required this.original,
    this.quantity = 1,
    this.basket = false,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: MenuOfferPricing.instance,
    builder: (context, _) {
      final p = MenuOfferPricing.instance.price(
        branch,
        product,
        original,
        basket: basket,
      );
      if (p == null)
        return Text(
          _money(original * quantity),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF00296B),
          ),
        );
      return Wrap(
        spacing: 7,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _money(p.unit.netFils / 1000 * quantity),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF087345),
            ),
          ),
          Text(
            _money(original * quantity),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF647184),
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      );
    },
  );
}
