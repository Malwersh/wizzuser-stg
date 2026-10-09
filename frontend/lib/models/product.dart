// lib/models/product.dart

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String category;
  final String brand;
  final String unit; // وحدة القياس (كيلو، لتر، قطعة)
  final bool isAvailable;
  final double? discount;
  final String storeId;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.category,
    required this.brand,
    required this.unit,
    this.isAvailable = true,
    this.discount,
    required this.storeId,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'] ?? '',
      category: json['category'] ?? '',
      brand: json['brand'] ?? '',
      unit: json['unit'] ?? 'قطعة',
      isAvailable: json['is_available'] ?? true,
      discount: json['discount']?.toDouble(),
      storeId: json['store_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category,
      'brand': brand,
      'unit': unit,
      'is_available': isAvailable,
      'discount': discount,
      'store_id': storeId,
    };
  }

  double get finalPrice {
    if (discount != null && discount! > 0) {
      return price * (1 - discount! / 100);
    }
    return price;
  }
}
