import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/google_places_config.dart';

/// 🔥 Custom Google Places Service - بدون مكتبات خارجية
/// يستخدم Google Places API مباشرة مع Session Token و Caching
class GooglePlacesService {
  final String apiKey;
  String? _sessionToken;
  Timer? _sessionTimer;
  
  // Cache للنتائج
  final Map<String, List<PlacePrediction>> _searchCache = {};
  
  GooglePlacesService({String? apiKey}) 
      : apiKey = apiKey ?? _getDefaultApiKey() {
    _loadCache();
  }
  
  static String _getDefaultApiKey() {
    // استخدم iOS key لأنه أقل تقييداً في الـ HTTP requests
    if (Platform.isIOS) {
      return GooglePlacesConfig.httpKey;
    }
    // للـ Android، استخدم نفس الـ key مؤقتاً
    return GooglePlacesConfig.httpKey; // تغيير مؤقت للاختبار
  }
  
  /// 🎯 الحصول على Session Token (يجدد كل 3 دقائق)
  String get sessionToken {
    if (_sessionToken == null) {
      _generateNewSession();
    }
    return _sessionToken!;
  }
  
  void _generateNewSession() {
    _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
    
    // إلغاء Timer القديم
    _sessionTimer?.cancel();
    
    // تجديد الـ Session كل 3 دقائق
    _sessionTimer = Timer(const Duration(minutes: 3), () {
      _sessionToken = null;
    });
    
    print('🔑 Session Token جديد: $_sessionToken');
  }
  
  /// 🔍 البحث عن أماكن (Autocomplete)
  Future<List<PlacePrediction>> searchPlaces({
    required String query,
    String language = 'ar',
    List<String> countries = const ['iq'],
  }) async {
    if (query.isEmpty) return [];
    
    // تحقق من الـ Cache أولاً
    final cacheKey = '${query}_${language}_${countries.join(',')}';
    if (_searchCache.containsKey(cacheKey)) {
      print('💾 نتيجة من Cache: $query');
      return _searchCache[cacheKey]!;
    }
    
    try {
      final components = countries.isNotEmpty 
          ? 'country:${countries.join('|country:')}' 
          : '';
      
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&key=$apiKey'
        '&sessiontoken=$sessionToken'
        '&language=$language'
        '${components.isNotEmpty ? '&components=$components' : ''}'
      );
      
      print('🌐 API Request: ${url.toString().replaceAll(apiKey, 'HIDDEN')}');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final predictions = (data['predictions'] as List?)
              ?.map((p) => PlacePrediction.fromJson(p))
              .toList() ?? [];
          
          // حفظ في Cache
          _searchCache[cacheKey] = predictions;
          _saveCache();
          
          print('✅ وجدنا ${predictions.length} نتيجة للبحث: $query');
          return predictions;
        } else {
          print('⚠️ Google Places API Error: ${data['status']} - ${data['error_message']}');
          throw Exception('${data['status']}: ${data['error_message'] ?? 'Unknown error'}');
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ فشل البحث: $e');
      rethrow;
    }
  }
  
  /// 📍 الحصول على تفاصيل المكان (Place Details)
  Future<PlaceDetails> getPlaceDetails({
    required String placeId,
    String language = 'ar',
  }) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&key=$apiKey'
        '&sessiontoken=$sessionToken'
        '&language=$language'
        '&fields=geometry,formatted_address,name,address_components'
      );
      
      print('🌐 Details Request: ${url.toString().replaceAll(apiKey, 'HIDDEN')}');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          // بعد الحصول على التفاصيل، نجدد الـ Session
          _generateNewSession();
          
          print('✅ حصلنا على تفاصيل المكان: ${data['result']['name']}');
          return PlaceDetails.fromJson(data['result']);
        } else {
          print('⚠️ Details API Error: ${data['status']}');
          throw Exception(data['error_message'] ?? 'Failed to get place details');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ فشل الحصول على التفاصيل: $e');
      rethrow;
    }
  }
  
  /// 🌍 Reverse Geocoding - الحصول على عنوان من الإحداثيات
  Future<String> getAddressFromCoordinates({
    required double latitude,
    required double longitude,
    String language = 'ar',
  }) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$latitude,$longitude'
        '&key=$apiKey'
        '&language=$language'
      );
      
      print('🌍 Reverse Geocoding: $latitude, $longitude');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'] != null) {
          final results = data['results'] as List;
          
          if (results.isNotEmpty) {
            // 🎯 البحث عن أفضل عنوان (بالأولوية):
            // 1. عنوان يحتوي على neighborhood أو sublocality
            // 2. عنوان بدون Plus Codes
            // 3. عنوان بدون "طريق بدون اسم"
            
            String? bestAddress;
            
            // المحاولة الأولى: ابحث عن عنوان مع neighborhood
            for (var result in results) {
              final address = result['formatted_address'] as String;
              final types = result['types'] as List?;
              
              // تحقق من النوع - نفضل neighborhood, sublocality
              if (types != null && 
                  (types.contains('neighborhood') || 
                   types.contains('sublocality') ||
                   types.contains('sublocality_level_1'))) {
                if (!address.contains(RegExp(r'[A-Z0-9]{4}\+[A-Z0-9]{2,}')) &&
                    !address.contains('طريق بدون اسم') &&
                    !address.contains('Unnamed Road')) {
                  bestAddress = address;
                  print('✅ عنوان من neighborhood: $address');
                  break;
                }
              }
            }
            
            // المحاولة الثانية: ابحث عن أي عنوان جيد
            if (bestAddress == null) {
              for (var result in results) {
                final address = result['formatted_address'] as String;
                
                // تجنب Plus Codes والطرق بدون اسم
                if (!address.contains(RegExp(r'[A-Z0-9]{4}\+[A-Z0-9]{2,}')) &&
                    !address.contains('طريق بدون اسم') &&
                    !address.contains('Unnamed Road')) {
                  bestAddress = address;
                  print('✅ عنوان بديل جيد: $address');
                  break;
                }
              }
            }
            
            // المحاولة الثالثة: استخدم الأول (أفضل من لا شيء)
            if (bestAddress == null) {
              bestAddress = results[0]['formatted_address'] as String;
              print('⚠️ استخدام العنوان الأول (احتياطي): $bestAddress');
            }
            
            return bestAddress;
          }
        }
        
        throw Exception('No address found');
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ فشل Reverse Geocoding: $e');
      rethrow;
    }
  }
  
  /// 💾 حفظ Cache في SharedPreferences
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = _searchCache.map(
        (key, value) => MapEntry(
          key,
          value.map((p) => p.toJson()).toList(),
        ),
      );
      await prefs.setString('places_cache_v2', json.encode(cacheData));
      print('💾 تم حفظ ${_searchCache.length} عنصر في Cache');
    } catch (e) {
      print('⚠️ فشل حفظ Cache: $e');
    }
  }
  
  /// 📂 تحميل Cache من SharedPreferences
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheString = prefs.getString('places_cache_v2');
      
      if (cacheString != null) {
        final cacheData = json.decode(cacheString) as Map<String, dynamic>;
        
        cacheData.forEach((key, value) {
          _searchCache[key] = (value as List)
              .map((p) => PlacePrediction.fromJson(p))
              .toList();
        });
        
        print('📂 تم تحميل ${_searchCache.length} عنصر من Cache');
      }
    } catch (e) {
      print('⚠️ فشل تحميل Cache: $e');
    }
  }
  
  /// 🗑️ مسح Cache
  Future<void> clearCache() async {
    _searchCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('places_cache_v2');
    print('🗑️ تم مسح Cache');
  }
  
  /// 🧹 Cleanup
  void dispose() {
    _sessionTimer?.cancel();
  }
}

