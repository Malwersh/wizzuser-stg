import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/models/home_slide.dart';
import 'package:foodapp_user/services/home_slideshow_service.dart';

void main() {
  test('platform offers preserve eligible merchants and code', () {
    final slide=HomeSlide.fromJson({'id':'x','title':'Offer','imageUrl':'https://example.com/x',
      'endAt':'2100-01-01T00:00:00Z','action':{'type':'campaign','id':'p','code':'SAVE','allMerchants':false,
      'merchants':[{'id':'m','name':'Restaurant'}]}});
    expect(slide.merchants.single['id'],'m');expect(slide.code,'SAVE');expect(slide.allMerchants,isFalse);
  });
  test('published feed preserves image version and category destination', () async {
    await http.runWithClient(() async {
      final feed = await HomeSlideshowService().load(regionId:'najaf');
      expect(feed.configured, isTrue);
      expect(feed.slides.single.merchantId, 'merchant');
      expect(feed.slides.single.targetId, 'drinks');
      expect(feed.slides.single.imageVersion, 'updated');
    }, () => MockClient((request) async {
      expect(request.url.queryParameters['regionId'], 'najaf');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response(jsonEncode({'version':1,'slides':[{
        'id':'slide','title':'Drinks','imageUrl':'https://images.example/slide.jpg',
        'imageVersion':'updated','endAt':'2100-01-01T00:00:00Z',
        'action':{'type':'category','id':'drinks','merchantId':'merchant'},
      }]}),200);
    }));
  });
  test('paused or ineligible empty feed remains configured and hides defaults', () async {
    await http.runWithClient(() async {
      final feed=await HomeSlideshowService().load();
      expect(feed.configured,isTrue);expect(feed.slides,isEmpty);
    },()=>MockClient((_)async=>http.Response('{"version":2,"slides":[]}',200)));
  });
  test('server errors are not interpreted as an unconfigured slideshow', () async {
    await http.runWithClient(() async {
      await expectLater(HomeSlideshowService().load(),throwsStateError);
    },()=>MockClient((_)async=>http.Response('{}',503)));
  });
  test('arbitrary tap actions and unsafe image schemes are rejected', () {
    expect(()=>HomeSlide.fromJson({'id':'x','title':'x','imageUrl':'javascript:alert(1)',
      'endAt':'2100-01-01T00:00:00Z','action':{'type':'merchant','id':'m'}}),throwsFormatException);
    expect(()=>HomeSlide.fromJson({'id':'x','title':'x','imageUrl':'https://example.com/x',
      'endAt':'2100-01-01T00:00:00Z','action':{'type':'external','id':'m'}}),throwsFormatException);
  });
}
