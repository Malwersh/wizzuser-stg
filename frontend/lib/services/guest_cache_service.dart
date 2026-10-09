import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/delivery_address.dart';

/// خدمة إدارة الذاكرة المؤقتة (Cache) للمستخدمين الضيوف
/// Guest Cache Service - Manages temporary address storage for guest users
class GuestCacheService {
  // مفتاح حفظ عنوان الضيف النشط
  static const String _guestAddressKey = 'guest_active_address';
  
  // مفتاح حفظ تاريخ آخر تحديث
  static const String _lastUpdatedKey = 'guest_address_last_updated';
  
  // مدة صلاحية العنوان (7 أيام)
  static const int _expiryDays = 7;
  
  /// حفظ عنوان الضيف في Cache
  /// Save guest address to local cache
  /// 
  /// يتم حفظ العنوان محلياً في SharedPreferences ليستمر
  /// حتى بعد إغلاق وإعادة فتح التطبيق
  static Future<bool> saveGuestAddress(DeliveryAddress address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // تحويل العنوان إلى JSON
      final addressJson = jsonEncode(address.toJson());
      
      // حفظ العنوان
      await prefs.setString(_guestAddressKey, addressJson);
      
      // حفظ وقت الحفظ
      await prefs.setInt(
        _lastUpdatedKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      
      print('✅ تم حفظ عنوان الضيف: ${address.formattedAddress}');
      return true;
    } catch (e) {
      print('❌ فشل حفظ عنوان الضيف: $e');
      return false;
    }
  }
  
  /// قراءة عنوان الضيف من Cache
  /// Load guest address from local cache
  /// 
  /// يتم فحص صلاحية العنوان (7 أيام)
  /// إذا انتهت الصلاحية، يتم حذف العنوان
  static Future<DeliveryAddress?> getGuestAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // التحقق من وجود عنوان محفوظ
      if (!prefs.containsKey(_guestAddressKey)) {
        print('ℹ️ لا يوجد عنوان محفوظ للضيف');
        return null;
      }
      
      // قراءة العنوان
      final addressJson = prefs.getString(_guestAddressKey);
      if (addressJson == null) return null;
      
      // قراءة وقت الحفظ
      final lastUpdated = prefs.getInt(_lastUpdatedKey);
      
      // فحص الصلاحية
      if (lastUpdated != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(lastUpdated);
        final daysSinceSaved = DateTime.now().difference(savedDate).inDays;
        
        if (daysSinceSaved > _expiryDays) {
          print('⏰ انتهت صلاحية عنوان الضيف (${daysSinceSaved} أيام)');
          await clearGuestAddress();
          return null;
        }
      }
      
      // تحويل من JSON إلى DeliveryAddress
      final addressMap = jsonDecode(addressJson) as Map<String, dynamic>;
      final address = DeliveryAddress.fromJson(addressMap);
      
