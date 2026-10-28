import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/services/google_places_service.dart';
import 'package:foodapp_user/services/region_boundary_service.dart';
import 'package:foodapp_user/services/region_resolver_service.dart';
import 'package:foodapp_user/widgets/location_picker_screen.dart';

class TestPlaces extends GooglePlacesService {
  TestPlaces() : super(apiKey: 'unit-test');
  @override
  Future<String> getAddressFromCoordinates({
    required double latitude,
    required double longitude,
    String language = 'ar',
  }) async => 'عنوان التوصيل';
}

http.Response covered([String id = 'selected']) => http.Response(
  jsonEncode({
    'success': true,
    'data': {
      'region_id': id,
      'region_name_ar': 'المنطقة',
      'effective': {
        'isActive': true,
        'service': {'delivery': true},
      },
    },
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> boundary() => {
  'success': true,
  'data': {
    'regionId': 'selected',
    'nameAr': 'مركز المناذرة',
    'geometry': {
      'type': 'Polygon',
      'coordinates': [
        [
          [44, 31],
          [45, 31],
          [45, 32],
          [44, 32],
          [44, 31],
        ],
        [
          [44.7, 31.7],
          [44.8, 31.7],
          [44.8, 31.8],
          [44.7, 31.8],
          [44.7, 31.7],
        ],
      ],
    },
  },
};

class SlowPlaces extends TestPlaces {
  @override
  Future<String> getAddressFromCoordinates({required double latitude,required double longitude,String language='ar'}) => Completer<String>().future;
}

class Fixture {
  late GoogleMap map;
  LatLng target = const LatLng(31.5, 44.5);
  final Future<http.Response> Function(http.Request) resolver;
  final bool boundaryFails;
  final TestPlaces places;
  Fixture({
    Future<http.Response> Function(http.Request)? resolver,
    this.boundaryFails = false,
    TestPlaces? places,
  }) : places = places ?? TestPlaces(), resolver = resolver ?? ((_) async => covered());
  LocationPickerScreen screen() => LocationPickerScreen(
    initialPosition: const LatLng(31.5, 44.5),
    initialAddress: 'مركز المناذرة',
    requiredRegionId: 'selected',
    requirePinSelection: true,
    regionResolver: RegionResolverService(client: MockClient(resolver)),
    placesService: places,
    boundaryService: RegionBoundaryService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(boundary()),
          boundaryFails ? 503 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    ),
    mapBuilder: (value) {
      map = value;
      return GestureDetector(
        key: const ValueKey('test-map'),
        behavior: HitTestBehavior.opaque,
        onTap: () => value.onTap!(target),
        onPanStart: (_) => value.onCameraMoveStarted!(),
        onPanUpdate:
            (_) =>
                value.onCameraMove!(CameraPosition(target: target, zoom: 17)),
        onPanEnd: (_) => value.onCameraIdle!(),
        child: const ColoredBox(color: Colors.lightBlueAccent),
      );
    },
  );
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: screen()));
    await tester.pumpAndSettle();
  }

  FilledButton button(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('confirm-delivery-point')),
  );
  Future<void> tap(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('test-map')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('region view without a confirmed point starts wide and cannot confirm its geometric center',(tester)async{
    late GoogleMap map;
    await tester.pumpWidget(MaterialApp(home:LocationPickerScreen(initialViewport:LatLngBounds(southwest:const LatLng(31.8,44.3),northeast:const LatLng(31.96,44.56)),requiredRegionId:'selected',requirePinSelection:true,placesService:TestPlaces(),mapBuilder:(value){map=value;return const ColoredBox(color:Colors.white);} )));
    await tester.pumpAndSettle();
    expect(map.initialCameraPosition.zoom,12);expect(map.polygons,isEmpty);
    final button=tester.widget<FilledButton>(find.byKey(const ValueKey('confirm-delivery-point')));expect(button.onPressed,isNull);
    expect(find.textContaining('تعذر تحديد موقع جهازك'),findsNothing);
  });
  testWidgets('a real initial point keeps street zoom even when a region viewport is available',(tester)async{
    late GoogleMap map;
    await tester.pumpWidget(MaterialApp(home:LocationPickerScreen(initialPosition:const LatLng(31.92,44.46),initialViewport:LatLngBounds(southwest:const LatLng(31.8,44.3),northeast:const LatLng(31.96,44.56)),requiredRegionId:'selected',requirePinSelection:true,placesService:TestPlaces(),mapBuilder:(value){map=value;return const ColoredBox(color:Colors.white);} )));
    await tester.pumpAndSettle();expect(map.initialCameraPosition.target,const LatLng(31.92,44.46));expect(map.initialCameraPosition.zoom,17);expect(map.polygons,isEmpty);
  });

  testWidgets('slow reverse geocoding cannot delay confirmation for five seconds', (tester) async {
    Map<String,dynamic>? result;
    final f=Fixture(places:SlowPlaces());
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{result=await Navigator.push<Map<String,dynamic>>(context,MaterialPageRoute(builder:(_)=>f.screen()));},child:const Text('اختيار'))))));
    await tester.tap(find.text('اختيار'));await tester.pumpAndSettle();await f.tap(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-delivery-point')));await tester.pump();await tester.pump(const Duration(milliseconds:900));await tester.pumpAndSettle();
    expect(result?['position'],f.target);expect(result?['address'],contains('31.50000'));
    await tester.pump(const Duration(seconds:2));f.places.dispose();
  });
  test('MultiPolygon outlines retain separate parts, holes and complete bounds', () {
    final data = Map<String,dynamic>.from(boundary()['data']);
    final original = (data['geometry'] as Map)['coordinates'];
    data['geometry'] = {'type':'MultiPolygon','coordinates':[original, [[[45,32],[46,32],[46,33],[45,33],[45,32]]]]};
    final parsed = RegionBoundary.fromJson(data);
    expect(parsed.polygons.length,2);expect(parsed.polygons.first.length,2);
    expect(parsed.bounds.southwest,const LatLng(31,44));expect(parsed.bounds.northeast,const LatLng(33,46));
  });
  testWidgets('map controls and confirmation fit a small screen', (tester) async {
    tester.view.physicalSize=const Size(320,568);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final f=Fixture();await f.mount(tester);await f.tap(tester);
    expect(tester.takeException(),isNull);expect(f.button(tester).onPressed,isNotNull);f.places.dispose();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'boundary and holes render; real map gestures remain enabled; preview is not an address',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(f.map.polygons, isEmpty);
      expect(f.map.scrollGesturesEnabled, true);
      expect(f.map.zoomGesturesEnabled, true);
      expect(f.map.liteModeEnabled, false);
      expect(f.map.gestureRecognizers, isNotEmpty);
      expect(find.byTooltip('تكبير الخريطة'), findsOneWidget);
      expect(find.byTooltip('إظهار حدود المنطقة'), findsNothing);
      expect(f.button(tester).onPressed, isNull);
      expect(find.textContaining('حرّك الخريطة لتحديد'), findsOneWidget);
      f.places.dispose();
    },
  );
  testWidgets('tap selects a point and enables confirmation', (tester) async {
    final f = Fixture();
    await f.mount(tester);
    final gestures = f.map.gestureRecognizers;
    await f.tap(tester);
    expect(identical(gestures, f.map.gestureRecognizers), isTrue);
    expect(f.button(tester).onPressed, isNotNull);
    expect(find.text('نقطة التوصيل متاحة'), findsOneWidget);
    f.places.dispose();
  });
  testWidgets(
    'panning under the center pin resolves the camera target and enables confirmation',
    (tester) async {
      double? lookedUp;
      final f = Fixture(
        resolver: (r) async {
          lookedUp = double.parse(r.url.queryParameters['latitude']!);
          return covered();
        },
      );
      await f.mount(tester);
      f.target = const LatLng(31.4, 44.4);
      await tester.drag(
        find.byKey(const ValueKey('test-map')),
        const Offset(80, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(lookedUp, 31.4);
      expect(f.button(tester).onPressed, isNotNull);
      f.places.dispose();
    },
  );
  testWidgets(
    'point in another region disables confirmation and explains the correction',
    (tester) async {
      final f = Fixture(resolver: (_) async => covered('other'));
      await f.mount(tester);
      await f.tap(tester);
      expect(f.button(tester).onPressed, isNull);
      expect(find.textContaining('النقطة خارج مركز المناذرة'), findsOneWidget);
      f.places.dispose();
    },
  );
  testWidgets('hidden polygon endpoint is unnecessary; live resolver still authorizes point', (
    tester,
  ) async {
    final f = Fixture(boundaryFails: true);
    await f.mount(tester);
    expect(find.text('إعادة تحميل الحدود'), findsNothing);
    expect(f.map.polygons, isEmpty);
    await f.tap(tester);
    expect(f.button(tester).onPressed, isNotNull);
    f.places.dispose();
  });
  testWidgets('late lookup for an earlier point cannot enable confirmation', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    var requests = 0;
    final f = Fixture(
      resolver: (_) async => ++requests == 1 ? first.future : covered('other'),
    );
    await f.mount(tester);
    f.map.onTap!(const LatLng(31.2, 44.2));
    await tester.pump(const Duration(milliseconds: 300));
    f.map.onTap!(const LatLng(31.3, 44.3));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    first.complete(covered());
    await tester.pumpAndSettle();
    expect(f.button(tester).onPressed, isNull);
    expect(find.textContaining('النقطة خارج'), findsOneWidget);
    f.places.dispose();
  });
  testWidgets('confirm rechecks and returns the actual selected coordinates', (
    tester,
  ) async {
    Map<String, dynamic>? result;
    var requests = 0;
    final f = Fixture(
      resolver: (_) async {
        requests++;
        return covered();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(builder: (_) => f.screen()),
                    );
                  },
                  child: const Text('اختيار'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('اختيار'));
    await tester.pumpAndSettle();
    await f.tap(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-delivery-point')));
    await tester.pumpAndSettle();
    expect(result?['position'], f.target);
    expect(result?['address'], 'عنوان التوصيل');
    expect(requests, 2);
    f.places.dispose();
  });
}
