import 'storefront_pricing.dart';
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
  static BusinessModel parseBusiness(dynamic value) {
    final data = Map<String, dynamic>.from(value as Map);
    final business = BusinessModel.fromJson(data);
    StorefrontPricing.instance.seedBusiness(
      business.id,
      business.metadata ?? data,
    );
    return business;
  }

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
      final response = await http.get(url, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['business'] != null) {
          return parseBusiness(data['business']);
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
  static Future<List<CategoryModel>> getBusinessCategories(
    String businessId,
  ) async {
    try {
      final url = Uri.parse('$_baseUrl/business/$businessId/categories');
      final response = await http.get(url, headers: await _getHeaders());

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
      final url = Uri.parse(
        '$_baseUrl/category/$categoryId/products?page=$page&limit=$limit',
      );
      final response = await http.get(url, headers: await _getHeaders());

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
      final url = Uri.parse(
        '$_baseUrl/business/$businessId/products?page=$page&limit=$limit',
      );
      final response = await http.get(url, headers: await _getHeaders());

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
  static Future<ProductModel?> getProductDetails(
    String businessId,
    String productId,
  ) async {
    try {
      final url = Uri.parse('$_baseUrl/product/$productId');
      final response = await http.get(url, headers: await _getHeaders());

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
  static Future<Map<String, List<ProductModel>>>
  getBusinessCategoriesAndProducts(String businessId) async {
    try {
      debugPrint('🔍 جاري جلب منتجات المطعم: $businessId');

      // نجلب الفئات أيضاً لربط categoryId بالاسم الحقيقي عند غياب categoryName.
      final categoriesFuture = getBusinessCategories(businessId);

      // جلب جميع منتجات المطعم من المسار الجديد
      final url = Uri.parse('$_baseUrl/business/$businessId/products');
      debugPrint('📡 استدعاء API: $url');

      final response = await http.get(url, headers: await _getHeaders());

      debugPrint('📊 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📦 Response Data: ${data.keys.toList()}');

        if (data['success'] == true && data['products'] != null) {
          final List<dynamic> productsJson = data['products'];
          debugPrint('✅ تم جلب ${productsJson.length} منتج من API');

          final categories = await categoriesFuture;
          final categoryNameById = <String, String>{
            for (final category in categories)
              if (category.categoryId.trim().isNotEmpty &&
                  category.categoryName.trim().isNotEmpty)
                category.categoryId.trim(): category.categoryName.trim(),
          };

          final products =
              productsJson.map((json) => ProductModel.fromJson(json)).toList();

          // تجميع المنتجات حسب الفئات مباشرة من categoryName
          final Map<String, List<ProductModel>> result = {};
          int productsWithCategory = 0;
          int productsWithoutCategory = 0;

          for (final product in products) {
            String categoryName;

            final rawCategoryName = product.categoryName?.trim() ?? '';
            final rawCategoryId = product.categoryId.trim();

            // 1) اسم الفئة القادم من المنتج (إن كان صالحاً)
            if (rawCategoryName.isNotEmpty &&
                !_looksLikeOpaqueId(rawCategoryName)) {
              categoryName = rawCategoryName;
              productsWithCategory++;
            } else if (rawCategoryId.isNotEmpty &&
                categoryNameById.containsKey(rawCategoryId)) {
              // 2) fallback: اسم الفئة الحقيقي عبر categoryId
              categoryName = categoryNameById[rawCategoryId]!;
              productsWithCategory++;
            } else {
              // 4) إذا كان المعرّف UUID/opaque أو مفقوداً، نستخدم اسم آمن للعرض.
              categoryName = 'منتجات أخرى';
              productsWithoutCategory++;
              debugPrint(
                '⚠️ منتج بدون اسم فئة قابل للعرض: ${product.name} (categoryId=$rawCategoryId, categoryName=$rawCategoryName)',
              );
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
          debugPrint(
            '⚠️ Response success=${data["success"]}, has products=${data["products"] != null}',
          );
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
      final response = await http.get(url, headers: await _getHeaders());

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

  /// التحقق إن كان النص يشبه معرفاً خاماً (UUID أو token طويل) وليس اسماً مناسباً للعرض.
  static bool _looksLikeOpaqueId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return true;

    // UUID v4/v1 الشائع
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (uuidRegex.hasMatch(normalized)) return true;

    // token طويل مكوّن من حروف/أرقام/فواصل ويبدو غير قابل للقراءة
    final compact = normalized.replaceAll(RegExp(r'[\s_-]'), '');
    final opaqueTokenRegex = RegExp(r'^[0-9a-zA-Z]{24,}$');
    if (opaqueTokenRegex.hasMatch(compact)) {
      final hasDigit = RegExp(r'\d').hasMatch(compact);
      final hasLetter = RegExp(r'[A-Za-z]').hasMatch(compact);
      if (hasDigit && hasLetter) return true;
    }

    return false;
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
      final endpoint =
          '/businesses?${queryParams.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';

      final url = Uri.parse('$_baseUrl$endpoint');

      debugPrint('🔗 API URL: $url');
      debugPrint('📡 Headers: ${await _getHeaders()}');

      final response = await http.get(url, headers: await _getHeaders());

      debugPrint('📡 Response Status: ${response.statusCode}');
      debugPrint('📡 Response Headers: ${response.headers}');
      debugPrint('📡 Response Body Length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📊 Success: ${data['success']}');
        debugPrint('📊 Businesses Count: ${data['businesses']?.length ?? 0}');

        if (data['success'] == true && data['businesses'] != null) {
          final businesses =
              (data['businesses'] as List)
                  .map((business) => parseBusiness(business))
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
      final endpoint =
          '/businesses?${queryParams.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';

      final url = Uri.parse('$_baseUrl$endpoint');

      debugPrint('🔗 API URL: $url');

      final response = await http.get(url, headers: await _getHeaders());

      debugPrint('📡 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📊 Success: ${data['success']}');
        debugPrint('📊 Businesses Count: ${data['businesses']?.length ?? 0}');
        debugPrint('📊 Has More: ${data['hasMore']}');
        debugPrint('📊 Total: ${data['total']}');

        if (data['success'] == true && data['businesses'] != null) {
          final businesses =
              (data['businesses'] as List)
                  .map((business) => parseBusiness(business))
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
      final uri = Uri.parse(
        '$_baseUrl${ApiConfig.getNearbyBusinessesEndpoint}',
      ).replace(
        queryParameters: {
          'latitude': userLatitude.toString(),
          'longitude': userLongitude.toString(),
          'radius_km': maxDistanceKm.toString(),
          'limit': limit.toString(),
        },
      );
      final response = await http
          .get(uri, headers: await _getHeaders())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final payload = jsonDecode(response.body);
      if (payload['success'] != true) return [];
      return (payload['data']['businesses'] as List)
          .map(parseBusiness)
          .toList();
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
