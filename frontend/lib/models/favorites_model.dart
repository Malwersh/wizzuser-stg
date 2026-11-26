import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/favorites_service.dart';
import '../services/session_service.dart';

typedef FavoriteResult = Future<Map<String, dynamic>>;

/// One account-scoped source for hearts on every screen. Server reads are
/// authoritative; stale reads may never overwrite a newer user action.
class FavoritesModel extends ChangeNotifier {
  final String Function() _account;
  final FavoriteResult Function() _read;
  final FavoriteResult Function(String) _check;
  final FavoriteResult Function(String, String, String, String) _add;
  final FavoriteResult Function(String) _remove;
  String? _owner;
  int _generation = 0;
  int _revision = 0;
  List<String> _stores = [];
  List<String> _dishes = [];
  Map<String, String> _lookup = {};
  final Map<String, Future<void>> _pending = {};
  Future<void>? _initializing;
  bool _initialized = false;
  bool _loading = false;
  bool _disposed = false;

  FavoritesModel({
    String Function()? account,
    FavoriteResult Function()? read,
    FavoriteResult Function(String)? check,
    FavoriteResult Function(String, String, String, String)? add,
    FavoriteResult Function(String)? remove,
  }) : _account =
           account ??
           (() =>
               SessionService.instance.isLoggedIn &&
                       !SessionService.instance.isGuest
                   ? SessionService.instance.currentUserId ?? 'anonymous'
                   : 'guest'),
       _read = read ?? FavoritesService.getUserFavorites,
       _check =
           check ??
           ((id) => FavoritesService.checkFavoriteStatus(businessId: id)),
       _add =
           add ??
           ((id, name, image, category) => FavoritesService.addToFavorites(
             businessId: id,
             businessName: name,
             businessImage: image,
             businessCategory: category,
           )),
       _remove =
           remove ??
           ((id) => FavoritesService.removeFromFavorites(favoriteId: id)) {
    initialize();
  }

  List<String> get favoriteStoreIds => List.unmodifiable(_stores);
  List<String> get favoriteDishIds => List.unmodifiable(_dishes);
  bool get isInitialized => _initialized;
  bool get isLoading => _loading;
  bool isStoreFavorite(String id) => _stores.contains(id);
  bool isDishFavorite(String id) => _dishes.contains(id);
  bool isStoreUpdating(String id) => _pending.containsKey(id);
  bool get _remote => _owner != 'guest' && _owner != 'anonymous';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && _owner == _account();

  void _ensureAccount() {
    final account = _account();
    if (_owner == account) return;
    _owner = account;
    _generation++;
    _revision++;
    _stores = [];
    _dishes = [];
    _lookup = {};
    _pending.clear();
    _initializing = null;
    _initialized = false;
  }

  Future<void> initialize() {
    _ensureAccount();
    if (_initialized) return Future.value();
    return _initializing ??= _initialize(_generation);
  }

