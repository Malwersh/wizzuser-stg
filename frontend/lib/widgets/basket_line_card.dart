import 'menu_item_price.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import '../models/cart_item.dart';

String basketMoney(num amount) =>
    '${NumberFormat('#,##0.###', 'en').format(amount)} د.ع';

class BasketLineCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback increase, decrease, remove;
  const BasketLineCard({
    super.key,
    required this.item,
    required this.increase,
    required this.decrease,
    required this.remove,
  });
  @override
  Widget build(BuildContext context) {
    final image = item.dish.imageUrls.firstOrNull ?? '';
    final ids = item.selectedOptions.values.expand((v) => v).toList();
    final options = {
      for (final group in item.dish.optionGroups)
        for (final option in group.options) option.id: option.name,
    };
    final names =
        ids.where(options.containsKey).map((id) => options[id]!).toList();
    final choices =
        names.length == ids.length
            ? names.join('، ')
            : ids.isEmpty
            ? ''
            : 'إضافات مختارة (${ids.length})';
    Widget placeholder() => Container(
      color: const Color(0xfff1f5fa),
      child: const Icon(Icons.restaurant_rounded, color: AppColors.secondary),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffe3eaf2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child:
                      image.startsWith('https://') ||
                              image.startsWith('http://')
                          ? Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => placeholder(),
                          )
                          : placeholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.dish.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (ids.isEmpty)
                      MenuItemPrice(
                        branch: item.storeId,
                        product: item.dish.id,
                        original: item.unitPrice,
                        basket: true,
                      )
                    else
                      Text(
                        '${basketMoney(item.unitPrice)} للقطعة',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    if (choices.isNotEmpty)
                      Text(
                        choices,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    if (item.specialInstructions?.trim().isNotEmpty == true)
                      Text(
                        item.specialInstructions!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'حذف ${item.dish.name}',
                onPressed: remove,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xfff1f5fa),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'زيادة كمية ${item.dish.name}',
                      onPressed: increase,
                      icon: const Icon(
                        Icons.add_rounded,
                        color: AppColors.secondary,
                      ),
                    ),
                    Semantics(
                      liveRegion: true,
                      child: SizedBox(
                        width: 32,
                        child: Text(
                          '${item.quantity}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'تقليل كمية ${item.dish.name}',
                      onPressed: item.quantity > 1 ? decrease : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    ids.isEmpty
                        ? MenuItemPrice(
                          branch: item.storeId,
                          product: item.dish.id,
                          original: item.unitPrice,
                          quantity: item.quantity,
                          basket: true,
                        )
                        : Text(
                          basketMoney(item.totalPrice),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondaryDark,
                          ),
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
