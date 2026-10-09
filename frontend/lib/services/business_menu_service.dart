import 'dart:developer' as developer;
// خدمة جلب فئات ومنتجات المطعم من قاعدة البيانات
import '../models/category_model.dart';
import '../models/product_model.dart';
import 'real_api_client.dart';

class BusinessMenuService {
  static final RealApiClient _apiClient = RealApiClient();

  /// جلب فئات المطعم من order-receiver-categories-dev
  static Future<List<CategoryModel>> getBusinessCategories(String businessId) async {
    try {
      developer.log('🔄 جلب فئات المطعم: $businessId');
      
      final response = await _apiClient.get('/businesses/$businessId/categories');
      
      if (response['success'] == true && response['categories'] != null) {
        final List<dynamic> categoriesJson = response['categories'];
        
        final categories = categoriesJson
            .map((json) => CategoryModel.fromJson(json))
            .where((category) => category.isActive)
            .toList();
        
        developer.log('✅ تم جلب ${categories.length} فئة للمطعم $businessId');
        return categories;
      }
      
      developer.log('⚠️ لم يتم العثور على فئات للمطعم $businessId');
      return [];
    } catch (e) {
      developer.log('❌ خطأ في جلب فئات المطعم $businessId: $e');
      return [];
    }
  }

  /// جلب منتجات فئة معينة من order-receiver-products-dev
  static Future<List<ProductModel>> getCategoryProducts(String businessId, String categoryId) async {
    try {
      developer.log('🔄 جلب منتجات الفئة: $categoryId للمطعم: $businessId');
      
      final response = await _apiClient.get('/businesses/$businessId/categories/$categoryId/products');
      
      if (response['success'] == true && response['products'] != null) {
        final List<dynamic> productsJson = response['products'];
        
        final products = productsJson
            .map((json) => ProductModel.fromJson(json))
            .where((product) => product.isAvailable)
            .toList();
        
        developer.log('✅ تم جلب ${products.length} منتج للفئة $categoryId');
        return products;
      }
      
      developer.log('⚠️ لم يتم العثور على منتجات للفئة $categoryId');
      return [];
    } catch (e) {
      developer.log('❌ خطأ في جلب منتجات الفئة $categoryId: $e');
      return [];
    }
  }

  /// جلب جميع منتجات المطعم مع فئاتها
  static Future<Map<CategoryModel, List<ProductModel>>> getBusinessMenu(String businessId) async {
    try {
      developer.log('🔄 جلب قائمة المطعم الكاملة: $businessId');
      
      final categories = await getBusinessCategories(businessId);
      final Map<CategoryModel, List<ProductModel>> menu = {};
      
      for (final category in categories) {
        final products = await getCategoryProducts(businessId, category.categoryId);
        menu[category] = products;
      }
      
      developer.log('✅ تم جلب قائمة المطعم: ${categories.length} فئة, ${menu.values.fold(0, (sum, products) => sum + products.length)} منتج');
      return menu;
    } catch (e) {
      developer.log('❌ خطأ في جلب قائمة المطعم $businessId: $e');
      return {};
    }
  }

  /// جلب منتج واحد بالتفصيل
  static Future<ProductModel?> getProductDetails(String productId) async {
    try {
      developer.log('🔄 جلب تفاصيل المنتج: $productId');
      
      final response = await _apiClient.get('/products/$productId');
      
      if (response['success'] == true && response['product'] != null) {
        final product = ProductModel.fromJson(response['product']);
        developer.log('✅ تم جلب تفاصيل المنتج: ${product.name}');
        return product;
      }
      
      developer.log('⚠️ لم يتم العثور على المنتج $productId');
      return null;
    } catch (e) {
      developer.log('❌ خطأ في جلب تفاصيل المنتج $productId: $e');
      return null;
    }
  }

  /// البحث في منتجات المطعم
  static Future<List<ProductModel>> searchBusinessProducts(String businessId, String query) async {
    try {
      developer.log('🔍 البحث في منتجات المطعم $businessId: "$query"');
      
      final response = await _apiClient.get('/businesses/$businessId/products/search?q=${Uri.encodeComponent(query)}');
      
      if (response['success'] == true && response['products'] != null) {
        final List<dynamic> productsJson = response['products'];
        
        final products = productsJson
            .map((json) => ProductModel.fromJson(json))
            .where((product) => product.isAvailable)
            .toList();
        
        developer.log('✅ تم العثور على ${products.length} منتج في البحث');
        return products;
      }
      
      developer.log('⚠️ لم يتم العثور على نتائج للبحث "$query"');
      return [];
    } catch (e) {
      developer.log('❌ خطأ في البحث: $e');
      return [];
    }
  }
}
