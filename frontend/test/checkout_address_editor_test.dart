import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:foodapp_user/models/address_model.dart';
import 'package:foodapp_user/models/browsing_location.dart';
import 'package:foodapp_user/services/region_resolver_service.dart';
import 'package:foodapp_user/widgets/checkout_address_editor.dart';

const area = BrowsingLocation(
  regionId: 'r',
  regionName: 'مركز المناذرة',
  source: 'region',
);

class FakeResolver extends RegionResolverService {
  final String id;
  FakeResolver(this.id);
  @override
  Future<RegionResolveResult?> resolvePoint({
    required double lat,
    required double lng,
    bool throwOnFailure = false,
  }) async => RegionResolveResult(
    success: true,
    region: RegionInfo(id: id, name: 'Area', nameAr: 'المنطقة', level: 3),
    effective: EffectiveState(
      isActive: true,
      service: ServiceInfo(delivery: DeliveryServiceInfo(available: true)),
    ),
    resolvedAt: DateTime.now(),
  );
}

RegionResolverService resolver([String region = 'r']) => FakeResolver(region);
DetailedAddress saved(AddressCreateRequest r) => DetailedAddress.fromJson({
  'id': 'owned-checkout',
  'user_id': 'owner',
  'region_id': 'r',
  'name': r.name,
  'latitude': r.latitude,
  'longitude': r.longitude,
  'neighborhood': r.neighborhood,
  'landmark': r.landmark,
  'full_address': r.detailedAddress,
});
Future<void> typeDetails(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('delivery-neighborhood')),
    'حي المعلمين',
  );
  await tester.enterText(
    find.byKey(const ValueKey('delivery-landmark')),
    'مقابل المدرسة',
  );
}

Future<void> confirm(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('confirm-delivery-details')),
  );
  await tester.tap(find.byKey(const ValueKey('confirm-delivery-details')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pricing receives confirmed coordinates before either text field and typing text does not reprice or save', (tester) async {
    final points=<LatLng>[];var saves=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:CheckoutAddressEditor(selection:area,currentPosition:()async=>const LatLng(31.9,44.4),resolver:resolver(),loggedIn:()=>true,onPointConfirmed:points.add,persist:(r)async{saves++;return saved(r);},onConfirmed:(_){})))));
    await tester.pumpAndSettle();expect(points,[const LatLng(31.9,44.4)]);expect(saves,0);
    await typeDetails(tester);await tester.pumpAndSettle();expect(points.length,1);expect(saves,0);
  });

  testWidgets(
    'area starts with current GPS but requires written details and defaults to checkout-only storage',
    (tester) async {
      AddressCreateRequest? request;
      DetailedAddress? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CheckoutAddressEditor(
                selection: area,
                currentPosition: () async => const LatLng(31.9, 44.4),
                resolver: resolver(),
                loggedIn: () => true,
                persist: (r) async {
                  request = r;
                  return saved(r);
                },
                onConfirmed: (a) => selected = a,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(request, isNull);
      expect(find.text('اكتب اسم الحي أو المحلة'), findsOneWidget);
      await typeDetails(tester);
      await confirm(tester);
      expect(request!.saveToAddressBook, false);
      expect(request!.neighborhood, 'حي المعلمين');
      expect(request!.landmark, 'مقابل المدرسة');
      expect(request!.latitude, 31.9);
      expect(selected!.id, 'owned-checkout');
    },
  );
  testWidgets(
    'real search point is preserved without replacing it with current GPS and save is explicit',
    (tester) async {
      var gpsCalls = 0;
      AddressCreateRequest? request;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CheckoutAddressEditor(
                selection: const BrowsingLocation(
                  regionId: 'r',
                  regionName: 'مركز المناذرة',
                  source: 'search',
                  latitude: 31.5,
                  longitude: 44.5,
                  addressText: 'شارع اختاره الزبون',
                ),
                currentPosition: () async {
                  gpsCalls++;
                  return const LatLng(30, 43);
                },
                resolver: resolver(),
                loggedIn: () => true,
                persist: (r) async {
                  request = r;
                  return saved(r);
                },
                onConfirmed: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gpsCalls, 0);
      expect(find.text('شارع اختاره الزبون'), findsOneWidget);
      await typeDetails(tester);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await confirm(tester);
      expect(request!.saveToAddressBook, true);
      expect(request!.latitude, 31.5);
    },
  );
  testWidgets('GPS in another area cannot authorize checkout', (tester) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CheckoutAddressEditor(
              selection: area,
              currentPosition: () async => const LatLng(30, 43),
              resolver: resolver('other'),
              loggedIn: () => true,
              persist: (r) async {
                saves++;
                return saved(r);
              },
              onConfirmed: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('موقعك ليس داخل'), findsOneWidget);
    final b = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-delivery-details')),
    );
    expect(b.onPressed, isNull);
    expect(saves, 0);
  });
  testWidgets('retrying address confirmation reuses the same key', (
    tester,
  ) async {
    final keys = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CheckoutAddressEditor(
              selection: area,
              currentPosition: () async => const LatLng(31.9, 44.4),
              resolver: resolver(),
              loggedIn: () => true,
              persist: (r) async {
                keys.add(r.idempotencyKey);
                return keys.length == 1 ? null : saved(r);
              },
              onConfirmed: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await typeDetails(tester);
    await confirm(tester);
    await confirm(tester);
    expect(keys.length, 2);
    expect(keys.first, keys.last);
  });
}
