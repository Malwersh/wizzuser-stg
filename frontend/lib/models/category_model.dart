// lib/models/category_model.dart

class CategoryModel {
  final String categoryId;
  final String businessId;  // معرف المطعم/البزنز من order-receiver-businesses-dev
  final String categoryName;
  final String? description;
  final String? imageUrl;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CategoryModel({
    required this.categoryId,
    required this.businessId,
    required this.categoryName,
    this.description,
    this.imageUrl,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      categoryId: json['categoryId']?.toString() ?? json['category_id']?.toString() ?? '',
      businessId: json['businessId']?.toString() ?? json['business_id']?.toString() ?? '',
      categoryName: json['name_ar']?.toString() ?? json['categoryName']?.toString() ?? json['category_name']?.toString() ?? json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      imageUrl: json['image_url']?.toString() ?? json['imageUrl']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? (json['sortOrder'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updated_at'] != null || json['updatedAt'] != null
          ? DateTime.tryParse(json['updated_at']?.toString() ?? json['updatedAt']?.toString() ?? '')
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'categoryId': categoryId,
      'businessId': businessId,
      'categoryName': categoryName,
      'description': description,
      'imageUrl': imageUrl,
      'sortOrder': sortOrder,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  // للتوافق مع النظام الحالي
  String get name => categoryName;
  String get id => categoryId;
}
