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
  Future<void> _storageQueue = Future.value();
  int _revision = 0;

  /// عناصر السلة
  List<CartItem> get items => List.unmodifiable(_items);

  /// المجموع الكلي
  double get totalAmount =>
      _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// عدد العناصر في السلة
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// المعرّف الحالي للمتجر (null إذا كانت السلة فارغة)
  String? get currentStoreId => _items.isEmpty ? null : _items.first.storeId;

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
    final revision = _revision;
    final loadingKey = await _getCartKey();
    try {
      await _storageQueue;
      final prefs = await SharedPreferences.getInstance();
      final cartKey = await _getCartKey();
      if (cartKey != loadingKey || revision != _revision) return;
      final cartData = prefs.getString(cartKey);

      // تنظيف السلة الحالية أولاً
      _items.clear();

      if (cartData != null) {
        final List<dynamic> jsonList = json.decode(cartData);

        for (final itemJson in jsonList) {
          try {
            final cartItem = CartItem.fromFullJson(
              itemJson as Map<String, dynamic>,
            );
            _items.add(cartItem);
          } catch (e) {
            debugPrint('خطأ في تحميل عنصر السلة: $e');
          }
        }

        debugPrint(
          'تم تحميل ${_items.length} عنصر من السلة للمستخدم: $cartKey',
        );
      } else {
        debugPrint('لا توجد سلة محفوظة للمستخدم: $cartKey');
      }
    } catch (e) {
      if (revision != _revision) return;
      debugPrint('خطأ في تحميل السلة من التخزين: $e');
      // في حالة الخطأ، تنظيف السلة للحماية
      _items.clear();
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// حفظ السلة في التخزين المحلي
  Future<void> saveToStorage() {
    // Capture account and data before awaiting I/O. Serialize writes so an older
    // tap cannot overwrite a newer quantity or resurrect a cleared basket.
    final session = SessionService.instance;
    final key =
        session.isGuest
            ? 'cart_items_guest'
            : session.currentUserId != null
            ? 'cart_items_${session.currentUserId}'
            : 'cart_items_anonymous';
    final data = json.encode(_items.map((item) => item.toJson()).toList());
    return _storageQueue = _storageQueue
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, data);
        })
        .catchError((Object e) {
          debugPrint('Cart persistence failed: $e');
        });
  }

  Future<void> clearStorage() {
    final session = SessionService.instance;
    final key =
        session.isGuest
            ? 'cart_items_guest'
            : session.currentUserId != null
            ? 'cart_items_${session.currentUserId}'
            : 'cart_items_anonymous';
    return _storageQueue = _storageQueue
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(key);
        })
        .catchError((Object e) {
          debugPrint('Cart persistence failed: $e');
        });
  }

  /// إضافة عنصر مع التحقق من المطعم
  void addItem(CartItem newItem) {
    // إذا السلة ليست فارغة ومطعم الطلب الجديد مختلف
    if (currentStoreId != null && currentStoreId != newItem.storeId) {
      // لا نفعل شيء هنا، بل نوفّر التحقق في واجهة المستخدم
      return;
    }

    final existing = _items.firstWhereOrNull(
      (item) => item.lineKey == newItem.lineKey,
    );

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

    _revision++;
    notifyListeners();
    saveToStorage(); // حفظ تلقائي
  }

  void updateItemQuantity(CartItem item, int newQuantity) {
    final idx = _items.indexWhere((r) => r.lineKey == item.lineKey);
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
    _revision++;
    notifyListeners();
    saveToStorage(); // حفظ تلقائي
  }

  void changeItemQuantity(CartItem item, int delta) {
    final current = _items.firstWhereOrNull((r) => r.lineKey == item.lineKey);
    if (current == null || delta == 0) return;
    updateItemQuantity(current, current.quantity + delta);
  }

  void removeItem(CartItem item) {
    _items.removeWhere((r) => r.lineKey == item.lineKey);
    _revision++;
    notifyListeners();
    saveToStorage(); // حفظ تلقائي
  }

  void clear() {
    _items.clear();
    _revision++;
    notifyListeners();
    clearStorage(); // مسح من التخزين أيضاً
  }

  /// مسح السلة عند تغيير الجلسة (بدلاً من الحذف، نحمل السلة الصحيحة)
  Future<void> clearOnSessionChange() async {
    // Invalidate any previous account load before switching baskets.
    _revision++;
    _items.clear();

    // إعادة تحميل السلة المناسبة للمستخدم الجديد
    // هذا سيحمل السلة الفارغة للمستخدم الجديد أو سلته المحفوظة
    await loadFromStorage();

    debugPrint('تم تبديل السلة بسبب تغيير الجلسة');
  }
}