/// 📍 نموذج نتيجة البحث
class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;
  
  PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
  
  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structuredFormatting = json['structured_formatting'] as Map<String, dynamic>?;
    
    return PlacePrediction(
      placeId: json['place_id'] as String,
      description: json['description'] as String,
      mainText: structuredFormatting?['main_text'] as String? ?? json['description'] as String,
      secondaryText: structuredFormatting?['secondary_text'] as String? ?? '',
    );
  }
  
  Map<String, dynamic> toJson() => {
    'place_id': placeId,
    'description': description,
    'structured_formatting': {
      'main_text': mainText,
      'secondary_text': secondaryText,
    },
  };
}

/// 🗺️ نموذج تفاصيل المكان
class PlaceDetails {
  final double latitude;
  final double longitude;
  final String formattedAddress;
  final String name;
  final Map<String, String> addressComponents;
  
  PlaceDetails({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.name,
    required this.addressComponents,
  });
  
  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;
    
    // استخراج مكونات العنوان
    final components = <String, String>{};
    final addressComponentsList = json['address_components'] as List?;
    
    if (addressComponentsList != null) {
      for (var component in addressComponentsList) {
        final types = component['types'] as List;
        final longName = component['long_name'] as String;
        
        for (var type in types) {
          components[type] = longName;
        }
      }
    }
    
    return PlaceDetails(
      latitude: location['lat'] as double,
      longitude: location['lng'] as double,
      formattedAddress: json['formatted_address'] as String? ?? '',
      name: json['name'] as String? ?? '',
      addressComponents: components,
    );
  }
  
  /// الحصول على اسم المدينة
  String? get city {
    return addressComponents['locality'] 
        ?? addressComponents['administrative_area_level_1'];
  }
  
  /// الحصول على اسم الحي
  String? get neighborhood {
    return addressComponents['neighborhood'] 
        ?? addressComponents['sublocality'];
  }
}
