import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/active_region_catalog.dart';
import 'package:foodapp_user/widgets/active_region_tree.dart';

void main() {
  testWidgets('Iraq hierarchy expands progressively and selects only a leaf', (
    tester,
  ) async {
    ActiveRegion? selected;
    final catalog = ActiveRegionCatalog(
      client: MockClient(
        (_) async => http.Response(
          '{"success":true,"data":{"schemaVersion":313,"items":[{"id":"c","labelAr":"العراق","level":0,"parentId":null},{"id":"g","labelAr":"النجف","level":1,"parentId":"c"},{"id":"d","labelAr":"المناذرة","level":2,"parentId":"g"},{"id":"n","labelAr":"مركز القضاء","level":3,"parentId":"d","bounds":{"north":32,"south":31,"east":45,"west":44}}]}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: ActiveRegionTree(
                catalog: catalog,
                onSelected: (r) => selected = r,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('العراق'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.text('النجف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المناذرة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مركز القضاء'));
    expect(selected?.id, 'n');
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed catalog shows retry instead of stale or fake areas', (
    tester,
  ) async {
    final catalog = ActiveRegionCatalog(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveRegionTree(catalog: catalog, onSelected: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.text('العراق'), findsNothing);
  });
}
