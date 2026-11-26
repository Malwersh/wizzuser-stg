import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodapp_user/models/home_navigation.dart';
import 'package:foodapp_user/widgets/discovery/home_discovery_header.dart';

void main() {
  test(
    'renewed signed URL reuses decoded image; replacing upload invalidates it',
    () {
      HomeTypeCategory category(String signature, String key) {
        final item = HomeNavigationItem.fromJson({
          'id': 'pizza',
          'label': 'بيتزا',
          'kind': 'cuisine',
          'value': 'pizza',
          'imageKey': key,
          'imageUrl': 'https://example.com/$key?signature=$signature',
        });
        return HomeTypeCategory(
          item.id,
          item.label,
          item.asset,
          imageUrl: item.imageUrl,
          imageKey: item.imageKey,
        );
      }

      CachedNetworkImageProvider provider(HomeTypeCategory c) =>
          CachedNetworkImageProvider(c.imageUrl!, cacheKey: c.imageCacheKey);
      final first = provider(
        category('one', 'home-slideshow/upload-one/image.jpg'),
      );
      final refresh = provider(
        category('two', 'home-slideshow/upload-one/image.jpg'),
      );
      final replacement = provider(
        category('three', 'home-slideshow/upload-two/image.jpg'),
      );
      expect(first, refresh);
      expect(first.hashCode, refresh.hashCode);
      expect(first, isNot(replacement));
    },
  );
  test(
    'legacy images keep their full URL identity instead of stripping parameters',
    () {
      const c = HomeTypeCategory(
        'x',
        'تصنيف',
        'asset',
        imageUrl: 'https://example.com/image?v=2',
      );
      expect(c.imageCacheKey, c.imageUrl);
    },
  );
}
