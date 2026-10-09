import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;

class RestaurantImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const RestaurantImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: Icon(Icons.restaurant, color: Colors.grey, size: 30),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // إذا كان الرابط فارغ، اعرض placeholder
    if (imageUrl.isEmpty) {
      return _buildPlaceholder();
    }

    developer.log('RestaurantImage: تحميل الصورة من: $imageUrl');

    Widget imageWidget;
    
    if (kIsWeb) {
      // للويب: استخدم FutureBuilder مع تحميل مخصص
      imageWidget = FutureBuilder<Uint8List?>(
        future: _loadImageForWeb(imageUrl),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingWidget();
          }
          
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            developer.log('RestaurantImage: فشل في تحميل الصورة: ${snapshot.error}');
            return _buildPlaceholder();
          }

          return Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              developer.log('RestaurantImage: خطأ في عرض الصورة: $error');
              return _buildPlaceholder();
            },
          );
        },
      );
    } else {
      // للموبايل: استخدم CachedNetworkImage مع إعدادات محسنة
      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        httpHeaders: const {
          'Accept': 'image/*',
          'User-Agent': 'Flutter-App/1.0',
        },
        placeholder: (context, url) => _buildLoadingWidget(),
        errorWidget: (context, url, error) {
          developer.log('RestaurantImage: خطأ CachedNetworkImage: $error');
          return _buildPlaceholder();
        },
      );
    }

    // إضافة BorderRadius إذا تم تحديده
    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  // تحميل خاص للويب مع معالجة مشاكل AWS S3
  Future<Uint8List?> _loadImageForWeb(String url) async {
    try {
      developer.log('RestaurantImage: بدء تحميل البيانات من: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'image/*,*/*',
          'User-Agent': 'Flutter-Web-App/1.0',
          'Cache-Control': 'no-cache',
        },
      );

      developer.log('RestaurantImage: استجابة HTTP: ${response.statusCode}');
      developer.log('RestaurantImage: Content-Type: ${response.headers['content-type']}');
      developer.log('RestaurantImage: حجم البيانات: ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        
        if (bytes.isNotEmpty) {
          // فحص بداية الملف
          final header = bytes.take(10).toList();
          developer.log('RestaurantImage: رأس الملف: ${header.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
          
          // فحص إذا كانت البيانات صورة صحيحة
          if (_isValidImageHeader(bytes)) {
            developer.log('RestaurantImage: الصورة صحيحة، تم التحميل بنجاح');
            return bytes;
          } else {
            developer.log('RestaurantImage: البيانات لا تحتوي على صورة صحيحة');
            return null;
          }
        }
      }
      
      developer.log('RestaurantImage: فشل في تحميل الصورة - كود الحالة: ${response.statusCode}');
      return null;
    } catch (e) {
      developer.log('RestaurantImage: خطأ في تحميل الصورة: $e');
      return null;
    }
  }

  // فحص صحة بيانات الصورة
  bool _isValidImageHeader(Uint8List bytes) {
    if (bytes.length < 4) return false;

    // فحص JPEG (FF D8)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return true;
    }
    
    // فحص PNG (89 50 4E 47)
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return true;
    }
    
    // فحص GIF (47 49 46)
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    
    // فحص WebP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return true;
    }

    return false;
  }
}
