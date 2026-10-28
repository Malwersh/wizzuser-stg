import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:foodapp_user/services/region_resolver_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/models/browsing_location.dart';
import 'package:foodapp_user/services/browsing_location_service.dart';
import 'package:foodapp_user/services/active_region_catalog.dart';
import 'package:foodapp_user/screens/address_gate_screen.dart';
import 'package:foodapp_user/widgets/location_picker_screen.dart';

const items = [
  {'id': 'c', 'labelAr': 'العراق', 'level': 0, 'parentId': null},
  {'id': 'g', 'labelAr': 'النجف', 'level': 1, 'parentId': 'c'},
  {'id': 'd', 'labelAr': 'المناذرة', 'level': 2, 'parentId': 'g'},
  {'id': 'r', 'labelAr': 'مركز المناذرة', 'level': 3, 'parentId': 'd'},
];
ActiveRegionCatalog catalog([bool open = true]) => ActiveRegionCatalog(
  client: MockClient(
    (_) async => http.Response(
      jsonEncode({
        'success': true,
        'data': {'schemaVersion': 313, 'items': open ? items : []},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  ),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'region selection persists confirmed point without saved address identity',
    () async {
      final s = BrowsingLocationService(
        owner: () => 'owner',
        catalog: catalog(),
      );
      await s.select(
        const BrowsingLocation(
          regionId: 'r',
          regionName: 'مركز المناذرة',
          source: 'region',
          latitude: 31.5,
          longitude: 44.5,
        ),
      );
      expect(s.selection!.hasPoint, true);
      expect(s.selection!.savedAddressId, isNull);
      final restored = BrowsingLocationService(
        owner: () => 'owner',
        catalog: catalog(),
      );
      await restored.restore();
      expect(restored.selection!.regionId, 'r');
      expect(restored.selection!.latitude, 31.5);
      s.dispose();
      restored.dispose();
    },
  );
  test(
    'saved browsing choices are account scoped and closed regions are not restored',
    () async {
      var owner = 'one';
      final s = BrowsingLocationService(owner: () => owner, catalog: catalog());
      await s.select(
        const BrowsingLocation(
          regionId: 'r',
          regionName: 'المنطقة',
          source: 'region',
          latitude: 31.5,
          longitude: 44.5,
        ),
      );
      owner = 'two';
      expect(s.selection, isNull);
      await s.restore();
      expect(s.selection, isNull);
      final closed = BrowsingLocationService(
        owner: () => 'one',
        catalog: catalog(false),
      );
      await closed.restore();
      expect(closed.selection, isNull);
      s.dispose();
      closed.dispose();
    },
  );
  test(
    'area selection requires a confirmed point and distinguishes real GPS/search points',
    () {
      expect(
        () => BrowsingLocation.fromJson({
          'regionId': 'r',
          'regionName': 'منطقة',
          'source': 'region',
        }),
        throwsFormatException,
      );
      for (final source in ['search', 'gps']) {
        final p = BrowsingLocation.fromJson({
          'regionId': 'r',
          'regionName': 'منطقة',
          'source': source,
          'latitude': 31.5,
          'longitude': 44.5,
          'addressText': 'عنوان مكتوب',
        });
        expect(p.hasPoint, true);
        expect(p.addressText, 'عنوان مكتوب');
      }
    },
  );
  testWidgets(
    'choosing a tree leaf confirms a point before returning without saving an address',
    (tester) async {
      final s = BrowsingLocationService(
        owner: () => 'guest',
        catalog: catalog(),
      );
      bool? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      chosen = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => AddressGateScreen(
                                isGuest: true,
                                showBackButton: true,
                                regionCatalog: catalog(),
                                browsingService: s,
                                pickPoint: (context, point, name, id) async {
                                  expect(id, 'r');
                                  expect(s.selection, isNull);
                                  return {
                                    'position': const LatLng(31.5, 44.5),
                                    'region': RegionResolveResult(
                                      success: true,
                                      region: RegionInfo(
                                        id: 'r',
                                        name: 'Area',
                                        nameAr: 'مركز المناذرة',
                                        level: 3,
                                      ),
                                      effective: EffectiveState(
                                        isActive: true,
                                        service: ServiceInfo(
                                          delivery: DeliveryServiceInfo(
                                            available: true,
                                          ),
                                        ),
                                      ),
                                      resolvedAt: DateTime.now(),
                                    ),
                                  };
                                },
                              ),
                        ),
                      );
                    },
                    child: const Text('ابدأ'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('ابدأ'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('النجف'));
      await tester.tap(find.text('النجف'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('المناذرة'));
      await tester.tap(find.text('المناذرة'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('مركز المناذرة'));
      await tester.tap(find.text('مركز المناذرة'));
      await tester.pumpAndSettle();
      expect(chosen, true);
      expect(s.selection!.source, 'region');
      expect(s.selection!.latitude, 31.5);
      expect(find.byType(LocationPickerScreen), findsNothing);
      s.dispose();
    },
  );
}
