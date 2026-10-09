// lib/models/cart_model.dart

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'cart_item.dart';
import '../services/session_service.dart';

class CartModel extends ChangeNotifier {
  final List<CartItem> _items = [];
  bool _isLoaded = false;

  /// عناصر السلة
  List<CartItem> get items => List.unmodifiable(_items);

  /// المجموع الكلي
  double get totalAmount =>
      _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// عدد العناصر في السلة
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// المعرّف الحالي للمتجر (null إذا كانت السلة فارغة)
  String? get currentStoreId =>
      _items.isEmpty ? null : _items.first.storeId;

  /// هل تم تحميل السلة من التخزين المحلي
  bool get isLoaded => _isLoaded;

  /// الحصول على مفتاح السلة للمستخدم الحالي
  Future<String> _getCartKey() async {
    final sessionService = SessionService.instance;
    final userId = sessionService.currentUserId;
    final isGuest = sessionService.isGuest;
    
    if (isGuest) {
      return 'cart_items_guest';
    } else if (userId != null) {
      return 'cart_items_$userId';
    } else {
      return 'cart_items_anonymous';
    }
  }

  /// تحميل السلة من التخزين المحلي
  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartKey = await _getCartKey();
      final cartData = prefs.getString(cartKey);
      
      // تنظيف السلة الحالية أولاً
      _items.clear();
      
      if (cartData != null) {
        final List<dynamic> jsonList = json.decode(cartData);
        
        for (final itemJson in jsonList) {
          try {
            final cartItem = CartItem.fromFullJson(itemJson as Map<String, dynamic>);
            _items.add(cartItem);
          } catch (e) {
            debugPrint('خطأ في تحميل عنصر السلة: $e');
          }
        }
        
        debugPrint('تم تحميل ${_items.length} عنصر من السلة للمستخدم: $cartKey');
      } else {
        debugPrint('لا توجد سلة محفوظة للمستخدم: $cartKey');
      }
    } catch (e) {
      debugPrint('خطأ في تحميل السلة من التخزين: $e');
      // في حالة الخطأ، تنظيف السلة للحماية
      _items.clear();
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// حفظ السلة في التخزين المحلي
  Future<void> saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartKey = await _getCartKey();
      final cartData = json.encode(_items.map((item) => item.toJson()).toList());
      await prefs.setString(cartKey, cartData);
      debugPrint('تم حفظ ${_items.length} عنصر في السلة للمستخدم: $cartKey');
    } catch (e) {
      debugPrint('خطأ في حفظ السلة: $e');
    }
  }

  /// مسح السلة من التخزين المحلي
  Future<void> clearStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartKey = await _getCartKey();
      await prefs.remove(cartKey);
      debugPrint('تم مسح السلة من التخزين للمستخدم: $cartKey');
    } catch (e) {
      debugPrint('خطأ في مسح السلة من التخزين: $e');
    }
  }

  /// إضافة عنصر مع التحقق من المطعم
  void addItem(CartItem newItem) {
    // إذا السلة ليست فارغة ومطعم الطلب الجديد مختلف
    if (currentStoreId != null && currentStoreId != newItem.storeId) {
      // لا نفعل شيء هنا، بل نوفّر التحقق في واجهة المستخدم
      return;
    }

    final existing = _items.firstWhereOrNull((item) =>
        item.dish.id == newItem.dish.id &&
        const DeepCollectionEquality()
            .equals(item.selectedOptions, newItem.selectedOptions));

    if (existing != null) {
      final idx = _items.indexOf(existing);
      final updatedQuantity = existing.quantity + newItem.quantity;
      final unitPrice = existing.unitPrice;
      _items[idx] = CartItem(
        storeId: existing.storeId,
        dish: existing.dish,
        quantity: updatedQuantity,
        unitPrice: unitPrice,
        totalPrice: unitPrice * updatedQuantity,
        selectedOptions: existing.selectedOptions,
        specialInstructions: existing.specialInstructions,
      );
    } else {
      _items.add(newItem);
    }

    notifyListeners();
    saveToStorage(); // حفظ تلقائي
  }

  void updateItemQuantity(CartItem item, int newQuantity) {
    final idx = _items.indexOf(item);
    if (idx == -1) return;
    if (newQuantity <= 0) {
      _items.removeAt(idx);
    } else {
      final existing = _items[idx];
      _items[idx] = CartItem(
        storeId: existing.storeId,
        dish: existing.dish,
        quantity: newQuantity,
        unitPrice: existing.unitPrice, // يبقى ثابت
        totalPrice: existing.unitPrice * newQuantity, // فقط هذا يتغير
        selectedOptions: existing.selectedOptions,
        specialInstructions: existing.specialInstructions,
      );
    }
    notifyListeners();
    saveToStorage(); // حفظ تلقائي
  }

  void removeItem(CartItem item) {
    _items.remove(item);
    notifyListeners();
    saveToStorage(); // حفظ تلقائي
  }

  void clear() {
    _items.clear();
    notifyListeners();
    clearStorage(); // مسح من التخزين أيضاً
  }

  /// مسح السلة عند تغيير الجلسة (بدلاً من الحذف، نحمل السلة الصحيحة)
  Future<void> clearOnSessionChange() async {
    // مسح السلة المعروضة حالياً في الذاكرة
    _items.clear();
    
    // إعادة تحميل السلة المناسبة للمستخدم الجديد
    // هذا سيحمل السلة الفارغة للمستخدم الجديد أو سلته المحفوظة
    await loadFromStorage();
    
    debugPrint('تم تبديل السلة بسبب تغيير الجلسة');
  }
}
