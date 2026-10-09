// lib/models/offer.dart

class Offer {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final double discountPercentage;
  final double? minOrderAmount;
  final DateTime startDate;
  final DateTime endDate;
  final String storeId;
  final String storeName;
  final List<String> applicableCategories;
  final OfferType type;

  Offer({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.discountPercentage,
    this.minOrderAmount,
    required this.startDate,
    required this.endDate,
    required this.storeId,
    required this.storeName,
    this.applicableCategories = const [],
    this.type = OfferType.percentage,
  });

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      imageUrl: json['image_url'] ?? '',
      discountPercentage: (json['discount_percentage'] as num).toDouble(),
      minOrderAmount: json['min_order_amount']?.toDouble(),
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      storeId: json['store_id'],
      storeName: json['store_name'],
      applicableCategories: List<String>.from(json['applicable_categories'] ?? []),
      type: OfferType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => OfferType.percentage,
      ),
    );
  }

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startDate) && now.isBefore(endDate);
  }

  String get formattedDiscount {
    switch (type) {
      case OfferType.percentage:
        return '${discountPercentage.toInt()}%';
      case OfferType.fixedAmount:
        return '${discountPercentage.toStringAsFixed(2)} ر.س';
      case OfferType.buyOneGetOne:
        return 'اشتري واحد واحصل على آخر مجاناً';
    }
  }
}

enum OfferType {
  percentage,     // خصم بالنسبة المئوية
  fixedAmount,    // خصم بمبلغ ثابت
  buyOneGetOne,   // اشتري واحد واحصل على آخر
}
