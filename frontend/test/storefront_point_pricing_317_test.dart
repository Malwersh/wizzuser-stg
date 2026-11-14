import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/models/browsing_location.dart';
import 'package:foodapp_user/services/storefront_pricing.dart';

const first = BrowsingLocation(
  regionId: 'r',
  regionName: 'المنطقة',
  source: 'region',
  latitude: 31.9,
  longitude: 44.4,
);
Map<String, dynamic> preview(Map<String, dynamic> request) => {
  'success': true,
  'preview': {
    'kind': 'STOREFRONT_PREVIEW',
    'schemaVersion': 1,
    'branchId': request['branchId'],
    'regionId': request['regionId'],
    'destination': request['point'],
    'informationalOnly': true,
    'requiresFinalConfirmation': true,
    'expiresAt': '2026-11-01T00:00:00Z',
    'customerDeliveryFee': {
      'moneySchemaVersion': 1,
      'currency': 'IQD',
      'scale': 1000,
      'minorAmount': 5500000,
    },
    'roadDistanceMeters': 11967,
    'deliveryDurationSeconds': 1620,
    'preparationMinutes': 20,
    'arrivalMinutes': {'minimum': 47, 'maximum': 52},
    'minimumOrderAmountIqd': 10000,
  },
};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'guest point obtains fee and minimum before any saved address or written delivery details',
    () async {
      var calls = 0;
      final p = StorefrontPricing(
        account: () => null,
        addressId: () => null,
        addressRevision: () => null,
        regionId: () => first.regionId,
        destination: () => first,
        listenToAddress: false,
        now: () => DateTime.utc(2026, 10, 26),
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, endsWith('/storefront-point-preview'));
          expect(request.headers.containsKey('Authorization'), false);
          final body = jsonDecode(request.body);
          expect(body['action'], 'storefront_point_preview');
          expect(body.containsKey('addressId'), false);
          expect(body.containsKey('neighborhood'), false);
          return http.Response(jsonEncode(preview(body)), 200);
        }),
      );
      expect(p.key('b', []), isNotNull);
      final value = await p.load('b', []);
      expect(value!.fee, 5500);
      expect(value.minimumOrderAmountIqd, 10000);
      expect(p.browsingPointFeeIqd('b', []), 5500);
      await p.load('b', []);
      expect(calls, 1);
      p.dispose();
    },
  );
  test(
    'old point response cannot replace a new destination or another account',
    () async {
      BrowsingLocation selected = first;
      String? owner;
      final pending = Completer<http.Response>();
      late Map<String, dynamic> body;
      final p = StorefrontPricing(
        account: () => owner,
        addressId: () => null,
        addressRevision: () => null,
        regionId: () => selected.regionId,
        destination: () => selected,
        listenToAddress: false,
        now: () => DateTime.utc(2026, 10, 26),
        client: MockClient((request) {
          body = jsonDecode(request.body);
          return pending.future;
        }),
      );
      final task = p.load('b', []);
      await Future<void>.delayed(Duration.zero);
      selected = const BrowsingLocation(
        regionId: 'r',
        regionName: 'المنطقة',
        source: 'gps',
        latitude: 31.8,
        longitude: 44.3,
      );
      owner = 'other';
      pending.complete(http.Response(jsonEncode(preview(body)), 200));
      expect(await task, isNull);
      expect(p.peek('b', []), isNull);
      p.dispose();
    },
  );
  test(
    'foreign response coordinates or missing informational guards are rejected',
    () async {
      for (final mismatch in [true, false]) {
        final p = StorefrontPricing(
          account: () => null,
          addressId: () => null,
          addressRevision: () => null,
          regionId: () => first.regionId,
          destination: () => first,
          listenToAddress: false,
          now: () => DateTime.utc(2026, 10, 26),
          client: MockClient((request) async {
            final r = preview(jsonDecode(request.body));
            if (mismatch) {
              r['preview']['destination'] = {'latitude': 30, 'longitude': 40};
            } else {
              r['preview'].remove('informationalOnly');
            }
            return http.Response(jsonEncode(r), 200);
          }),
        );
        expect(await p.load('b', []), isNull);
        expect(p.peek('b', []), isNull);
        p.dispose();
      }
    },
  );
}
