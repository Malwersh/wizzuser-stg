import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ImageCacheService {
  // Cache manager بسيط للصور
  static final customCacheManager = CacheManager(
    Config(
      'restaurant_images',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: 'restaurant_images'),
    ),
  );

  // تنظيف الكاش
  static Future<void> clearCache() async {
    await customCacheManager.emptyCache();
  }

  // تحديد حجم الكاش
  static Future<int> getCacheSize() async {
    final info = await customCacheManager.getFileStream('').length;
    return info;
  }
}
