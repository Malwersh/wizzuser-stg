import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/models/home_navigation.dart';
import 'package:foodapp_user/models/home_filters.dart';
import 'package:foodapp_user/widgets/discovery/discovery_results_transition.dart';

void main() {
  HomeNavigationItem selector(String kind, String value) => HomeNavigationItem.fromJson({'id': value, 'label': value, 'kind': kind, 'value': value});
  BusinessModel merchant(String id, String type, {String? canonical, List<String> cuisines = const []}) => BusinessModel(id: id, businessName: id, address: '', businessPhotoUrl: '', businessType: type, businessTypeId: canonical, rating: 4.5, metadata: {'reviewCount': 2, 'publishedCuisineIds': cuisines});
  test('canonical activity wins over conflicting legacy type', () {
    final cafe = merchant('cafe', 'restaurant', canonical: 'CAFE');
    expect(selector('activity', 'restaurant').matches(cafe, {}), false);
    expect(selector('activity', 'CAFE').matches(cafe, {}), true);
    expect(selector('activity', 'restaurant').matches(merchant('r', 'restaurant'), {}), true);
  });
  test('legacy and canonical parent IDs show the same topics; empty means all activities', () {
    final nav = HomeNavigation.fromJson({'enabled': true, 'items': [
      {'id': 'pizza', 'label': 'بيتزا', 'kind': 'cuisine', 'value': 'pizza', 'parentActivities': ['RESTAURANT']},
      {'id': 'all', 'label': 'عام', 'kind': 'cuisine', 'value': 'all', 'parentActivities': []},
    ]});
    expect(nav.topicsFor('restaurant').map((x) => x.id), ['pizza', 'all']);
    expect(nav.topicsFor('RESTAURANT').map((x) => x.id), ['pizza', 'all']);
    expect(nav.topicsFor('store').map((x) => x.id), ['all']);
    expect(nav.topicsFor(null).length, 2);
  });
  test('activity, cuisine and first-strip filter intersect rather than replace each other', () {
    final rows = [merchant('pizza', 'restaurant', cuisines: ['pizza']), merchant('shawarma', 'restaurant', cuisines: ['shawarma']), merchant('shop', 'store', cuisines: ['pizza'])];
    final settings = HomeFilters.defaults();
    final rating = settings.items.firstWhere((x) => x.kind == 'rating');
    final result = rows.where((b) => selector('activity', 'restaurant').matches(b, {}) && selector('cuisine', 'pizza').matches(b, {}) && matchesHomeFilter(rating, b, facts: {}, settings: settings, now: DateTime.now()));
    expect(result.map((b) => b.id), ['pizza']);
    expect(rows.where((b) => selector('activity', 'restaurant').matches(b, {})).length, 2);
  });
  for (final reduced in [false, true]) {
    testWidgets('changing results replaces old content, with reduced-motion support $reduced', (t) async {
      Widget page(String selection) => MaterialApp(home: MediaQuery(data: MediaQueryData(disableAnimations: reduced), child: DiscoveryResultsTransition(selection: selection, child: Text(selection))));
      await t.pumpWidget(page('restaurant'));
      await t.pumpAndSettle();
      await t.pumpWidget(page('store'));
      expect(find.text('restaurant'), findsNothing);
      expect(find.text('store'), findsOneWidget);
      await t.pumpAndSettle();
      expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      expect(t.takeException(), isNull);
    });
  }
}
