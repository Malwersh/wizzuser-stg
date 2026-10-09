import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

class WebImageHelper {
  // Check if we're running on web
  static bool get isWeb => kIsWeb;
  
  // Convert AWS S3 URL to be more web-compatible
  static String makeWebCompatible(String imageUrl) {
    if (!isWeb || imageUrl.isEmpty) return imageUrl;
    
    // For AWS S3 URLs, add cache busting and ensure proper headers
    if (imageUrl.contains('amazonaws.com') || imageUrl.contains('s3.')) {
      // Add cache busting parameter
      final separator = imageUrl.contains('?') ? '&' : '?';
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 3600000; // Change every hour
      return '$imageUrl${separator}cb=$timestamp';
    }
    
    return imageUrl;
  }
  
  // Get fallback image based on context
  static String getFallbackImage(String context) {
    switch (context) {
      case 'restaurant':
        return 'assets/images/restaurant_placeholder.png';
      case 'food':
        return 'assets/images/food_placeholder.png';
      case 'avatar':
        return 'assets/images/user_placeholder.png';
      default:
        return 'assets/images/placeholder.png';
    }
  }
  
  // Check if URL is a valid image URL
  static bool isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    
    // Check if it's a valid HTTP/HTTPS URL
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    
    // Check if it has a valid scheme
    if (!uri.hasScheme || (!uri.scheme.startsWith('http') && !uri.scheme.startsWith('asset'))) {
      return false;
    }
    
    return true;
  }
  
  // Log image loading issues for debugging
  static void logImageError(String imageUrl, Object error) {
    if (kDebugMode) {
      developer.log('🚨 Image loading error:');
      developer.log('   URL: $imageUrl');
      developer.log('   Error: $error');
      developer.log('   Is web: $isWeb');
      developer.log('   Is AWS S3: ${imageUrl.contains('amazonaws.com')}');
    }
  }
}
