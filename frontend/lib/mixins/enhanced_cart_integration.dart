import '../utils/readable_colors.dart';
import '../utils/currency_format.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/app_state_provider.dart';
import '../providers/improved_app_providers.dart';
import '../services/session_service.dart';

/// Enhanced Cart Integration Mixin for Store Detail Screen
/// Provides unified cart operations for both legacy and new systems
mixin EnhancedCartIntegration<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool _useNewSystem = false;

  /// Initialize cart integration
  Future<void> initializeCartIntegration() async {
    try {
      // Check if session is valid
      final sessionService = SessionService.instance;
      final isValid = sessionService.isLoggedIn || sessionService.isGuest;

      // Check if new system is available and initialized
      final authState = ref.read(authStateProvider);
      final cartState = ref.read(cartStateProvider);

      _useNewSystem = !authState.isLoading && !cartState.isLoading && isValid;
    } catch (e) {
      debugPrint('Cart integration initialization failed: $e');
      _useNewSystem = false;
    }
  }

  /// Get cart items count for a specific store
  int getCartItemsCountForStore(String storeId) {
    if (_useNewSystem) {
      final cartState = ref.watch(cartStateProvider);
      // Filter items by store ID and count them
      final storeItems =
          cartState.items.where((item) => item['store_id'] == storeId).toList();
      return storeItems.length;
    } else {
      final legacyProvider = provider.Provider.of<AppStateProvider>(
        context,
        listen: false,
      );
      return legacyProvider.getCartItemsForStore(storeId).length;
    }
  }

  /// Check if cart has items for a specific store
  bool hasCartItemsForStore(String storeId) {
    if (_useNewSystem) {
      final cartState = ref.watch(cartStateProvider);
      final storeItems =
          cartState.items.where((item) => item['store_id'] == storeId).toList();
      return storeItems.isNotEmpty;
    } else {
      final legacyProvider = provider.Provider.of<AppStateProvider>(
        context,
        listen: false,
      );
      return legacyProvider.hasCartItemsForStore(storeId);
    }
  }

  /// Get cart total for a specific store
  double getCartTotalForStore(String storeId) {
    if (_useNewSystem) {
      final cartState = ref.watch(cartStateProvider);
      // Calculate total for items from this store
      final storeItems =
          cartState.items.where((item) => item['store_id'] == storeId).toList();
      return storeItems.fold<double>(0.0, (total, item) {
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
        return total + (price * quantity);
      });
    } else {
      final legacyProvider = provider.Provider.of<AppStateProvider>(
        context,
        listen: false,
      );
      return legacyProvider.getCartTotalForStore(storeId);
    }
  }

  /// Add item to cart with enhanced validation
  Future<bool> addItemToCart({
    required String dishId,
    required String name,
    required double price,
    int quantity = 1,
    required String storeId,
    required String storeName,
    Map<String, dynamic>? extras,
  }) async {
    try {
      if (_useNewSystem) {
        // Check store validation in new system
        final cartState = ref.read(cartStateProvider);
        final currentStoreItems =
            cartState.items
                .where((item) => item['store_id'] != storeId)
                .toList();

        if (currentStoreItems.isNotEmpty) {
          // Show store change dialog
          final shouldChange = await _showStoreChangeDialog(
            storeName,
            'المطعم الحالي',
          );
          if (!shouldChange) return false;

          // Clear cart and switch store
          await ref.read(cartStateProvider.notifier).clearCart();
        }

        // Create cart item map in the format expected by addItem
        final cartItem = {
          'dish_id': dishId,
          'id': dishId,
          'name': name,
          'price': price,
          'quantity': quantity,
          'store_id': storeId,
          'store_name': storeName,
          'extras': extras ?? {},
        };

        await ref.read(cartStateProvider.notifier).addItem(cartItem);
        return true;
      } else {
        final legacyProvider = provider.Provider.of<AppStateProvider>(
          context,
          listen: false,
        );

        // Create cart item map for legacy provider
        final cartItem = {
          'dish_id': dishId,
          'id': dishId,
          'name': name,
          'price': price,
          'quantity': quantity,
          'store_id': storeId,
          'store_name': storeName,
          'extras': extras ?? {},
        };

        await legacyProvider.addToCart(cartItem);
        return true;
      }
    } catch (e) {
      debugPrint('Error adding item to cart: $e');
      return false;
    }
  }

  /// Remove item from cart
  Future<bool> removeItemFromCart(String dishId) async {
    try {
      if (_useNewSystem) {
        final cartState = ref.read(cartStateProvider);
        // Find the index of the item to remove
        final itemIndex = cartState.items.indexWhere(
          (item) => item['dish_id'] == dishId || item['id'] == dishId,
        );
        if (itemIndex >= 0) {
          await ref.read(cartStateProvider.notifier).removeItem(itemIndex);
        }
        return true;
      } else {
        final legacyProvider = provider.Provider.of<AppStateProvider>(
          context,
          listen: false,
        );
        // Find the item to remove in legacy provider
        final itemIndex = legacyProvider.cartItems.indexWhere(
          (item) => item['dish_id'] == dishId || item['id'] == dishId,
        );
        if (itemIndex >= 0) {
          final item = legacyProvider.cartItems[itemIndex];
          final itemId = item['id']?.toString() ?? dishId.toString();
          await legacyProvider.removeFromCart(itemId);
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error removing item from cart: $e');
      return false;
    }
  }

  /// Clear cart for current store
  Future<bool> clearStoreCart() async {
    try {
      if (_useNewSystem) {
        await ref.read(cartStateProvider.notifier).clearCart();
        return true;
      } else {
        final legacyProvider = provider.Provider.of<AppStateProvider>(
          context,
          listen: false,
        );
        await legacyProvider.clearCart();
        return true;
      }
    } catch (e) {
      debugPrint('Error clearing cart: $e');
      return false;
    }
  }

  /// Show store change confirmation dialog
  Future<bool> _showStoreChangeDialog(
    String newStoreName,
    String currentStoreName,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('تغيير المطعم'),
                content: Text(
                  'لديك عناصر في السلة من "$currentStoreName". '
                  'هل تريد حذف العناصر الحالية والتبديل إلى "$newStoreName"؟',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: readableForeground(AppColors.primary),
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'تأكيد',
                      style: TextStyle(color: const Color(0xFF00296B)),
                    ),
                  ),
                ],
              ),
        ) ??
        false;
  }

  /// Get current system status
  String getCurrentSystemStatus() {
    return _useNewSystem ? 'New System' : 'Legacy System';
  }

  /// Force system switch for testing
  void setUseNewSystem(bool useNew) {
    setState(() {
      _useNewSystem = useNew;
    });
  }

  /// Watch cart state changes
  Widget buildCartStateConsumer({
    required Widget Function(bool hasItems, int itemCount, double total)
    builder,
  }) {
    if (_useNewSystem) {
      return Consumer(
        builder: (context, ref, child) {
          final cartState = ref.watch(cartStateProvider);
          return builder(
            cartState.items.isNotEmpty,
            cartState.items.length,
            cartState.total,
          );
        },
      );
    } else {
      return provider.Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          return builder(
            appState.cartItems.isNotEmpty,
            appState.cartItemsCount,
            appState.cartTotal,
          );
        },
      );
    }
  }

  @override
  void dispose() {
    // Clean up resources if needed
    super.dispose();
  }
}

/// Enhanced Store Detail Screen with Cart Integration
class EnhancedStoreDetailWrapper extends ConsumerWidget {
  final Widget child;
  final String storeId;
  final String storeName;

  const EnhancedStoreDetailWrapper({
    super.key,
    required this.child,
    required this.storeId,
    required this.storeName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        child,
        // Cart bar overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Consumer(
            builder: (context, ref, _) {
              final cartState = ref.watch(cartStateProvider);

              // Check if cart has items for this store
              final storeItems =
                  cartState.items
                      .where((item) => item['store_id'] == storeId)
                      .toList();

              if (storeItems.isEmpty) {
                return const SizedBox.shrink();
              }

              final storeTotal = storeItems.fold<double>(0.0, (total, item) {
                final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                return total + (price * quantity);
              });

              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${storeItems.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'السلة - $storeName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${formatIqd(storeTotal)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Navigate to cart/checkout
                        Navigator.pushNamed(context, '/cart');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('عرض السلة'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
