import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/interface_layout.dart';
import 'home_slideshow_service.dart';
import 'session_service.dart';
import 'browsing_location_service.dart';
import 'delivery_address_manager.dart';

class InterfaceLayoutService {
  static final instance = InterfaceLayoutService();
  final String Function()? scopeReader;
  final Future<InterfaceLayout> Function(String, String, String)? fetcher;
  InterfaceLayoutService({this.scopeReader, this.fetcher});
  final _cache = <String, InterfaceLayout>{};
  final _pending = <String, Future<InterfaceLayout>>{};
  String get scope =>
      scopeReader?.call() ??
      '${SessionService.instance.isLoggedIn ? SessionService.instance.currentUserId : "guest"}:${BrowsingLocationService.instance.selection?.regionId ?? DeliveryAddressManager.instance.activeAddress?.regionId ?? ""}';
  Future<InterfaceLayout> load(
    String surface,
    String branch, {
    bool force = false,
  }) async {
    final owner = scope, key = '$owner:$surface:$branch', cached = _cache[key];
    if (_pending[key] != null) return _pending[key]!;
    if (!force && cached?.fresh == true) return cached!;
    final future =
        fetcher?.call(surface, branch, owner) ?? _fetch(surface, branch, owner);
    _pending[key] = future;
    try {
      final result = await future;
      if (owner != scope) throw StateError('Interface account changed');
      if (owner == scope) {
        _cache.removeWhere((k, v) => !k.startsWith('$owner:') || !v.fresh);
        if (_cache.length > 40) _cache.clear();
        _cache[key] = result;
      }
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  Future<InterfaceLayout> _fetch(
    String surface,
    String branch,
    String owner,
  ) async {
    final session = SessionService.instance,
        token = session.isLoggedIn ? await session.getToken() : null;
    if (session.isLoggedIn && token == null)
      throw StateError('Session unavailable');
    final region =
        BrowsingLocationService.instance.selection?.regionId ??
        DeliveryAddressManager.instance.activeAddress?.regionId;
    final uri = Uri.parse(HomeSlideshowService.baseUrl).replace(
      queryParameters: {
        'surface': surface,
        'offerSlotsVersion': '1',
        'branchId': branch,
        if (region != null) 'regionId': region,
        if (session.isLoggedIn) 'userId': session.currentUserId!,
      },
    );
    final response = await http
        .get(
          uri,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200 || scope != owner)
      throw StateError('Interface unavailable');
    return InterfaceLayout.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body)['interface']),
    );
  }
}
