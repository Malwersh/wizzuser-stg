import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/order_model.dart';
import 'session_service.dart';

/// Private, bounded session history. No guest/account crossover or database scans.
class DiscoveryHistory extends ChangeNotifier {
  static final instance = DiscoveryHistory();
  final Future<List<OrderModel>> Function(String)? loader;
  final String Function()? account;
  final http.Client? client;
  final Future<String?> Function()? tokenReader;
  DiscoveryHistory({this.loader, this.account, this.client, this.tokenReader});
  String? _owner;
  bool _restored = false;
  DateTime? _loaded;
  Future<void>? _pending;
  List<OrderModel> _orders = [];
  final List<String> _stores = [];
  final Map<String, List<String>> _products = {};
  String get scope =>
      account?.call() ??
      (SessionService.instance.isLoggedIn
          ? SessionService.instance.currentUserId ?? 'guest'
          : 'guest');
  void _check() {
    if (_owner != scope) {
      _owner = scope;
      _orders = [];
      _stores.clear();
      _products.clear();
      _loaded = null;
      _pending = null;
      _restored = false;
    }
  }

  List<String> get pastStores {
    _check();
    return _orders.map((o) => o.storeId).toSet().toList();
  }

  List<String> get recentStores {
    _check();
    return List.unmodifiable(_stores);
  }

  List<String> products(String branch, {bool last = false}) {
    _check();
    final orders = _orders.where((o) => o.storeId == branch);
    return (last ? orders.take(1) : orders)
        .expand((o) => o.items)
        .map((p) => p.productId.isEmpty ? p.dishId : p.productId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> recentProducts(String branch) {
    _check();
    return List.unmodifiable(_products[branch] ?? []);
  }

  void viewedStore(String branch) {
    _check();
    _stores.remove(branch);
    _stores.insert(0, branch);
    if (_stores.length > 40) _stores.removeLast();
    _persist();
    notifyListeners();
  }

  void viewedProduct(String branch, String product) {
    _check();
    final list = _products.putIfAbsent(branch, () => []);
    list.remove(product);
    list.insert(0, product);
    if (list.length > 40) list.removeLast();
    if (_products.length > 40) _products.remove(_products.keys.first);
    _persist();
    notifyListeners();
  }

  Future<void> load() async {
    _check();
    await _restore();
    _check();
    if (scope == 'guest' ||
        _loaded != null &&
            DateTime.now().difference(_loaded!) < const Duration(minutes: 1))
      return;
    if (_pending != null) return _pending!;
    final owner = scope;
    final future = _fetch(owner);
    _pending = future;
    try {
      await future;
    } finally {
      if (_pending == future) _pending = null;
    }
  }

  Future<void> _fetch(String owner) async {
    try {
      final orders =
          loader != null ? await loader!(owner) : await _request(owner);
      if (owner != scope) return;
      _orders =
          orders.where((o) => o.status == OrderStatus.delivered).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loaded = DateTime.now();
      notifyListeners();
    } catch (_) {
      /* Hide personal section on failure; do not reuse another identity. */
    }
  }

  Future<List<OrderModel>> _request(String owner) async {
    final token =
        await (tokenReader?.call() ?? SessionService.instance.getToken());
    if (token == null) throw StateError('Session unavailable');
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/users/${Uri.encodeComponent(owner)}/orders',
    ).replace(queryParameters: {'status': 'completed', 'historyDays': '30'});
    final response = await (client?.get ?? http.get)(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('History unavailable');
    final payload = jsonDecode(response.body);
    if (payload['success'] != true) throw StateError('History unavailable');
    final data = payload['orders'];
    if (data is! List) throw const FormatException('History format');
    return data
        .map((o) => OrderModel.fromJson(Map<String, dynamic>.from(o)))
        .toList();
  }

  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    final owner = scope;
    try {
      final prefs = await SharedPreferences.getInstance(),
          raw = prefs.getString('discovery_recent_v1_$owner');
      if (raw == null || owner != scope) return;
      final saved = jsonDecode(raw);
      final stores = (saved['stores'] as List? ?? []).whereType<String>().take(
        40,
      );
      for (final id in stores)
        if (!_stores.contains(id) && _stores.length < 40) _stores.add(id);
      final products = saved['products'];
      if (products is Map)
        for (final e in products.entries.take(40)) {
          final list = _products.putIfAbsent(e.key.toString(), () => []);
          for (final id in (e.value as List).whereType<String>().take(40))
            if (!list.contains(id) && list.length < 40) list.add(id);
        }
      notifyListeners();
    } catch (_) {
      /* Corrupt local observations do not affect browsing. */
    }
  }

  Future<void> _persist() async {
    final owner = scope;
    await _restore();
    if (owner != scope) return;
    final data = jsonEncode({'stores': _stores, 'products': _products});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('discovery_recent_v1_$owner', data);
    } catch (_) {}
  }
}
