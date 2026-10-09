// lib/models/search_result.dart

import 'store.dart';
import 'dish.dart';
import 'product.dart';
import 'offer.dart';

enum SearchResultType {
  store,        // متجر
  dish,         // طبق
  product,      // منتج سوبرماركت
  offer,        // عرض خاص
  coupon,       // كوبون خصم
  category,     // فئة
  combo,        // وجبة مجمعة
}

class SearchResult {
  final SearchResultType type;
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final Store? store;
  final Dish? dish;
  final Product? product;
  final Offer? offer;
  final String? storeId; // للأطباق والمنتجات
  final String? storeName; // للأطباق والمنتجات
  final Map<String, dynamic>? metadata; // بيانات إضافية

  SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.store,
    this.dish,
    this.product,
    this.offer,
    this.storeId,
    this.storeName,
    this.metadata,
  });

  // إنشاء نتيجة بحث من متجر
  factory SearchResult.fromStore(Store store) {
    return SearchResult(
      type: SearchResultType.store,
      id: store.id,
      title: store.name,
      subtitle: store.category ?? 'متنوع',
      imageUrl: store.image,
      store: store,
    );
  }

  // إنشاء نتيجة بحث من طبق
  factory SearchResult.fromDish(Dish dish, String storeId, String storeName) {
    return SearchResult(
      type: SearchResultType.dish,
      id: dish.id,
      title: dish.name,
      subtitle: 'في $storeName • ${dish.basePrice.toStringAsFixed(2)} ر.س',
      imageUrl: dish.imageUrls.isNotEmpty ? dish.imageUrls.first : '',
      dish: dish,
      storeId: storeId,
      storeName: storeName,
    );
  }

  // إنشاء نتيجة بحث من منتج
  factory SearchResult.fromProduct(Product product, String storeName) {
    return SearchResult(
      type: SearchResultType.product,
      id: product.id,
      title: product.name,
      subtitle: 'في $storeName • ${product.finalPrice.toStringAsFixed(2)} ر.س/${product.unit}',
      imageUrl: product.imageUrl,
      product: product,
      storeId: product.storeId,
      storeName: storeName,
    );
  }

  // إنشاء نتيجة بحث من عرض
  factory SearchResult.fromOffer(Offer offer) {
    return SearchResult(
      type: SearchResultType.offer,
      id: offer.id,
      title: offer.title,
      subtitle: '${offer.formattedDiscount} خصم في ${offer.storeName}',
      imageUrl: offer.imageUrl,
      offer: offer,
      storeId: offer.storeId,
      storeName: offer.storeName,
    );
  }

  // إنشاء نتيجة بحث من فئة
  factory SearchResult.fromCategory(String categoryName, String iconPath, int storeCount) {
    return SearchResult(
      type: SearchResultType.category,
      id: 'category_${categoryName.toLowerCase()}',
      title: categoryName,
      subtitle: '$storeCount متجر متاح',
      imageUrl: iconPath,
      metadata: {'store_count': storeCount},
    );
  }

  // إنشاء نتيجة بحث عامة مع بيانات مخصصة
  factory SearchResult.custom({
    required SearchResultType type,
    required String id,
    required String title,
    required String subtitle,
    required String imageUrl,
    Map<String, dynamic>? metadata,
  }) {
    return SearchResult(
      type: type,
      id: id,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      metadata: metadata,
    );
  }
}
