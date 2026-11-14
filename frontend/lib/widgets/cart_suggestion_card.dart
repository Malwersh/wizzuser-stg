import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/product_model.dart';
import 'menu_item_price.dart';

class CartSuggestionCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onOpen;
  const CartSuggestionCard({
    super.key,
    required this.product,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 150,
                height: 130,
                child:
                    product.imageUrl.startsWith('https://')
                        ? Image.network(
                          product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallback(),
                        )
                        : _fallback(),
              ),
            ),
            PositionedDirectional(
              start: 7,
              bottom: 7,
              child: Material(
                color: Colors.white,
                elevation: 2,
                shadowColor: Colors.black26,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'اختيار ${product.name}',
                  onPressed: onOpen,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(
                    Icons.add,
                    color: AppColors.secondaryDark,
                    size: 25,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryDark,
          ),
        ),
        const SizedBox(height: 5),
        MenuItemPrice(
          branch: product.businessId,
          product: product.id,
          original: product.price,
        ),
      ],
    ),
  );
  Widget _fallback() => const ColoredBox(
    color: Color(0xfff1f4f9),
    child: Center(
      child: Icon(Icons.restaurant, color: AppColors.secondaryDark),
    ),
  );
}
