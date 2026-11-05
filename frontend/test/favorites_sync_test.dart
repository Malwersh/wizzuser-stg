import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/models/favorites_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({
    'favorite_stores_sync-test-user': ['stale-store'],
  }));
  test('successful empty server snapshot clears stale local favorites', () async {
    final model = FavoritesModel(account: () => 'sync-test-user',
      read: () async => {'success': true, 'data': {'favorites': []}});
    await model.initialize();
    expect(model.favoriteStoreIds, isEmpty);
    model.dispose();
  });
  test('server removal persists across later refreshes', () async {
    var rows = <Map<String, dynamic>>[
      {'business_id': 'store', 'id': 'favorite'}
    ];
    final model = FavoritesModel(account: () => 'sync-test-user',
      read: () async => {'success': true, 'data': {'favorites': rows}},
      remove: (id) async {
        expect(id, 'favorite');
        rows = [];
        return {'success': true};
      });
    await model.initialize();
    await model.toggleStoreFavorite('store', 'Store');
    expect(model.isStoreFavorite('store'), false);
    await model.refreshFavoritesFromServer();
    expect(model.isStoreFavorite('store'), false);
    model.dispose();
  });
  test('failed delete restores favorite and reports the error', () async {
    final model = FavoritesModel(account: () => 'sync-test-user',
      read: () async => {'success': true, 'data': {'favorites': [
        {'business_id': 'store', 'id': 'favorite'}]}},
      check: (_) async => {'success': false, 'error': 'network'},
      remove: (_) async => {'success': false, 'error': 'network'});
    await model.initialize();
    await expectLater(model.toggleStoreFavorite('store', 'Store'), throwsStateError);
    expect(model.isStoreFavorite('store'), true);
    model.dispose();
  });
  test('failed status check never silently removes an offline favorite', () async {
    final model = FavoritesModel(account: () => 'sync-test-user',
      read: () async => {'success': false},
      check: (_) async => {'success': false, 'error': 'offline'});
    await model.initialize();
    await expectLater(model.toggleStoreFavorite('stale-store', 'Store'), throwsStateError);
    expect(model.isStoreFavorite('stale-store'), true);
    model.dispose();
  });
}
