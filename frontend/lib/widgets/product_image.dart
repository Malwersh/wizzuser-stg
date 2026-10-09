import 'dart:developer' as developer;
import '../constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Widget محسن لعرض صور المنتجات مع معالجة مشاكل AWS S3 Content-Type
class ProductImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const ProductImage({
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
        color: Colors.grey[150],
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: Icon(
          Icons.fastfood,
          color: Colors.grey,
          size: 30,
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // إذا كان الرابط فارغ، اعرض placeholder
    if (imageUrl.isEmpty) {
      developer.log('ProductImage: رابط فارغ - عرض placeholder');
      return _buildPlaceholder();
    }

    developer.log('ProductImage: تحميل صورة المنتج من: $imageUrl');
    developer.log('ProductImage: Platform - Web: $kIsWeb');

    Widget imageWidget;
    
    // تجربة كل من الويب والموبايل مع Image.network أولاً
    imageWidget = Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      headers: const {
        'Accept': 'image/jpeg,image/png,image/webp,image/*,*/*',
        'User-Agent': 'Flutter-App/1.0',
        'Cache-Control': 'no-cache',
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          developer.log('✅ ProductImage: تم تحميل الصورة بنجاح');
          return child;
        }
        final progress = loadingProgress.expectedTotalBytes != null
            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
            : null;
        developer.log('🔄 ProductImage: تحميل... ${progress != null ? '${(progress * 100).toInt()}%' : 'غير معروف'}');
        return _buildLoadingWidget();
      },
      errorBuilder: (context, error, stackTrace) {
        developer.log('❌ ProductImage: خطأ Image.network: $error');
        developer.log('   StackTrace: $stackTrace');
        
        // إذا فشل Image.network، جرب الطريقة المخصصة
        if (kIsWeb) {
          developer.log('🔄 ProductImage: محاولة التحميل المخصص للويب...');
          return FutureBuilder<Uint8List?>(
            future: _loadImageForWeb(imageUrl),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingWidget();
              }
              
              if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                developer.log('❌ ProductImage: فشل التحميل المخصص: ${snapshot.error}');
                return _buildPlaceholder();
              }

              return Image.memory(
                snapshot.data!,
                width: width,
                height: height,
                fit: fit,
                errorBuilder: (context, error, stackTrace) {
                  developer.log('❌ ProductImage: خطأ في عرض Image.memory: $error');
                  return _buildPlaceholder();
                },
              );
            },
          );
        }
        
        return _buildPlaceholder();
      },
    );

    // إضافة BorderRadius إذا تم تحديده
    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  // تحميل خاص للويب مع معالجة مشاكل AWS S3 Content-Type
  Future<Uint8List?> _loadImageForWeb(String url) async {
    try {
      developer.log('ProductImage: بدء تحميل البيانات من: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'image/*,*/*',
          'User-Agent': 'Flutter-Web-App/1.0',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 15));

      developer.log('ProductImage: استجابة HTTP: ${response.statusCode}');
      developer.log('ProductImage: Content-Type: ${response.headers['content-type']}');
      developer.log('ProductImage: Content-Length: ${response.headers['content-length']}');

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        
        // فحص إذا كانت البيانات صورة صحيحة
        if (_isValidImageData(bytes)) {
          developer.log('✅ ProductImage: تم تحميل البيانات بنجاح (${bytes.length} bytes)');
          return bytes;
        } else {
          developer.log('❌ ProductImage: البيانات ليست صورة صحيحة');
          return null;
        }
      } else {
        developer.log('❌ ProductImage: فشل HTTP: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      developer.log('❌ ProductImage: خطأ في التحميل: $e');
      return null;
    }
  }

  // فحص بسيط للتأكد من أن البيانات صورة
  bool _isValidImageData(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    
    // فحص بداية ملفات الصور الشائعة
    // JPEG: FF D8 FF
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 && 
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
      return true;
    }
    
    // WebP: RIFF...WEBP
    if (bytes.length >= 12 && 
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return true;
    }
    
    // GIF: GIF87a or GIF89a
    if (bytes.length >= 6 && 
        bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
        bytes[3] == 0x38 && (bytes[4] == 0x37 || bytes[4] == 0x39) && bytes[5] == 0x61) {
      return true;
    }
    
    return false;
  }
}
