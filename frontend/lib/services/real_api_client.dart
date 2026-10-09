import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class RealApiClient {
  static final RealApiClient _instance = RealApiClient._internal();
  factory RealApiClient() => _instance;
  RealApiClient._internal();
  
  final Map<String, String> _defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// GET request to real API
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? headers}) async {
    try {
      final url = Uri.parse(ApiConfig.buildUrl(endpoint));
      
      debugPrint('🌐 API Request: GET $url');
      
      final response = await http.get(
        url,
        headers: {..._defaultHeaders, ...?headers},
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('📡 Response Status: ${response.statusCode}');
      debugPrint('📡 Response Headers: ${response.headers}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ API Success: ${data.keys.toList()}');
        return data;
      } else {
        debugPrint('❌ API Error: ${response.statusCode} - ${response.body}');
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Network Error: $e');
      throw Exception('Network Error: $e');
    }
  }

  /// POST request to real API
  Future<Map<String, dynamic>> post(String endpoint, {Map<String, dynamic>? body, Map<String, String>? headers}) async {
    try {
      final url = Uri.parse(ApiConfig.buildUrl(endpoint));
      
      debugPrint('🌐 API Request: POST $url');
      debugPrint('📤 Request Body: ${json.encode(body)}');
      
      final response = await http.post(
        url,
        headers: {..._defaultHeaders, ...?headers},
        body: body != null ? json.encode(body) : null,
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('📡 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        debugPrint('✅ API Success: ${data.keys.toList()}');
        return data;
      } else {
        debugPrint('❌ API Error: ${response.statusCode} - ${response.body}');
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Network Error: $e');
      throw Exception('Network Error: $e');
    }
  }

  /// PUT request to real API
  Future<Map<String, dynamic>> put(String endpoint, {Map<String, dynamic>? body, Map<String, String>? headers}) async {
    try {
      final url = Uri.parse(ApiConfig.buildUrl(endpoint));
      
      debugPrint('🌐 API Request: PUT $url');
      debugPrint('📤 Request Body: ${json.encode(body)}');
      
      final response = await http.put(
        url,
        headers: {..._defaultHeaders, ...?headers},
        body: body != null ? json.encode(body) : null,
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('📡 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ API Success: ${data.keys.toList()}');
        return data;
      } else {
        debugPrint('❌ API Error: ${response.statusCode} - ${response.body}');
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Network Error: $e');
      throw Exception('Network Error: $e');
    }
  }

  /// DELETE request to real API
  Future<Map<String, dynamic>> delete(String endpoint, {Map<String, String>? headers}) async {
    try {
      final url = Uri.parse(ApiConfig.buildUrl(endpoint));
      
      debugPrint('🌐 API Request: DELETE $url');
      
      final response = await http.delete(
        url,
        headers: {..._defaultHeaders, ...?headers},
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('📡 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ API Success: ${data.keys.toList()}');
        return data;
      } else {
        debugPrint('❌ API Error: ${response.statusCode} - ${response.body}');
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Network Error: $e');
      throw Exception('Network Error: $e');
    }
  }
}

