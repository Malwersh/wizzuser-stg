import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/models/address_model.dart';
import 'package:foodapp_user/models/browsing_location.dart';
import 'package:foodapp_user/services/address_service.dart';
import 'package:foodapp_user/services/browsing_location_service.dart';
import 'package:foodapp_user/services/address_book_api_319.dart';
import 'package:foodapp_user/services/address_save_attempt_319.dart';

Map<String, dynamic> row(
  String id, {
  String owner = 'owner',
  bool isDefault = false,
  double lat = 31.9,
}) => {
  'id': id,
  'user_id': owner,
  'name': 'المنزل',
  'full_address': 'حي الجمعية قرب المدرسة',
  'province': 'النجف',
  'district': 'المناذرة',
  'neighborhood': 'حي الجمعية',
  'landmark': 'قرب المدرسة',
  'latitude': lat,
  'longitude': 44.4,
  'region_id': 'r',
  'region_name_ar': 'المنطقة',
  'is_default': isDefault,
};
http.Response book(List<Map<String, dynamic>> rows, String? defaultId) =>
    http.Response(
      jsonEncode({
        'success': true,
        'data': {'addresses': rows, 'default_address_id': defaultId},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
AddressCreateRequest request() => AddressCreateRequest(
  name: 'المنزل',
  province: 'النجف',
  district: 'المناذرة',
  neighborhood: 'حي الجمعية',
  landmark: 'قرب المدرسة',
  latitude: 31.9,
  longitude: 44.4,
  saveToAddressBook: true,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'save attempt survives service restart; changes in payload or account cannot reuse another intent',
    () async {
      final body = request().toJson();
      final first = await AddressSaveAttempt319.key('owner', body);
      expect(
        await AddressSaveAttempt319.key('owner', {
          ...body,
          'idempotency_key': 'different',
        }),
        first,
      );
      expect(await AddressSaveAttempt319.key('other', body), isNot(first));
      expect(
        await AddressSaveAttempt319.key('owner', {
          ...body,
          'landmark': 'قرب الجامع',
        }),
        isNot(first),
      );
      await AddressSaveAttempt319.confirmed('owner', body, first);
      expect(await AddressSaveAttempt319.key('owner', body), isNot(first));
    },
  );
  test(
    'HTTP 200 deletion is success; timeout is friendly and explicitly uncertain',
    () async {
      final api = AddressBookApi319(
        client: MockClient((_) async => http.Response('{"success":true}', 200)),
      );
      expect(
        (await api.request(
          method: 'DELETE',
          owner: 'owner',
          token: 't',
          addressId: 'a',
        ))['success'],
        true,
      );
      final timeout = AddressBookApi319(
        timeout: const Duration(milliseconds: 2),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      final r = await timeout.request(
        method: 'POST',
        owner: 'owner',
        token: 't',
        body: {},
      );
      expect(r['uncertain'], true);
      expect(r['message'], isNot(contains('TimeoutException')));
    },
  );
  test(
    'set default uses server result and activates that destination without guessing first row',
    () async {
      var defaultId = 'a';
      final active = <String>[];
      final browsing = BrowsingLocationService(owner: () => 'owner');
      final api = AddressBookApi319(
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            defaultId = 'b';
            return http.Response('{"success":true}', 200);
          }
          return book([
            row('a'),
            row('b', isDefault: defaultId == 'b'),
          ], defaultId);
        }),
      );
      final s = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (a) async => active.add(a.id),
        api: api,
      );
      await s.fetchAddresses();
      expect(s.defaultAddress!.id, 'a');
      expect(await s.setDefaultAddress('b'), true);
      expect(s.defaultAddress!.id, 'b');
      expect(s.detailedAddresses.where((a) => a.isDefault).length, 1);
      expect(active, ['b']);
      s.dispose();
      browsing.dispose();
    },
  );
  test(
    'deleting active/default uses authoritative remaining saved address; empty response clears local default',
    () async {
      var deleted = false;
      final browsing = BrowsingLocationService(owner: () => 'owner');
      await browsing.select(
        const BrowsingLocation(
          regionId: 'r',
          regionName: 'المنطقة',
          source: 'saved',
          latitude: 31.9,
          longitude: 44.4,
          savedAddressId: 'a',
          addressText: 'حي الجمعية قرب المدرسة',
        ),
      );
      final active = <String>[];
      final api = AddressBookApi319(
        client: MockClient((r) async {
          if (r.method == 'DELETE') {
            deleted = true;
            return http.Response('{"success":true}', 200);
          }
          return deleted
              ? book([row('b', isDefault: true)], 'b')
              : book([row('a', isDefault: true), row('b')], 'a');
        }),
      );
      final s = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (a) async => active.add(a.id),
        api: api,
      );
      await s.fetchAddresses();
      expect(await s.deleteAddress('a'), true);
      expect(s.defaultAddress!.id, 'b');
      expect(active, ['b']);
      s.dispose();
      browsing.dispose();
    },
  );
  test('late address list cannot cross an account switch', () async {
    var owner = 'one';
    final pending = Completer<http.Response>();
    final browsing = BrowsingLocationService(owner: () => owner);
    final api = AddressBookApi319(client: MockClient((r) => pending.future));
    final s = EnhancedAddressService(
      owner: () => owner,
      loggedIn: () => true,
      freshToken: () async => 't',
      browsing: browsing,
      activate: (_) async {},
      api: api,
    );
    final fetch = s.fetchAddresses();
    await Future<void>.delayed(Duration.zero);
    owner = 'two';
    pending.complete(book([row('a', owner: 'one', isDefault: true)], 'a'));
    await fetch;
    expect(s.detailedAddresses, isEmpty);
    expect(s.defaultAddress, isNull);
    s.dispose();
    browsing.dispose();
  });
  test(
    'server empty book clears stale selected/default address and persists empty cache',
    () async {
      var empty = false;
      final browsing = BrowsingLocationService(owner: () => 'owner');
      final api = AddressBookApi319(
        client: MockClient(
          (r) async =>
              empty ? book([], null) : book([row('a', isDefault: true)], 'a'),
        ),
      );
      final s = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (_) async {},
        api: api,
      );
      await s.fetchAddresses();
      expect(s.defaultAddress!.id, 'a');
      empty = true;
      await s.fetchAddresses();
      expect(s.defaultAddress, isNull);
      expect(s.currentAddress, isNull);
      expect(s.detailedAddresses, isEmpty);
      s.dispose();
      browsing.dispose();
    },
  );
  test(
    'new session loads account cache but server corrected coordinates override it',
    () async {
      final browsing = BrowsingLocationService(owner: () => 'owner');
      final api = AddressBookApi319(
        client: MockClient((r) async => book([row('a', isDefault: true)], 'a')),
      );
      final first = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (_) async {},
        api: api,
      );
      await first.fetchAddresses();
      first.dispose();
      final pending = Completer<http.Response>();
      final next = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (_) async {},
        api: AddressBookApi319(client: MockClient((r) => pending.future)),
      );
      final fetch = next.fetchAddresses();
      await Future<void>.delayed(Duration.zero);
      expect(next.defaultAddress!.latitude, 31.9);
      pending.complete(book([row('a', isDefault: true, lat: 31.8)], 'a'));
      await fetch;
      expect(next.defaultAddress!.latitude, 31.8);
      next.dispose();
      browsing.dispose();
    },
  );
  test(
    'uncertain save reuses key on retry and never adds an unconfirmed local row',
    () async {
      final keys = <String>[];
      var attempts = 0;
      final browsing = BrowsingLocationService(owner: () => 'owner');
      final api = AddressBookApi319(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            keys.add(jsonDecode(r.body)['idempotency_key']);
            if (++attempts == 1) throw Exception('lost');
            return http.Response(
              jsonEncode({
                'success': true,
                'data': row('new', isDefault: true),
              }),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return book([row('new', isDefault: true)], 'new');
        }),
      );
      final s = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (_) async {},
        api: api,
      );
      expect(await s.createAddress(request()), isNull);
      expect(s.addressCount, 0);
      expect((await s.createAddress(request()))!.id, 'new');
      expect(keys.first, keys.last);
      expect(s.addressCount, 1);
      s.dispose();
      browsing.dispose();
    },
  );
  test(
    'editing a selected saved point refreshes its coordinates without changing persistent default',
    () async {
      final browsing = BrowsingLocationService(owner: () => 'owner');
      await browsing.select(
        const BrowsingLocation(
          regionId: 'r',
          regionName: 'المنطقة',
          source: 'saved',
          latitude: 31.9,
          longitude: 44.4,
          savedAddressId: 'b',
          addressText: 'حي الجمعية قرب المدرسة',
        ),
      );
      var latitude = 31.9;
      final activated = <double>[];
      var mutations = 0;
      final api = AddressBookApi319(
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            mutations++;
            expect(r.url.path.endsWith('/set-default'), false);
            latitude = 32;
            return http.Response(
              jsonEncode({'success': true, 'data': row('b', lat: latitude)}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return book([
            row('a', isDefault: true),
            row('b', lat: latitude),
          ], 'a');
        }),
      );
      final service = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (a) async {
          activated.add(a.latitude!);
        },
        api: api,
      );
      await service.fetchAddresses();
      expect(
        (await service.updateAddress(
          'b',
          AddressUpdateRequest(latitude: 32),
        ))!.latitude,
        32,
      );
      expect(service.defaultAddress!.id, 'a');
      expect(activated, [32]);
      expect(mutations, 1);
      service.dispose();
      browsing.dispose();
    },
  );
  test(
    'uncertain edit reloads authoritative data instead of retaining stale coordinates',
    () async {
      var changed = false;
      final browsing = BrowsingLocationService(owner: () => 'owner');
      final api = AddressBookApi319(
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            changed = true;
            return http.Response('{}', 503);
          }
          return book([
            row('a', isDefault: true, lat: changed ? 32 : 31.9),
          ], 'a');
        }),
      );
      final service = EnhancedAddressService(
        owner: () => 'owner',
        loggedIn: () => true,
        freshToken: () async => 't',
        browsing: browsing,
        activate: (_) async {},
        api: api,
      );
      await service.fetchAddresses();
      expect(
        await service.updateAddress('a', AddressUpdateRequest(latitude: 32)),
        isNull,
      );
      expect(service.defaultAddress!.latitude, 32);
      expect(service.error, isNotNull);
      service.dispose();
      browsing.dispose();
    },
  );
}
