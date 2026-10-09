import 'dart:developer' as developer;
import '../constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'dart:async';

// Force recompilation

class RobustNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const RobustNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<RobustNetworkImage> createState() => _RobustNetworkImageState();
}

class _RobustNetworkImageState extends State<RobustNetworkImage> {
  ImageProvider? _imageProvider;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(RobustNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  String _getOptimizedImageUrl(String originalUrl) {
    if (originalUrl.isEmpty) return originalUrl;
    
    // معالجة خاصة لصور AWS S3 - إزالة معايير cache busting المسببة للمشاكل
    if (originalUrl.contains('amazonaws.com') || originalUrl.contains('s3.')) {
      // فقط إضافة معامل timestamp بسيط
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final separator = originalUrl.contains('?') ? '&' : '?';
      return '$originalUrl${separator}t=$timestamp';
    }
    
    return originalUrl;
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final optimizedUrl = _getOptimizedImageUrl(widget.imageUrl);
      developer.log('🔄 Loading robust image: $optimizedUrl');

      // For Flutter web with S3, use NetworkImage directly as it handles CORS and binary data better
      final imageProvider = NetworkImage(optimizedUrl);
      
      // Test if the image can be decoded
      await _validateImageProvider(imageProvider);
      
      setState(() {
        _imageProvider = imageProvider;
        _isLoading = false;
        _hasError = false;
      });
      developer.log('✅ Robust image loaded successfully: $optimizedUrl');
      return;
      
    } catch (e) {
      developer.log('🚨 Robust image loading error: $e');
      
      // Fallback: Try original URL without optimization
      try {
        final fallbackProvider = NetworkImage(widget.imageUrl);
        await _validateImageProvider(fallbackProvider);
        
        setState(() {
          _imageProvider = fallbackProvider;
          _isLoading = false;
          _hasError = false;
        });
        developer.log('🔄 Fallback image loaded with original URL: ${widget.imageUrl}');
        return;
      } catch (fallbackError) {
        developer.log('🚨 Fallback also failed: $fallbackError');
      }
      
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _validateImageProvider(ImageProvider provider) async {
    final completer = Completer<void>();
    
    final imageStream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        imageStream.removeListener(listener);
        completer.complete();
      },
      onError: (dynamic exception, StackTrace? stackTrace) {
        imageStream.removeListener(listener);
        completer.completeError(exception);
      },
    );
    
    imageStream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 10));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ?? 
        Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        );
    }

    if (_hasError || _imageProvider == null) {
      return widget.errorWidget ?? 
        Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.restaurant,
                size: widget.width != null ? widget.width! * 0.3 : 40,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 8),
              Text(
                'صورة المطعم',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: _imageProvider!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit ?? BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: child,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            developer.log('🚨 Image display error: $error');
            return widget.errorWidget ?? 
              Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image,
                      size: widget.width != null ? widget.width! * 0.3 : 40,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'فشل تحميل الصورة',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
          },
        ),
      ),
    );
  }
}
