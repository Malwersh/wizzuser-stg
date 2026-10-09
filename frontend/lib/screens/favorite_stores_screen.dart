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
  Widget build(BuildContext context) {
    final favoriteStoreIds = favoritesModel.favoriteStoreIds;
    final favoriteRestaurants = allStores
        .where((store) => favoriteStoreIds.contains(store.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المفضلة'),
        centerTitle: true,
      ),
      body: favoriteRestaurants.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.favorite_border, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('لا توجد مطاعم مفضلة',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('اضغط على القلب لإضافة المطاعم المفضلة',
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: favoriteRestaurants.length,
              itemBuilder: (context, index) {
                final store = favoriteRestaurants[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 60,
                            height: 60,
                            child: store.image.isNotEmpty
                                ? RobustNetworkImage(
                                    imageUrl: store.image,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.restaurant, color: Colors.grey),
                                  ),
                          ),
                        ),
                        // Restaurant status indicator
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getRestaurantStatusColor(store),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(store.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.category ?? 'مطعم',
                            style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                        const SizedBox(height: 2),
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
                    trailing: IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.red),
                      onPressed: () async {
                        await favoritesModel.toggleStoreFavorite(
                          store.id,
                          store.name,
                          storeImage: store.image,
                          storeCategory: store.category,
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StoreDetailScreen(
                            store: store,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  Color _getRestaurantStatusColor(Store store) {
    // Check comprehensive restaurant availability status
    if (store.isOpen && store.acceptingOrders && store.isOnline && !store.isBusy) {
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
    if (store.isOpen && store.acceptingOrders && store.isOnline && !store.isBusy) {
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
