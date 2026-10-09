class DishModel {
  final String id;
  final String name;
  final double price;
  final double rating;
  final String category;
  final String? description;
  final String? image;
  final String? storeId;
  final String? storeName;

  DishModel({
    required this.id,
    required this.name,
    required this.price,
    required this.rating,
    required this.category,
    this.description,
    this.image,
    this.storeId,
    this.storeName,
  });

  factory DishModel.fromJson(Map<String, dynamic> json) {
    return DishModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString(),
      image: json['image']?.toString(),
      storeId: json['store_id']?.toString() ?? json['storeId']?.toString(),
      storeName: json['store_name']?.toString() ?? json['storeName']?.toString(),
    );
  }

  factory DishModel.fromProduct(dynamic product) {
    return DishModel(
      id: product.id?.toString() ?? '',
      name: product.name?.toString() ?? '',
      price: (product.price as num?)?.toDouble() ?? 0.0,
      rating: (product.rating as num?)?.toDouble() ?? 4.0,
      category: product.category?.toString() ?? '',
      description: product.description?.toString(),
      image: product.image?.toString(),
      storeId: product.storeId?.toString(),
      storeName: product.storeName?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'rating': rating,
      'category': category,
      'description': description,
      'image': image,
      'store_id': storeId,
      'store_name': storeName,
    };
  }
}
