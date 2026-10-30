import 'dish.dart';
// lib/models/product_model.dart

class ProductModel {
  final List<OptionGroup>? optionGroups;
  final String id;
  final String businessId;
  final String categoryId;
  final String? categoryName; // 🔥 إضافة اسم الفئة
  final String name;
  final String description;
  final String imageUrl;
  final double price;
  final bool isAvailable;
  final bool isFeatured; // 🔥 الأكثر مبيعاً/مميز
  final List<dynamic>?
  addons; // 🔥 إضافات/خيارات خام من الباك إند (شكل غير مضمون)
  final List<dynamic>? variations; // 🔥 متغيرات خام من الباك إند
  final int preparationTime;
  final Map<String, dynamic>? nutritionInfo;
  final List<String> allergens;
  final bool isVegetarian;
  final bool isVegan;
  final bool isGlutenFree;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ProductModel({
    required this.id,
    required this.businessId,
    required this.categoryId,
    this.categoryName, // 🔥 إضافة
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.price,
    this.isAvailable = true,
    this.isFeatured = false,
    this.optionGroups,
    this.addons,
    this.variations,
    this.preparationTime = 0,
    this.nutritionInfo,
    this.allergens = const [],
    this.isVegetarian = false,
    this.isVegan = false,
    this.isGlutenFree = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id:
          json['productId']?.toString() ??
          json['product_id']?.toString() ??
          json['id']?.toString() ??
          '',
      businessId:
          json['businessId']?.toString() ??
          json['business_id']?.toString() ??
          '',
      categoryId:
          json['categoryId']?.toString() ??
          json['category_id']?.toString() ??
          '',
      categoryName:
          json['categoryName']?.toString() ??
          json['category_name']?.toString(), // 🔥 إضافة
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      imageUrl:
          json['imageUrl']?.toString() ?? json['image_url']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      isAvailable: json['isAvailable'] ?? json['is_available'] ?? true,
      isFeatured: json['is_featured'] == true || json['isFeatured'] == true,
      optionGroups:
          json.containsKey('optionGroups')
              ? (json['optionGroups'] as List)
                  .map(
                    (v) => OptionGroup.fromJson(Map<String, dynamic>.from(v)),
                  )
                  .toList()
              : null,
      addons:
          json['addons'] is List
              ? List<dynamic>.from(json['addons'] as List)
              : null,
      variations:
          json['variations'] is List
              ? List<dynamic>.from(json['variations'] as List)
              : null,
      preparationTime: (json['preparation_time'] as num?)?.toInt() ?? 0,
      nutritionInfo: json['nutrition_info'] as Map<String, dynamic>?,
      allergens:
          json['allergens'] != null ? List<String>.from(json['allergens']) : [],
      isVegetarian: json['is_vegetarian'] ?? false,
      isVegan: json['is_vegan'] ?? false,
      isGlutenFree: json['is_gluten_free'] ?? false,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          json['updated_at'] != null
              ? DateTime.tryParse(json['updated_at'].toString())
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (optionGroups != null)
        'optionGroups': optionGroups!.map((v) => v.toJson()).toList(),
      'id': id,
      'business_id': businessId,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'price': price,
      'is_available': isAvailable,
      'preparation_time': preparationTime,
      'nutrition_info': nutritionInfo,
      'allergens': allergens,
      'is_vegetarian': isVegetarian,
      'is_vegan': isVegan,
      'is_gluten_free': isGlutenFree,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  List<OptionGroup> get effectiveOptionGroups =>
      optionGroups ?? OptionGroup.listFromAddons(addons ?? variations);

  // للتوافق مع النظام الحالي
  String get image => imageUrl;
  double get basePrice => price;
  List<String> get imageUrls => [imageUrl];
  int get likesPercent => 80; // قيمة افتراضية
  int get likesCount => 50; // قيمة افتراضية
}
