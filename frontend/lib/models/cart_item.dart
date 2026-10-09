// lib/models/cart_item.dart

import 'package:foodapp_user/models/dish.dart';

class CartItem {
  /// معرّف المتجر الذي انبثق منه الطلب
  final String storeId;
  final Dish dish;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final Map<String, Set<String>> selectedOptions;
  final String? specialInstructions;

  CartItem({
    required this.storeId,
    required this.dish,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.selectedOptions,
    this.specialInstructions,
  });

  factory CartItem.fromJson(Map<String, dynamic> json, Dish dish) => CartItem(
        storeId: json['storeId'] as String,
        dish: dish,
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        totalPrice: (json['totalPrice'] as num).toDouble(),
        selectedOptions: (json['selectedOptions'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, Set<String>.from(v as List<dynamic>))),
        specialInstructions: json['specialInstructions'] as String?,
      );

  // Factory للإنشاء من JSON مع بيانات الطبق المضمنة
  factory CartItem.fromFullJson(Map<String, dynamic> json) => CartItem(
        storeId: json['storeId'] as String,
        dish: Dish.fromJson(json['dish'] as Map<String, dynamic>),
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        totalPrice: (json['totalPrice'] as num).toDouble(),
        selectedOptions: (json['selectedOptions'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, Set<String>.from(v as List<dynamic>))),
        specialInstructions: json['specialInstructions'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'dish': dish.toJson(),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalPrice': totalPrice,
        'selectedOptions': selectedOptions.map((k, v) => MapEntry(k, v.toList())),
        'specialInstructions': specialInstructions,
      };
}