      print('✅ تم تحميل عنوان الضيف: ${address.formattedAddress}');
      return address;
    } catch (e) {
      print('❌ فشل تحميل عنوان الضيف: $e');
      // في حالة الخطأ، نحذف العنوان المعطوب
      await clearGuestAddress();
      return null;
    }
  }
  
  /// حذف عنوان الضيف من Cache
  /// Clear guest address from cache
  /// 
  /// يستخدم عند:
  /// - انتهاء صلاحية العنوان
  /// - حدوث خطأ في قراءة العنوان
  /// - تسجيل دخول الضيف كمستخدم مسجل
  static Future<bool> clearGuestAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(_guestAddressKey);
      await prefs.remove(_lastUpdatedKey);
      
      print('✅ تم حذف عنوان الضيف من Cache');
      return true;
    } catch (e) {
      print('❌ فشل حذف عنوان الضيف: $e');
      return false;
    }
  }
  
  /// فحص وجود عنوان محفوظ
  /// Check if guest has a saved address
  /// 
  /// يتم استخدامها في splash_screen لتحديد المسار المناسب
  static Future<bool> hasGuestAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // فحص وجود العنوان
      if (!prefs.containsKey(_guestAddressKey)) {
        return false;
      }
      
      // فحص الصلاحية
      final lastUpdated = prefs.getInt(_lastUpdatedKey);
      if (lastUpdated != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(lastUpdated);
        final daysSinceSaved = DateTime.now().difference(savedDate).inDays;
        
        if (daysSinceSaved > _expiryDays) {
          // انتهت الصلاحية
          await clearGuestAddress();
          return false;
        }
      }
      
      return true;
    } catch (e) {
      print('❌ فشل فحص عنوان الضيف: $e');
      return false;
    }
  }
  
  /// تحديث وقت آخر استخدام للعنوان
  /// Update last used timestamp
  /// 
  /// يستخدم لتجديد صلاحية العنوان عند استخدامه
  static Future<bool> updateLastUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setInt(
        _lastUpdatedKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      
      return true;
    } catch (e) {
      print('❌ فشل تحديث وقت الاستخدام: $e');
      return false;
    }
  }
  
  /// الحصول على عدد الأيام منذ آخر تحديث
  /// Get days since last update
  static Future<int?> getDaysSinceLastUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdated = prefs.getInt(_lastUpdatedKey);
      
      if (lastUpdated == null) return null;
      
      final savedDate = DateTime.fromMillisecondsSinceEpoch(lastUpdated);
      return DateTime.now().difference(savedDate).inDays;
    } catch (e) {
      return null;
    }
  }
  
  // ============================================
  // 🆕 إدارة عناوين متعددة للضيف
  // Multiple Addresses Management for Guest
  // ============================================
  
  static const String _guestAddressesListKey = 'guest_addresses_list';
  static const int _maxGuestAddresses = 5; // الحد الأقصى للعناوين المحفوظة
  
  /// حفظ عنوان جديد في قائمة العناوين
  /// Add address to guest addresses list
  static Future<bool> addGuestAddressToList(DeliveryAddress address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // جلب القائمة الحالية
      final currentList = await getAllGuestAddresses();
      
      // إزالة أي عنوان مكرر (نفس الإحداثيات)
      currentList.removeWhere((addr) => 
        addr.latitude == address.latitude && 
        addr.longitude == address.longitude
      );
      
      // إضافة العنوان الجديد في البداية
      currentList.insert(0, address);
      
      // الاحتفاظ بآخر 5 عناوين فقط
      if (currentList.length > _maxGuestAddresses) {
        currentList.removeRange(_maxGuestAddresses, currentList.length);
      }
      
      // حفظ القائمة
      final addressesJson = currentList.map((addr) => addr.toJson()).toList();
      await prefs.setString(_guestAddressesListKey, jsonEncode(addressesJson));
      
      print('✅ تم إضافة عنوان للقائمة. إجمالي: ${currentList.length}');
      return true;
    } catch (e) {
      print('❌ فشل إضافة عنوان للقائمة: $e');
      return false;
    }
  }
  
  /// جلب جميع العناوين المحفوظة للضيف
  /// Get all saved guest addresses
  static Future<List<DeliveryAddress>> getAllGuestAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final addressesJson = prefs.getString(_guestAddressesListKey);
      if (addressesJson == null) return [];
      
      final List<dynamic> addressesList = jsonDecode(addressesJson);
      return addressesList
          .map((json) => DeliveryAddress.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ فشل جلب قائمة العناوين: $e');
      return [];
    }
  }
  
  /// حذف عنوان من القائمة
  /// Remove address from list
  static Future<bool> removeGuestAddress(DeliveryAddress address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getAllGuestAddresses();
      
      currentList.removeWhere((addr) => 
        addr.latitude == address.latitude && 
        addr.longitude == address.longitude
      );
      
      final addressesJson = currentList.map((addr) => addr.toJson()).toList();
      await prefs.setString(_guestAddressesListKey, jsonEncode(addressesJson));
      
      return true;
    } catch (e) {
      print('❌ فشل حذف العنوان: $e');
      return false;
    }
  }
  
  /// حذف جميع العناوين المحفوظة
  /// Clear all guest addresses
  static Future<bool> clearAllGuestAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_guestAddressesListKey);
      await clearGuestAddress(); // حذف العنوان النشط أيضاً
      return true;
    } catch (e) {
      return false;
    }
  }
}
