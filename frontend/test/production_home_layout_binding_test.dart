import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:foodapp_user/config/api_config.dart';
import 'package:foodapp_user/services/home_slideshow_service.dart';

void main() {
  test('home layout uses the correct environment and region', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.scheme, 'https');
      expect(request.url.queryParameters['layoutVersion'], '3');
      expect(
        request.url.queryParameters['slideActions'],
        ApiConfig.isProduction ? '2' : null,
      );
      expect(request.url.queryParameters['regionId'], 'test-region');
      expect(
        request.url.path,
        ApiConfig.isProduction
            ? '/production/customer/home-layout'
            : '/staging/staff/public/home-slideshow',
      );
      return http.Response(
        jsonEncode({
          'version': 0,
          'slides': [
            if (ApiConfig.isProduction)
              {
                'id': 'banner',
                'title': 'إعلان',
                'imageUrl': 'https://example.com/banner.gif',
                'endAt': '2026-12-01T00:00:00.000Z',
                'action': {'type': 'announcement', 'id': 'banner'},
              },
          ],
          'layout': {'configured': true, 'version': 7, 'sections': []},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final result = await HomeSlideshowService(
      client: client,
    ).load(regionId: 'test-region');
    expect(result.layout?.configured, true);
    expect(result.layout?.sections, isEmpty);
    if (ApiConfig.isProduction) {
      expect(HomeSlideshowService.baseUrl, isEmpty);
      expect(result.slides.single.actionType, 'announcement');
      expect(result.slides.single.title, 'إعلان');
    } else {
      expect(result.slides, isEmpty);
    }
  });

  test(
    'campaign list and offer detail use the same environment as home',
    () async {
      final requests = <Uri>[];
      final slide = {
        'id': 'offer',
        'title': 'حملة الخصم',
        'imageUrl': 'https://example.com/offer.gif',
        'imageVersion': 'media-v1',
        'standalone': true,
        'endAt': '2026-12-01T00:00:00.000Z',
        'action': {
          'type': 'campaign',
          'id': 'offer',
          'offerSource': 'platform',
        },
      };
      final service = HomeSlideshowService(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'campaigns': [slide],
              'slide': slide,
              'offer': {'imageUrl': slide['imageUrl']},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect((await service.campaigns()).single.imageUrl, slide['imageUrl']);
      expect((await service.campaign('offer')).standalone, true);
      final detail = await service.details(
        'offer',
        merchantId: 'branch',
        standalone: true,
      );
      expect(detail['offer']['imageUrl'], slide['imageUrl']);
      expect(requests.length, 3);
      expect(requests.first.queryParameters['campaigns'], '1');
      expect(requests.last.queryParameters['campaignId'], 'offer');
      expect(requests.last.queryParameters['merchantId'], 'branch');
      if (ApiConfig.isProduction) {
        expect(
          requests.every(
            (url) => url.host == Uri.parse(HomeSlideshowService.layoutUrl).host,
          ),
          true,
        );
        expect(
          requests.every(
            (url) => url.path == '/production/customer/home-layout',
          ),
          true,
        );
      } else {
        expect(requests.first.path, '/staging/staff/public/home-slideshow');
        expect(requests.last.path, '/staging/staff/public/home-offer');
      }
    },
  );
}
