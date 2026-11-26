import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:foodapp_user/models/home_slide.dart';
import 'package:foodapp_user/screens/offer_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/config/api_config.dart';
import 'package:foodapp_user/models/browsing_location.dart';
import 'package:foodapp_user/services/browsing_location_service.dart';
import 'package:foodapp_user/services/home_slideshow_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BrowsingLocationService.instance.clear();
  });
  tearDown(() => BrowsingLocationService.instance.clear());

  Future<void> select(String region, {String source = 'gps'}) =>
      BrowsingLocationService.instance.select(
        BrowsingLocation(
          regionId: region,
          regionName: 'مركز المناذرة',
          source: source,
          latitude: 31.92,
          longitude: 44.46,
        ),
      );

  testWidgets('linked slide opens details using its offer ID', (tester) async {
    final requests = <http.Request>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: OfferDetailScreen(
        slide: HomeSlide.fromJson({
          'id': 'advertisement', 'title': 'إعلان', 'imageUrl': '', 'imageVersion': '1',
          'standalone': true, 'endAt': '2099-01-01T00:00:00Z',
          'action': {'type': 'campaign', 'id': 'linked-offer', 'offerSource': 'merchant'},
        }),
        openMerchant: (_) async {},
      )));
      await tester.pumpAndSettle();
    }, () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode({
        'offer': {'title': 'Linked merchant offer', 'type': 'percentage', 'value': 20},
      }), 200);
    }));
    expect(requests.single.url.queryParameters['campaignId'], 'linked-offer');
    expect(requests.single.url.queryParameters['offerSource'], 'merchant');
    expect(find.text('Linked merchant offer'), findsOneWidget);
  });

  test('header uses the environment home endpoint and browsing region', () async {
    await select('manathera');
    final service = HomeSlideshowService(
      client: MockClient((request) async {
        final endpoint = Uri.parse(
          ApiConfig.isProduction
              ? HomeSlideshowService.layoutUrl
              : HomeSlideshowService.baseUrl,
        );
        expect(request.method, 'GET');
        expect(request.url.authority, endpoint.authority);
        expect(request.url.path, endpoint.path);
        expect(request.url.queryParameters, {
          'headerOffers': '1',
          'regionId': 'manathera',
        });
        return http.Response(
          '{"settings":{"enabled":true},"campaigns":[]}',
          200,
        );
      }),
    );
    final feed = await service.headerFeed();
    expect(feed.settings.enabled, isTrue);
    expect(feed.offers, isEmpty);
  });

  test(
    'GPS browsing region shows targeted slides without a saved delivery address',
    () async {
      await select('manathera');
      final service = HomeSlideshowService(
        client: MockClient((request) async {
          final targeted =
              request.url.queryParameters['regionId'] == 'manathera';
          return http.Response(
            jsonEncode({
              'version': 1,
              'slides':
                  targeted
                      ? [
                        {
                          'id': 'regional-slide',
                          'title': 'Regional slide',
                          'imageUrl': 'https://example.com/slide.jpg',
                          'imageVersion': '1',
                          'endAt': '2099-01-01T00:00:00Z',
                          'action': {'type': 'merchant', 'id': 'restaurant'},
                        },
                      ]
                      : [],
            }),
            200,
          );
        }),
      );
      expect((await service.load()).slides.single.id, 'regional-slide');
      await BrowsingLocationService.instance.clear();
      expect((await service.load()).slides, isEmpty);
    },
  );

  test(
    'feed, campaign discovery, details and tracking follow changed browsing region',
    () async {
      final requests = <http.Request>[];
      final service = HomeSlideshowService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'version': 1, 'slides': [], 'campaigns': []}),
            200,
          );
        }),
      );
      await select('first');
      await service.load();
      expect(requests.last.url.queryParameters['regionId'], 'first');
      await select('second', source: 'region');
      await service.load();
      await service.campaigns();
      await service.details('slide');
      await service.track('slide', 'view');
      for (final request in requests.skip(1)) {
        expect(request.url.queryParameters['regionId'], 'second');
      }
      await BrowsingLocationService.instance.clear();
      await service.load();
      expect(
        requests.last.url.queryParameters.containsKey('regionId'),
        isFalse,
      );
    },
  );
}