  Future<void> _initialize(int generation) async {
    _loading = true;
    final owner = _owner!;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_current(generation)) return;
      _stores = prefs.getStringList('favorite_stores_$owner') ?? [];
      _dishes = prefs.getStringList('favorite_dishes_$owner') ?? [];
      _notify();
      await _load();
    } finally {
      if (_current(generation)) {
        _initialized = true;
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> _persist(int generation) async {
    final owner = _owner!;
    final stores = List<String>.from(_stores),
        dishes = List<String>.from(_dishes);
    final prefs = await SharedPreferences.getInstance();
    if (!_current(generation)) return;
    await prefs.setStringList('favorite_stores_$owner', stores);
    await prefs.setStringList('favorite_dishes_$owner', dishes);
  }

  Future<void> _load() async {
    if (!_remote || _pending.isNotEmpty) return;
    final generation = _generation, revision = _revision;
    Map<String, dynamic> result;
    try {
      result = await _read();
    } catch (_) {
      return;
    }
    if (!_current(generation) || revision != _revision || _pending.isNotEmpty)
      return;
    if (result['success'] != true) return; // Retain cache only on read failure.
    final rows = result['data']?['favorites'];
    if (rows is! List) return;
    final lookup = <String, String>{};
    for (final row in rows) {
      final id = row['business_id'] ?? row['businessId'];
      final favorite = row['id'] ?? row['favoriteId'];
      if (id is String && favorite is String) lookup[id] = favorite;
    }
    _lookup = lookup;
    _stores =
        lookup.keys.toList(); // An empty successful response clears cache.
    await _persist(generation);
    _notify();
  }

  Future<void> toggleStoreFavorite(
    String id,
    String name, {
    String? storeImage,
    String? storeCategory,
  }) {
    _ensureAccount();
    final existing = _pending[id];
    if (existing != null) return existing;
    final generation = _generation;
    final operation = _toggle(
      id,
      name,
      storeImage ?? '',
      storeCategory ?? '',
      generation,
    );
    _pending[id] = operation;
    return operation.whenComplete(() {
      if (_current(generation)) {
        _pending.remove(id);
        _notify();
      }
    });
  }

  Future<void> _toggle(
    String id,
    String name,
    String image,
    String category,
    int generation,
  ) async {
    await initialize();
    if (!_current(generation)) return;
    final wasFavorite = isStoreFavorite(id);
    final oldId = _lookup[id];
    _revision++;
    if (wasFavorite) {
      _stores.remove(id);
    } else {
      _stores.add(id);
    }
    _notify();
    if (!_remote) {
      await _persist(generation);
      return;
    }
    try {
      Map<String, dynamic> result;
      if (wasFavorite) {
        String? favoriteId = oldId;
        if (favoriteId == null) {
          final status = await _check(id);
          if (!_current(generation)) return;
          if (status['success'] != true)
            throw StateError('تعذر التحقق من المحفوظة');
          if (status['data']?['is_favorite'] != true) {
            _lookup.remove(id);
            await _persist(generation);
            return;
          }
          favoriteId = status['data']?['favoriteId'];
        }
        if (favoriteId == null) throw StateError('تعذر التحقق من المحفوظة');
        result = await _remove(favoriteId);
      } else {
        result = await _add(id, name, image, category);
      }
      if (!_current(generation)) return;
      if (result['success'] != true) {
        // A timeout/duplicate response may follow a committed write. Verify
        // before reverting the heart, without replaying a mutation blindly.
        final status = await _check(id);
        if (!_current(generation)) return;
        if (status['success'] != true ||
            status['data']?['is_favorite'] != !wasFavorite) {
          throw StateError('تعذر حفظ التغيير. أعد المحاولة');
        }
        if (!wasFavorite && status['data']?['favoriteId'] is String) {
          _lookup[id] = status['data']['favoriteId'];
        }
      } else if (!wasFavorite) {
        final favoriteId =
            result['data']?['id'] ?? result['data']?['favoriteId'];
        if (favoriteId is String) _lookup[id] = favoriteId;
      }
      if (wasFavorite) _lookup.remove(id);
      await _persist(generation);
    } catch (_) {
      if (_current(generation)) {
        _stores.remove(id);
        if (wasFavorite) _stores.add(id);
        if (oldId != null)
          _lookup[id] = oldId;
        else
          _lookup.remove(id);
        _notify();
        await _persist(generation);
        throw StateError('تعذر حفظ التغيير في المحفوظة. أعد المحاولة');
      }
    }
  }

  Future<void> loadFavoritesFromServer() async {
    await initialize();
    await _load();
  }

  Future<void> refreshFavoritesFromServer() => loadFavoritesFromServer();
  Future<void> syncWithServer() => loadFavoritesFromServer();
  Future<void> loadFavoritesFromLocal() => initialize();
  Future<bool> checkRestaurantFavoriteStatus(String id) async {
    await initialize();
    return isStoreFavorite(id);
  }

  Future<void> resetForNewUser() async {
    _ensureAccount();
    await initialize();
  }

  Future<void> reloadAfterLogin() => resetForNewUser();
  Future<void> clearAllFavorites() async {
    _generation++;
    _revision++;
    _stores = [];
    _dishes = [];
    _lookup = {};
    _pending.clear();
    _owner = null;
    _initialized = false;
    _initializing = null;
    _notify(); // Logout clears memory, not other accounts' saved preferences.
  }

  Future<void> toggleDishFavorite(String id) async {
    await initialize();
    if (isDishFavorite(id)) {
      _dishes.remove(id);
    } else {
      _dishes.add(id);
    }
    await _persist(_generation);
    _notify();
  }

  Future<void> addDishFavorite(String id) async {
    await initialize();
    if (!isDishFavorite(id)) {
      _dishes.add(id);
      await _persist(_generation);
      _notify();
    }
  }

  Future<void> removeDishFavorite(String id) async {
    await initialize();
    _dishes.remove(id);
    await _persist(_generation);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
