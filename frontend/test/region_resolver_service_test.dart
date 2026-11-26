import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/region_resolver_service.dart';
void main() {
  test('shared boundary offers named choices and submits a selected region', () async {
    final service = RegionResolverService(client: MockClient((request) async {
      if (request.url.queryParameters['preferred_region_id'] == 'zone-b') {
        return http.Response('{"success":true,"data":{"region_id":"zone-b","effective":{"isActive":true,"service":{"delivery":true}}}}', 200);
      }
      return http.Response(
        '{"error":"BOUNDARY_REGION_SELECTION_REQUIRED","details":{"regions":[{"region_id":"zone-a","region_name_ar":"المنطقة الأولى","district":"القضاء الأول"},{"region_id":"zone-b","region_name_ar":"المنطقة الثانية","governorate":"النجف"}]}}',
        409,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));
    await expectLater(
      service.resolvePoint(lat: 31, lng: 44, throwOnFailure: true),
      throwsA(isA<BoundaryRegionSelectionRequired>().having(
        (e) => e.choices.last.governorate, 'governorate', 'النجف',
      )),
    );
    final selected = await service.resolvePoint(lat: 31, lng: 44,
      preferredRegionId: 'zone-b', throwOnFailure: true);
    expect(selected?.region.id, 'zone-b');
  });
  test('server failure is distinct from unavailable coverage', () async {
    final service = RegionResolverService(client: MockClient((_) async => http.Response('{"message":"Internal server error"}', 502)));
    await expectLater(service.resolvePoint(lat: 31.8858445, lng: 44.4803809, throwOnFailure: true), throwsA(isA<RegionResolutionException>()));
  });
  test('only confirmed missing region returns no coverage', () async {
    final service = RegionResolverService(client: MockClient((_) async => http.Response('{"error":"REGION_NOT_FOUND"}', 404)));
    expect(await service.resolvePoint(lat: 31, lng: 44, throwOnFailure: true), isNull);
    final broken = RegionResolverService(client: MockClient((_) async => http.Response('{"error":"REGION_METADATA_NOT_FOUND"}', 404)));
    await expectLater(broken.resolvePoint(lat: 31, lng: 44, throwOnFailure: true), throwsA(isA<RegionResolutionException>()));
  });
  test('resolved region remains serviceable', () async {
    final service = RegionResolverService(client: MockClient((_) async => http.Response('{"success":true,"data":{"region_id":"region-1","effective":{"isActive":true,"service":{"delivery":true}}}}', 200)));
    final result = await service.resolvePoint(lat: 31, lng: 44, throwOnFailure: true);
    expect(result!.region.id, 'region-1');
    expect(result.effective.hasDelivery, isTrue);
  });
}
