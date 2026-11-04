import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/models/favorites_model.dart';

Map<String, dynamic> rows(List<String> ids) => {
  'success': true,
  'data': {
    'favorites':
        ids.map((id) => {'business_id': id, 'id': 'favorite-$id'}).toList(),
  },
};
Map<String, dynamic> status(bool value) => {
  'success': true,
  'data': {'is_favorite': value, 'favoriteId': value ? 'favorite-a' : null},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'successful empty server response removes stale local favorites',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorite_stores_u': ['a'],
      });
      final model = FavoritesModel(
        account: () => 'u',
        read: () async => rows([]),
      );
      await model.initialize();
      expect(model.favoriteStoreIds, isEmpty);
      model.dispose();
    },
  );
  test(
    'failure after committed add is reconciled without undoing heart',
    () async {
      var adds = 0;
      final model = FavoritesModel(
        account: () => 'u',
        read: () async => rows([]),
        add: (_, __, ___, ____) async {
          adds++;
          return {'success': false};
        },
        check: (_) async => status(true),
      );
      await model.initialize();
      await model.toggleStoreFavorite('a', 'A');
      expect(model.isStoreFavorite('a'), isTrue);
      expect(adds, 1);
      model.dispose();
    },
  );
  test('double tap coalesces and late read cannot erase a newer add', () async {
    var reads = 0, adds = 0;
    final lateRead = Completer<Map<String, dynamic>>();
    final add = Completer<Map<String, dynamic>>();
    final model = FavoritesModel(
      account: () => 'u',
      read: () async => ++reads == 1 ? rows([]) : await lateRead.future,
      add: (_, __, ___, ____) {
        adds++;
        return add.future;
      },
    );
    await model.initialize();
    final refresh = model.loadFavoritesFromServer();
    await Future<void>.delayed(Duration.zero);
    final one = model.toggleStoreFavorite('a', 'A');
    final two = model.toggleStoreFavorite('a', 'A');
    await Future<void>.delayed(Duration.zero);
    expect(model.isStoreFavorite('a'), isTrue);
    add.complete({
      'success': true,
      'data': {'id': 'favorite-a'},
    });
    await Future.wait([one, two]);
    lateRead.complete(rows([]));
    await refresh;
    expect(model.isStoreFavorite('a'), isTrue);
    expect(adds, 1);
    model.dispose();
  });
  test(
    'failed remove verification retains saved heart and raises error',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorite_stores_u': ['a'],
      });
      final model = FavoritesModel(
        account: () => 'u',
        read: () async => {'success': false},
        check: (_) async => {'success': false},
      );
      await model.initialize();
      await expectLater(model.toggleStoreFavorite('a', 'A'), throwsStateError);
      expect(model.isStoreFavorite('a'), isTrue);
      model.dispose();
    },
  );
  test('old account response cannot change new account or its cache', () async {
    var account = 'one';
    final write = Completer<Map<String, dynamic>>();
    final model = FavoritesModel(
      account: () => account,
      read: () async => rows([]),
      add: (_, __, ___, ____) => write.future,
    );
    await model.initialize();
    final pending = model.toggleStoreFavorite('a', 'A');
    await Future<void>.delayed(Duration.zero);
    account = 'two';
    await model.resetForNewUser();
    write.complete({
      'success': true,
      'data': {'id': 'favorite-a'},
    });
    await pending;
    expect(model.favoriteStoreIds, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorite_stores_two'), isEmpty);
    model.dispose();
  });
  test('confirmed remove stays removed after server refresh', () async {
    var saved = true;
    final model = FavoritesModel(
      account: () => 'u',
      read: () async => rows(saved ? ['a'] : []),
      remove: (_) async {
        saved = false;
        return {'success': true};
      },
    );
    await model.initialize();
    await model.toggleStoreFavorite('a', 'A');
    await model.loadFavoritesFromServer();
    expect(model.isStoreFavorite('a'), isFalse);
    model.dispose();
  });
}
