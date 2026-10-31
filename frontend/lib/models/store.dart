// lib/models/store.dart

import 'menu_item.dart';

class Store {
  final String id;
  final String name;
  final String image;     // صورة الغلاف
  final String logoUrl;   // شعار المتجر
  final bool isOpen;      // مفتوح أم مغلق
  final String fee;       // رسوم التوصيل أو أي معلومة مالية
  final String rating;    // تقييم النجوم
  final String reviews;   // عدد المراجعات
  final String distance;  // المسافة
  final String time;      // وقت التوصيل/العمل
  final int? averagePreparationMinutes;
  final String address;   // عنوان المتجر

  // خصائص إضافية للتوافق مع الشاشات
  String get imageUrl => image;  // alias للصورة الرئيسية
  String get ratingLabel => ratingValue.isFinite && ratingValue >= 1 && ratingValue <= 5 ? rating : '—';
  double get ratingValue => double.tryParse(rating) ?? 0.0;  // التقييم كرقم
  String get deliveryTime => time;  // وقت التوصيل
  String get deliveryFee => fee;    // رسوم التوصيل

  // هذه الحقول كانت مفقودة في الكونستركتور
  final String? promo;
  final String? tag;
  final String? category;
  final String? businessType;        // نوع النشاط التجاري (restaurant, store, cafe, etc.)
  final bool sponsored;

  // حقول حالة المطعم الجديدة
  final bool isOnline;            // متصل عبر WebSocket
  final bool acceptingOrders;     // يستقبل طلبات
  final bool isBusy;             // مشغول
  final String businessMode;      // وضع المطعم (auto/manual/closed)
  final int currentOrdersCount;   // عدد الطلبات الحالية
  final int maxOrdersCapacity;    // الحد الأقصى للطلبات
  final String statusMessage;     // رسالة الحالة المخصصة
  final String? lastStatusUpdate; // آخر تحديث للحالة
  final Map<String, dynamic>? businessStatus; // معلومات الحالة الكاملة

  // قوائم الأصناف بحسب التبويبات
  final List<MenuItem> combos;
  final List<MenuItem> sandwiches;
  final List<MenuItem> drinks;
  final List<MenuItem> extras;
  final List<MenuItem> specialties; // أو أي تبويب إضافي

  Store({
    required this.id,
    required this.name,
    required this.image,
    required this.logoUrl,
    required this.isOpen,
    required this.fee,
    required this.rating,
    required this.reviews,
    required this.distance,
    required this.time,
    required this.address,
    this.averagePreparationMinutes,
    this.promo,
    this.tag,
    this.category,
    this.businessType,
    this.sponsored = false,
    // حقول حالة المطعم الجديدة
    this.isOnline = true,
    this.acceptingOrders = true,
    this.isBusy = false,
    this.businessMode = 'auto',
    this.currentOrdersCount = 0,
    this.maxOrdersCapacity = 10,
    this.statusMessage = '',
    this.lastStatusUpdate,
    this.businessStatus,
    required this.combos,
    required this.sandwiches,
    required this.drinks,
    required this.extras,
    required this.specialties,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    List<MenuItem> listFromJson(List<dynamic>? arr) =>
        arr?.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList() ??
        [];

    return Store(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String,
      logoUrl: json['logoUrl'] as String,
      isOpen: json['isOpen'] as bool,
      fee: json['fee'] as String,
      rating: json['rating'] as String,
      reviews: json['reviews'] as String,
      distance: json['distance'] as String,
      time: json['time'] as String,
      address: json['address'] as String,
      promo: json['promo'] as String?,
      tag: json['tag'] as String?,
      category: json['category'] as String?,
      businessType: json['businessType'] as String?,
      sponsored: json['sponsored'] as bool? ?? false,
      // حقول حالة المطعم الجديدة
      isOnline: json['isOnline'] as bool? ?? true,
      acceptingOrders: json['acceptingOrders'] as bool? ?? true,
      isBusy: json['isBusy'] as bool? ?? false,
      businessMode: json['businessMode'] as String? ?? 'auto',
      currentOrdersCount: json['currentOrdersCount'] as int? ?? 0,
      maxOrdersCapacity: json['maxOrdersCapacity'] as int? ?? 10,
      statusMessage: json['statusMessage'] as String? ?? '',
      lastStatusUpdate: json['lastStatusUpdate'] as String?,
      businessStatus: json['businessStatus'] as Map<String, dynamic>?,
      combos: listFromJson(json['combos'] as List<dynamic>?),
      sandwiches: listFromJson(json['sandwiches'] as List<dynamic>?),
      drinks: listFromJson(json['drinks'] as List<dynamic>?),
      extras: listFromJson(json['extras'] as List<dynamic>?),
      specialties: listFromJson(json['specialties'] as List<dynamic>?),
    );
  }
}
