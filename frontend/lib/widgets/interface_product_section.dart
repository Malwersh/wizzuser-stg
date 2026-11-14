import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/interface_layout.dart';
import 'restaurant_menu_components.dart';

class InterfaceProductSection extends StatelessWidget {
  final InterfaceSection section;
  final List<ProductModel> products;
  final bool Function(ProductModel) available;
  final String? Function(ProductModel) reason;
  final void Function(ProductModel) onOpen, onAdd;
  const InterfaceProductSection({
    super.key,
    required this.section,
    required this.products,
    required this.available,
    required this.reason,
    required this.onOpen,
    required this.onAdd,
  });
  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    Widget card(ProductModel p) => RestaurantProductCard(
      product: p,
      available: available(p),
      unavailableReason: reason(p),
      onDetails: () => onOpen(p),
      onAdd: () => onAdd(p),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF00296B),
            ),
          ),
          if (section.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                section.description,
                style: const TextStyle(fontSize: 12, color: Color(0xFF647184)),
              ),
            ),
          const SizedBox(height: 12),
          if (section.layout == 'horizontal')
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < products.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    SizedBox(width: 165, child: card(products[i])),
                  ],
                ],
              ),
            )
          else if (section.layout == 'vertical')
            ...products.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RestaurantMenuTile(
                  product: p,
                  available: available(p),
                  unavailableReason: reason(p),
                  onDetails: () => onOpen(p),
                  onAdd: () => onAdd(p),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (_, c) {
                final width = (c.maxWidth - 14) / 2;
                return Wrap(
                  spacing: 14,
                  runSpacing: 18,
                  children:
                      products
                          .map((p) => SizedBox(width: width, child: card(p)))
                          .toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}
