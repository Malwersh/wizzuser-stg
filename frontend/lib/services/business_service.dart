// lib/services/business_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/business_model.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';
import 'package:foodapp_user/services/session_service.dart';
import '../config/api_config.dart';

class BusinessService {
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }

  /// جلب تفاصيل متجر واحد
  static Future<BusinessModel?> getBusinessDetails(String businessId) async {
    try {
      final url = Uri.parse('$_baseUrl/business/$businessId');
      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['business'] != null) {
          return BusinessModel.fromJson(data['business']);
        }
      }
      
      debugPrint('فشل في جلب تفاصيل المتجر: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('خطأ في جلب تفاصيل المتجر: $e');
      return null;
    }
  }

  /// جلب فئات متجر معين
  static Future<List<CategoryModel>> getBusinessCategories(String businessId) async {
    try {
      final url = Uri.parse('$_baseUrl/business/$businessId/categories');
      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['categories'] != null) {
          final List<dynamic> categoriesJson = data['categories'];
          return categoriesJson
              .map((json) => CategoryModel.fromJson(json))
              .toList();
        }
      }
      
      debugPrint('فشل في جلب فئات المتجر: ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('خطأ في جلب فئات المتجر: $e');
      return [];
    }
  }

  /// جلب منتجات فئة معينة
  static Future<List<ProductModel>> getCategoryProducts(
    String businessId, 
    String categoryId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/category/$categoryId/products?page=$page&limit=$limit');
      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['products'] != null) {
          final List<dynamic> productsJson = data['products'];
          return productsJson
              .map((json) => ProductModel.fromJson(json))
              .toList();
        }
      }
      
      debugPrint('فشل في جلب منتجات الفئة: ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('خطأ في جلب منتجات الفئة: $e');
      return [];
    }
  }

  /// جلب جميع منتجات متجر معين
  static Future<List<ProductModel>> getAllBusinessProducts(
    String businessId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/business/$businessId/products?page=$page&limit=$limit');
      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['products'] != null) {
          final List<dynamic> productsJson = data['products'];
          return productsJson
              .map((json) => ProductModel.fromJson(json))
              .toList();
        }
      }
      
      debugPrint('فشل في جلب منتجات المتجر: ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('خطأ في جلب منتجات المتجر: $e');
      return [];
    }
  }

  /// جلب تفاصيل منتج واحد
  static Future<ProductModel?> getProductDetails(String businessId, String productId) async {
    try {
      final url = Uri.parse('$_baseUrl/product/$productId');
      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['product'] != null) {
          return ProductModel.fromJson(data['product']);
        }
      }
      
      debugPrint('فشل في جلب تفاصيل المنتج: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('خطأ في جلب تفاصيل المنتج: $e');
      return null;
    }
  }

  /// جلب فئات ومنتجات المطعم معاً - الطريقة الصحيحة
  static Future<Map<String, List<ProductModel>>> getBusinessCategoriesAndProducts(String businessId) async {
    try {
      debugPrint('🔍 جاري جلب منتجات المطعم: $businessId');
      
      // جلب جميع منتجات المطعم من المسار الجديد
      final url = Uri.parse('$_baseUrl/business/$businessId/products');
      debugPrint('📡 استدعاء API: $url');
      
      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      debugPrint('📊 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📦 Response Data: ${data.keys.toList()}');
        
        if (data['success'] == true && data['products'] != null) {
          final List<dynamic> productsJson = data['products'];
          debugPrint('✅ تم جلب ${productsJson.length} منتج من API');
          
          final products = productsJson
              .map((json) => ProductModel.fromJson(json))
              .toList();

          // تجميع المنتجات حسب الفئات مباشرة من categoryName
          final Map<String, List<ProductModel>> result = {};
          int productsWithCategory = 0;
          int productsWithoutCategory = 0;
          
          for (final product in products) {
            String categoryName;
            
            // استخدام categoryName من API مباشرة
            if (product.categoryName != null && product.categoryName!.isNotEmpty) {
              categoryName = product.categoryName!;
              productsWithCategory++;
            } else if (product.categoryId.isNotEmpty) {
              // استخدام categoryId منسق كاسم الفئة إذا لم يكن categoryName موجوداً
              categoryName = _formatCategoryId(product.categoryId);
              productsWithCategory++;
              debugPrint('⚠️ استخدام categoryId منسق كاسم للفئة: ${product.categoryId} -> $categoryName');
            } else {
              // إذا لم يكن هناك categoryId أو categoryName، ضع المنتج في فئة "أخرى"
              categoryName = 'منتجات أخرى';
              productsWithoutCategory++;
              debugPrint('⚠️ منتج بدون فئة: ${product.name}');
            }
            
            if (!result.containsKey(categoryName)) {
              result[categoryName] = [];
            }
            result[categoryName]!.add(product);
          }

          debugPrint('✅ تم تجميع المنتجات: ${result.length} فئة');
          debugPrint('📊 منتجات مع فئات: $productsWithCategory');
          debugPrint('⚠️ منتجات بدون فئة: $productsWithoutCategory');
          
          for (final entry in result.entries) {
            debugPrint('   📂 ${entry.key}: ${entry.value.length} منتج');
          }

          return result;
        } else {
          debugPrint('⚠️ Response success=${data["success"]}, has products=${data["products"] != null}');
        }
      }

      debugPrint('❌ فشل في جلب منتجات المتجر: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('📄 Response Body: ${response.body}');
      }
      return {};
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في جلب منتجات المتجر: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return {};
    }
  }

  /// جلب تفاصيل فئة واحدة
  static Future<CategoryModel?> getCategoryDetails(String categoryId) async {
    try {
      final url = Uri.parse('$_baseUrl/category/$categoryId');
      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['category'] != null) {
          return CategoryModel.fromJson(data['category']);
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('خطأ في جلب تفاصيل الفئة: $e');
      return null;
    }
  }

  /// إعداد headers للطلبات
  static Future<Map<String, String>> _getHeaders() async {
    final token = SessionService.instance.accessToken;
    
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// تنسيق categoryId ليكون أكثر قابلية للقراءة
  /// مثال: "burgers" -> "Burgers", "main_dishes" -> "Main Dishes"
  static String _formatCategoryId(String categoryId) {
    if (categoryId.isEmpty) return 'منتجات أخرى';
    
    // استبدال الشرطات السفلية بمسافات
    String formatted = categoryId.replaceAll('_', ' ').replaceAll('-', ' ');
    
    // تحويل أول حرف من كل كلمة إلى حرف كبير
    formatted = formatted.split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
    
    return formatted;
  }

  /// جلب قائمة جميع المتاجر المتاحة
  static Future<List<BusinessModel>> getAllBusinesses({
    int page = 0, // Use 0-based pagination
    int limit = 20,
    String? category,
    bool newOnly = false,
  }) async {
    try {
      // استدعاء API الحقيقي
      final queryParams = <String, String>{
        'page': page.toString(), // Use page as-is (0-based pagination)
        'limit': limit.toString(),
      };
      
      if (category != null) queryParams['category'] = category;
      if (newOnly) queryParams['new'] = 'true';
      
      // Build endpoint with query parameters
      final endpoint = '/businesses?${queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&')}';
      
      final url = Uri.parse('$_baseUrl$endpoint');
      
      debugPrint('🔗 API URL: $url');
      debugPrint('📡 Headers: ${await _getHeaders()}');

      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      debugPrint('📡 Response Status: ${response.statusCode}');
      debugPrint('📡 Response Headers: ${response.headers}');
      debugPrint('📡 Response Body Length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📊 Success: ${data['success']}');
        debugPrint('📊 Businesses Count: ${data['businesses']?.length ?? 0}');
        
        if (data['success'] == true && data['businesses'] != null) {
          final businesses = (data['businesses'] as List)
              .map((business) => BusinessModel.fromJson(business))
              .toList();
          
          // فحص أول business
          if (businesses.isNotEmpty) {
            final first = businesses.first;
            debugPrint('🍽️ First Business: ${first.businessName}');
            debugPrint('🖼️ Image URL: "${first.businessPhotoUrl}"');
            debugPrint('🖼️ URL Length: ${first.businessPhotoUrl.length}');
            debugPrint('🖼️ URL isEmpty: ${first.businessPhotoUrl.isEmpty}');
          }
          
          return businesses;
        }
      }
      
      debugPrint('فشل في جلب قائمة المتاجر: ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('خطأ في جلب قائمة المتاجر: $e');
      return [];
    }
  }

  /// جلب قائمة جميع المتاجر مع معلومات pagination
  static Future<BusinessListResponse> getAllBusinessesWithPagination({
    int page = 0, // Use 0-based pagination
    int limit = 20,
    String? category,
    bool newOnly = false,
  }) async {
    try {
      // استدعاء API الحقيقي
      final queryParams = <String, String>{
        'page': page.toString(), // Use page as-is (0-based pagination)
        'limit': limit.toString(),
      };
      
      if (category != null) queryParams['category'] = category;
      if (newOnly) queryParams['new'] = 'true';
      
      // Build endpoint with query parameters
      final endpoint = '/businesses?${queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&')}';
      
      final url = Uri.parse('$_baseUrl$endpoint');
      
      debugPrint('🔗 API URL: $url');

      final response = await http.get(
        url,
        headers: await _getHeaders(),
      );

      debugPrint('📡 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📊 Success: ${data['success']}');
        debugPrint('📊 Businesses Count: ${data['businesses']?.length ?? 0}');
        debugPrint('📊 Has More: ${data['hasMore']}');
        debugPrint('📊 Total: ${data['total']}');
        
        if (data['success'] == true && data['businesses'] != null) {
          final businesses = (data['businesses'] as List)
              .map((business) => BusinessModel.fromJson(business))
              .toList();
          
          return BusinessListResponse(
            businesses: businesses,
            hasMore: data['hasMore'] ?? false,
            total: data['total'] ?? 0,
            page: data['page'] ?? 0,
            count: data['count'] ?? 0,
          );
        }
      }
      
      debugPrint('فشل في جلب قائمة المتاجر: ${response.statusCode}');
      return BusinessListResponse(
        businesses: [],
        hasMore: false,
        total: 0,
        page: 0,
        count: 0,
      );
    } catch (e) {
      debugPrint('خطأ في جلب قائمة المتاجر: $e');
      return BusinessListResponse(
        businesses: [],
        hasMore: false,
        total: 0,
        page: 0,
        count: 0,
      );
    }
  }

  /// جلب المطاعم القريبة بناءً على المسافة الحقيقية
  static Future<List<BusinessModel>> getNearbyBusinesses({
    required double userLatitude,
    required double userLongitude,
    double maxDistanceKm = 20.0,
    int limit = 6,
  }) async {
    try {
      // جلب جميع المطاعم
      final allBusinessesResponse = await getAllBusinessesWithPagination(
        page: 0,
        limit: 100, // جلب عدد كبير للحصول على خيارات أكثر للفلترة
      );

      if (allBusinessesResponse.businesses.isEmpty) {
        return [];
      }

      // حساب المسافة لكل مطعم وفلترة المطاعم القريبة
      final nearbyBusinesses = <BusinessModel>[];
      
      for (final business in allBusinessesResponse.businesses) {
        if (business.latitude != null && business.longitude != null) {
          final distance = business.calculateDistanceFrom(userLatitude, userLongitude);
          
          if (distance != null && distance <= maxDistanceKm) {
            // إنشاء نسخة جديدة مع المسافة المحسوبة
            final businessWithDistance = business.copyWithCalculatedDistance(
              userLatitude, 
              userLongitude
            );
            nearbyBusinesses.add(businessWithDistance);
          }
        }
      }

      // ترتيب حسب المسافة (الأقرب أولاً)
      nearbyBusinesses.sort((a, b) {
        final distanceA = a.calculateDistanceFrom(userLatitude, userLongitude);
        final distanceB = b.calculateDistanceFrom(userLatitude, userLongitude);
        
        if (distanceA == null && distanceB == null) return 0;
        if (distanceA == null) return 1;
        if (distanceB == null) return -1;
        
        return distanceA.compareTo(distanceB);
      });

      // إرجاع العدد المطلوب فقط
      return nearbyBusinesses.take(limit).toList();
      
    } catch (e) {
      debugPrint('خطأ في جلب المطاعم القريبة: $e');
      return [];
    }
  }
}

/// نموذج استجابة قائمة المتاجر مع معلومات pagination
class BusinessListResponse {
  final List<BusinessModel> businesses;
  final bool hasMore;
  final int total;
  final int page;
  final int count;

  BusinessListResponse({
    required this.businesses,
    required this.hasMore,
    required this.total,
    required this.page,
    required this.count,
  });
}
