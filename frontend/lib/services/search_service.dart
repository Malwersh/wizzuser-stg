import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/store.dart';
import '../config/api_config.dart';

class SearchService {
  static String get _baseUrl {
    final url = ApiConfig.baseUrl;
    if (url.isEmpty) {
      throw StateError('Missing API_URL (dart-define)');
    }
    return url;
  }
  
  Timer? _debounceTimer;
  final Map<String, List<Store>> _searchCache = {};

  // البحث الأساسي في المتاجر
  Future<List<Store>> searchStores(String query, {
    String? category,
    double? latitude,
    double? longitude,
    int? radius,
  }) async {
    if (query.trim().isEmpty) return [];

    // التحقق من الكاش أولاً
    final cacheKey = _generateCacheKey(query, category, latitude, longitude);
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      final response = await _performSearchRequest(
        query: query,
        category: category,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<Store> stores = (data['stores'] as List)
            .map((storeJson) => Store.fromJson(storeJson))
            .toList();

        // حفظ في الكاش
        _searchCache[cacheKey] = stores;
        
        // تنظيف الكاش إذا أصبح كبيراً
        if (_searchCache.length > 50) {
          _searchCache.clear();
        }

        return stores;
      } else {
        throw Exception('فشل في البحث: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('خطأ في البحث: $e');
      return [];
    }
  }

  // إجراء طلب البحث للباك إند
  Future<http.Response> _performSearchRequest({
    required String query,
    String? category,
    double? latitude,
    double? longitude,
    int? radius,
  }) async {
    final Map<String, dynamic> params = {
      'q': query,
      'lang': 'ar',
    };

    if (category != null) params['category'] = category;
    if (latitude != null) params['lat'] = latitude.toString();
    if (longitude != null) params['lng'] = longitude.toString();
    if (radius != null) params['radius'] = radius.toString();

    final uri = Uri.parse('$_baseUrl/search/stores').replace(
      queryParameters: params,
    );

    return await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Language': 'ar',
      },
    ).timeout(const Duration(seconds: 10));
  }

  // توليد مفتاح الكاش
  String _generateCacheKey(String query, String? category, double? lat, double? lng) {
    return '$query|$category|$lat|$lng'.toLowerCase();
  }

  // البحث الشائع
  Future<List<String>> getPopularSearches() async {
    return [
      'برجر',
      'بيتزا', 
      'دجاج مقلي',
      'سوشي',
      'شاورما',
      'مأكولات آسيوية',
      'معجنات',
      'مشروبات',
      'حلويات',
      'مأكولات بحرية',
    ];
  }

  // البحث المحلي في المتاجر
  List<Store> searchLocalStores(String query, List<Store> stores) {
    final normalizedQuery = _normalizeSearchText(query);
    
    return stores.where((store) {
      final storeName = _normalizeSearchText(store.name);
      final storeCategory = _normalizeSearchText(store.category ?? '');
      
      return storeName.contains(normalizedQuery) || 
             storeCategory.contains(normalizedQuery) ||
             _isPartialMatch(storeName, normalizedQuery) ||
             _isPartialMatch(storeCategory, normalizedQuery);
    }).toList();
  }

  // تنظيف الكاش
  void clearCache() {
    _searchCache.clear();
  }

  // إلغاء العمليات المعلقة
  void dispose() {
    _debounceTimer?.cancel();
  }

  // Helper Methods
  String _normalizeSearchText(String text) {
    if (text.isEmpty) return '';
    
    String normalized = text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'), '')
        .replaceAll('آ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[^\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFFa-zA-Z\s]'), '')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    return normalized;
  }

  bool _isPartialMatch(String text, String query) {
    if (text.isEmpty || query.isEmpty) return false;
    
    final normalizedText = _normalizeSearchText(text);
    final normalizedQuery = _normalizeSearchText(query);
    
    if (normalizedText.contains(normalizedQuery)) return true;
    
    final textWords = normalizedText.split(' ');
    final queryWords = normalizedQuery.split(' ');
    
    for (String queryWord in queryWords) {
      if (queryWord.isNotEmpty) {
        bool wordFound = false;
        for (String textWord in textWords) {
          if (textWord.startsWith(queryWord) || textWord.contains(queryWord)) {
            wordFound = true;
            break;
          }
        }
        if (!wordFound) return false;
      }
    }
    
    return true;
  }
}

// مثيل عام للخدمة
final SearchService searchService = SearchService();
