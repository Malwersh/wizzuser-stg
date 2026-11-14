import 'package:flutter/material.dart';
import '../models/store.dart';
import '../models/favorites_model.dart';
import '../widgets/robust_network_image.dart';
import './store_detail_screen.dart';

class FavoriteStoresScreen extends StatelessWidget {
  final FavoritesModel favoritesModel;
  final List<Store> allStores;

  const FavoriteStoresScreen({
    super.key,
    required this.favoritesModel,
    required this.allStores,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: favoritesModel,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final favoriteStoreIds = favoritesModel.favoriteStoreIds;
    final favoriteRestaurants =
        allStores
            .where((store) => favoriteStoreIds.contains(store.id))
            .toList();

    const navy = Color(0xFF00296B);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text(
            'المفضلة',
            style: TextStyle(color: navy, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: navy),
        ),
        body:
            favoriteRestaurants.isEmpty
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: Color(0xFFE9EEF7),
                          child: Icon(
                            Icons.favorite_border_rounded,
                            size: 42,
                            color: navy,
                          ),
                        ),
                        SizedBox(height: 24),
                        Text(
                          'احتفظ بأماكنك المفضلة',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: navy,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'اضغط على القلب بجانب أي مطعم أو متجر لتجده هنا.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF748198),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  itemCount: favoriteRestaurants.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final store = favoriteRestaurants[index];
                    final category = switch (store.category?.toLowerCase()) {
                      'restaurant' => 'مطعم',
                      'store' || 'grocery' || 'market' => 'متجر',
                      'cafe' || 'coffee' => 'مقهى',
                      _ => store.category ?? 'مطعم',
                    };
                    return Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: const BorderSide(color: Color(0xFFE5EAF2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StoreDetailScreen(store: store),
                              ),
                            ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(17),
                                child: SizedBox(
                                  width: 88,
                                  height: 88,
                                  child:
                                      store.image.isNotEmpty
                                          ? RobustNetworkImage(
                                            imageUrl: store.image,
                                            fit: BoxFit.cover,
                                          )
                                          : const ColoredBox(
                                            color: Color(0xFFE9EEF7),
                                            child: Icon(
                                              Icons.storefront_outlined,
                                              color: navy,
                                              size: 32,
                                            ),
                                          ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      store.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: navy,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF748198),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _getRestaurantStatusText(store),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _getRestaurantStatusColor(store),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'إزالة من المفضلة',
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFF0F3F8),
                                ),
                                icon: const Icon(
                                  Icons.favorite_rounded,
                                  color: navy,
                                  size: 24,
                                ),
                                onPressed: () async {
                                  await favoritesModel.toggleStoreFavorite(
                                    store.id,
                                    store.name,
                                    storeImage: store.image,
                                    storeCategory: store.category,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }

  Color _getRestaurantStatusColor(Store store) {
    // Check comprehensive restaurant availability status
    if (store.isOpen &&
        store.acceptingOrders &&
        store.isOnline &&
        !store.isBusy) {
      return Colors.green; // Available for orders
    } else if (!store.acceptingOrders) {
      return Colors.orange; // Not accepting orders
    } else if (!store.isOnline) {
      return Colors.red; // Offline
    } else if (store.isBusy) {
      return Colors.amber; // Busy
    } else if (!store.isOpen) {
      return Colors.grey; // Closed
    } else {
      return Colors.grey; // Default
    }
  }

  String _getRestaurantStatusText(Store store) {
    // Check comprehensive restaurant availability status
    if (store.isOpen &&
        store.acceptingOrders &&
        store.isOnline &&
        !store.isBusy) {
      return 'متاح للطلب';
    } else if (!store.acceptingOrders) {
      return 'لا يقبل طلبات';
    } else if (!store.isOnline) {
      return 'غير متصل';
    } else if (store.isBusy) {
      return 'مشغول';
    } else if (!store.isOpen) {
      return 'مغلق';
    } else {
      return 'غير متاح';
    }
  }
}
