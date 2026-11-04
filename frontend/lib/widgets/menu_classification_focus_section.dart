import 'package:flutter/material.dart';
import '../models/menu_classification_focus.dart';
import '../models/interface_layout.dart';
import '../models/product_model.dart';
import 'interface_product_section.dart';

class MenuClassificationFocusSection extends StatelessWidget {
  final MenuClassificationFocus focus;
  final List<ProductModel> products;
  final VoidCallback onClear;
  final bool Function(ProductModel) available;
  final String? Function(ProductModel) reason;
  final void Function(ProductModel) onOpen, onAdd;
  const MenuClassificationFocusSection({
    super.key,
    required this.focus,
    required this.products,
    required this.onClear,
    required this.available,
    required this.reason,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'اختيارك من الرئيسية',
                style: TextStyle(fontSize: 12, color: Color(0xFF647184)),
              ),
            ),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00296B),
              ),
              child: const Text('تصفّح القائمة كاملة'),
            ),
          ],
        ),
      ),
      if (products.isNotEmpty)
        InterfaceProductSection(
          section: InterfaceSection.fromJson({
            'id': 'navigation-classification',
            'title': focus.label,
            'source': 'curated',
            'layout': 'horizontal',
          }),
          products: products,
          available: available,
          reason: reason,
          onOpen: onOpen,
          onAdd: onAdd,
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Text(
            'لم تُربط أصناف بتصنيف «${focus.label}» في القائمة المنشورة حاليًا. يمكنك تصفح المنيو كاملًا أدناه.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Color(0xFF647184),
            ),
          ),
        ),
    ],
  );
}
