import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/region_resolver_service.dart';
void main() {
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
    final service = RegionResolverService(client: MockClient((_) async => http.Response('{"success":true,"data":{"region_id":"region-1"}}', 200)));
    final result = await service.resolvePoint(lat: 31, lng: 44, throwOnFailure: true);
    expect(result!.region.id, 'region-1');
    expect(result.effective.hasDelivery, isTrue);
  });
}
