import 'package:flutter/material.dart';
import '../models/dish_model.dart';

class DishCard extends StatelessWidget {
  final DishModel dish;
  final Function()? onTap;
  final Function()? onAddToCart;
  final bool isCompact;

  const DishCard({
    super.key,
    required this.dish,
    this.onTap,
    this.onAddToCart,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: ListTile(
          title: Text(
            dish.name,
            style: const TextStyle(
              color: Colors.black, // نص أسود واضح لاسم الطبق
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            'Price: ${dish.price.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.black87, // نص أسود مخفف للسعر
            ),
          ),
          trailing: isCompact
              ? null
              : IconButton(
                  icon: Icon(Icons.add_shopping_cart),
                  onPressed: onAddToCart,
                ),
        ),
      ),
    );
  }
}
