import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'delivery_address_manager.dart';
import 'session_service.dart';

class StorefrontRoute {
  final Map<String, dynamic> data;
  StorefrontRoute(Map<String, dynamic> value) : data = Map.unmodifiable(value) {
    if (!['STOREFRONT_ROUTE', 'STOREFRONT_PREVIEW'].contains(data['kind']) ||
        data['schemaVersion'] != 1 ||
        DateTime.tryParse(data['expiresAt'] ?? '') == null) {
      throw const FormatException('Invalid storefront route');
    }
    for (final f in ['roadDistanceMeters', 'deliveryDurationSeconds']) {
      if (data[f] is! num || !data[f].isFinite || data[f] < 0) {
        throw const FormatException('Invalid route');
      }
    }
    final p = data['preparationMinutes'];
    if (p != null && (p is! int || p < 5 || p > 120)) {
      throw const FormatException('Invalid preparation time');
    }
    final eta = data['arrivalMinutes'];
    if (eta != null &&
        (p == null ||
            eta is! Map ||
            eta['minimum'] is! int ||
            eta['maximum'] is! int ||
            eta['minimum'] < p ||
            eta['maximum'] < eta['minimum'])) {
      throw const FormatException('Invalid arrival time');
    }
  }
  String get preparationText =>
      data['preparationMinutes'] == null
          ? 'لم يحدد المطعم المدة'
          : 'نحو ${data['preparationMinutes']} دقيقة';
  String get arrivalText =>
      data['arrivalMinutes'] == null
          ? 'غير متاح حاليًا'
          : '${data['arrivalMinutes']['minimum']}–${data['arrivalMinutes']['maximum']} دقيقة';
  String get distanceText {
    final n = (data['roadDistanceMeters'] as num).toDouble();
    return n < 1000 ? '${n.round()} م' : '${(n / 1000).toStringAsFixed(1)} كم';
  }

  DateTime get expiresAt => DateTime.parse(data['expiresAt']);
}

class StorefrontPreview extends StorefrontRoute {
  StorefrontPreview(super.value) {
    final m = data['customerDeliveryFee'];
    if (data['kind'] != 'STOREFRONT_PREVIEW' ||
        m is! Map ||
        m['moneySchemaVersion'] != 1 ||
        m['currency'] != 'IQD' ||
        m['scale'] != 1000 ||
        m['minorAmount'] is! int ||
        m['minorAmount'] < 0) {
      throw const FormatException('Invalid storefront preview');
    }
  }
  int? get minimumOrderAmountIqd {
    final value = data['minimumOrderAmountIqd'];
    if (value == null || value == 0) return null;
    if (value is! int || value < 0 || value > 1000000000)
      throw const FormatException('Invalid minimum order');
    return value;
  }

  double get fee => data['customerDeliveryFee']['minorAmount'] / 1000;
  String get feeText =>
      fee == 0
          ? 'توصيل مجاني'
          : '${fee.toStringAsFixed(fee == fee.roundToDouble() ? 0 : 3)} د.ع';
}

/// Shared, bounded cache for informational prices. Account/address/coordinates and
/// basket are part of the key; an old asynchronous result can never replace a new address.
class StorefrontPricing extends ChangeNotifier {
  static final instance = StorefrontPricing();
  final String? Function() account, token, addressId, addressRevision;
  final Future<String?> Function() freshToken;
  final http.Client client;
  final DateTime Function() now;
  final _businessFacts = <String, Map<String, dynamic>>{};
  final String? Function() regionId;
  final _cache = <String, StorefrontPreview>{};
  // Route information is independent of basket contents. Never reuse its fee.
  final _routes = <String, StorefrontRoute>{};
  final _running = <String, Future<StorefrontPreview?>>{};
  final _errors = <String, String>{};
  final _retryAt = <String, DateTime>{};
  StreamSubscription? _addresses, _sessions;
  String? _lastAccount;
  int _active = 0;
  Timer? _termsBoundary;
  bool _disposed = false;
  final _slots = <Completer<void>>[];
  StorefrontPricing({
    String? Function()? account,
    String? Function()? token,
    Future<String?> Function()? freshToken,
    String? Function()? addressId,
    String? Function()? addressRevision,
    String? Function()? regionId,
    http.Client? client,
    DateTime Function()? now,
    bool listenToAddress = true,
  }) : regionId =
           regionId ??
           (() => DeliveryAddressManager.instance.activeAddress?.regionId),
       account = account ?? (() => SessionService.instance.currentUserId),
       token = token ?? (() => SessionService.instance.accessToken),
       freshToken =
           freshToken ??
           (token != null
               ? (() async => token())
               : (() => SessionService.instance.getToken())),
       addressId =
           addressId ??
           (() => DeliveryAddressManager.instance.activeAddress?.addressId),
       addressRevision =
           addressRevision ??
           (() => jsonEncode([
             DeliveryAddressManager.instance.activeAddress?.addressId,
             DeliveryAddressManager.instance.activeAddress?.latitude,
             DeliveryAddressManager.instance.activeAddress?.longitude,
             DeliveryAddressManager.instance.activeAddress?.formattedAddress,
           ])),
       client = client ?? http.Client(),
       now = now ?? DateTime.now {
    if (listenToAddress) {
      _addresses = DeliveryAddressManager.instance.addressStream.listen((_) {
        notifyListeners();
      });
      _lastAccount = this.account();
      _sessions = SessionService.instance.sessionStateStream.listen((_) {
        if (_lastAccount != this.account()) {
          _lastAccount = this.account();
          _cache.clear();
          _routes.clear();
          _errors.clear();
          notifyListeners();
        }
      });
    }
  }
  void seedBusiness(
    String branch,
    Map<String, dynamic> facts, {
    bool onlyIfAbsent = false,
  }) {
    if (onlyIfAbsent && _businessFacts.containsKey(branch)) return;
    final selected = <String, dynamic>{
      'minimumOrderAmountIqd': facts['minimumOrderAmountIqd'],
      'averagePreparationMinutes': facts['averagePreparationMinutes'],
      'storefrontDeliveryAgreements':
          facts['storefrontDeliveryAgreements'] ?? [],
    };
    if (_businessFacts.length >= 80 && !_businessFacts.containsKey(branch))
      _businessFacts.remove(_businessFacts.keys.first);
    final previous = _businessFacts[branch];
    _businessFacts[branch] = jsonDecode(jsonEncode(selected));
    _scheduleTermsBoundary();
    if (jsonEncode(previous) != jsonEncode(selected)) {
      _cache.removeWhere((key, _) => (jsonDecode(key) as List)[3] == branch);
      _routes.removeWhere((key, _) => (jsonDecode(key) as List)[3] == branch);
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    }
  }

  void _scheduleTermsBoundary() {
    _termsBoundary?.cancel();
    DateTime? next;
    for (final facts in _businessFacts.values) {
      final rows = facts['storefrontDeliveryAgreements'];
      if (rows is! List) continue;
      for (final row in rows.whereType<Map>())
        for (final field in ['effectiveFrom', 'effectiveTo']) {
          final boundary = DateTime.tryParse(row[field]?.toString() ?? '');
          if (boundary != null &&
              boundary.isAfter(now()) &&
              (next == null || boundary.isBefore(next)))
            next = boundary;
        }
    }
    if (next != null)
      _termsBoundary = Timer(next.difference(now()), () {
        _cache.clear();
        _routes.clear();
        notifyListeners();
        _scheduleTermsBoundary();
      });
  }

  Map? _agreement(String branch) {
    if (addressId() == null || regionId() == null) return null;
    final rows = _businessFacts[branch]?['storefrontDeliveryAgreements'];
    if (rows is! List) return null;
    final matching =
        rows.whereType<Map>().where((row) {
          final from = DateTime.tryParse(
                row['effectiveFrom']?.toString() ?? '',
              ),
              to = DateTime.tryParse(row['effectiveTo']?.toString() ?? '');
          final fee = row['deliveryFeeIqd'],
              minimum = row['minimumOrderAmountIqd'];
          return from != null &&
              to != null &&
              !now().isBefore(from) &&
              now().isBefore(to) &&
              row['regionIds'] is List &&
              (row['regionIds'] as List).contains(regionId()) &&
              fee is int &&
              fee >= 0 &&
              minimum is int &&
              minimum >= 0;
        }).toList();
    return matching.length == 1 ? matching.single : null;
  }

  double? feeIqd(
    String branch,
    List<dynamic> items, {
    bool hasGoodsDiscount = false,
  }) {
    final preview = peek(branch, items, hasGoodsDiscount: hasGoodsDiscount);
    if (preview != null) return preview.fee;
    final agreement = _agreement(branch);
    return agreement == null
        ? null
        : (agreement['deliveryFeeIqd'] as int).toDouble();
  }

  int? minimumIqd(
    String branch,
    List<dynamic> items, {
    bool hasGoodsDiscount = false,
  }) {
    final preview = peek(branch, items, hasGoodsDiscount: hasGoodsDiscount);
    if (preview != null) return preview.minimumOrderAmountIqd;
    final value =
        _agreement(branch)?['minimumOrderAmountIqd'] ??
        _businessFacts[branch]?['minimumOrderAmountIqd'];
    return value is int && value > 0 ? value : null;
  }

  static List<Map<String, dynamic>> selections(List<dynamic> items) =>
      items.map((raw) {
          final r = raw as Map;
          return <String, dynamic>{
            'productId': r['productId'] ?? r['product_id'] ?? r['id'],
            'quantity': r['quantity'],
          };
        }).toList()
        ..sort((a, b) => '${a['productId']}'.compareTo('${b['productId']}'));
  String? key(
    String branch,
    List<dynamic> items, {
    bool hasGoodsDiscount = false,
  }) {
    if (account() == null ||
        account() == 'guest' ||
        addressId() == null ||
        addressId()!.isEmpty)
      return null;
    return jsonEncode([
      account(),
      addressId(),
      addressRevision(),
      branch,
      selections(items),
      hasGoodsDiscount,
      regionId(),
    ]);
  }

  StorefrontPreview? peek(
    String branch,
    List<dynamic> items, {
    bool hasGoodsDiscount = false,
  }) {
    final p = _cache[key(branch, items, hasGoodsDiscount: hasGoodsDiscount)];
    return p != null && now().isBefore(p.expiresAt) ? p : null;
  }

  String? _routeKey(String branch) {
    if (key(branch, const []) == null) return null;
    return jsonEncode([
      account(),
      addressId(),
      addressRevision(),
      branch,
      regionId(),
    ]);
  }

  StorefrontRoute? peekRoute(String branch) {
    final route = _routes[_routeKey(branch)];
    return route != null && now().isBefore(route.expiresAt) ? route : null;
  }

  String? error(
    String branch,
    List<dynamic> items, {
    bool hasGoodsDiscount = false,
  }) => _errors[key(branch, items, hasGoodsDiscount: hasGoodsDiscount)];
  Future<StorefrontPreview?> load(
    String branch,
    List<dynamic> items, {
    bool hasGoodsDiscount = false,
    bool force = false,
  }) async {
    final k = key(branch, items, hasGoodsDiscount: hasGoodsDiscount);
    if (k == null) return null;
    if (!force) {
      final cached = peek(branch, items, hasGoodsDiscount: hasGoodsDiscount);
      if (cached != null) return cached;
      if (_retryAt[k]?.isAfter(now()) == true) return null;
    }
    if (_running[k] != null) return _running[k]!;
    final owner = account(),
        address = addressId(),
        revision = addressRevision(),
        region = regionId(),
        selected = selections(items);
    Future<StorefrontPreview?> run() async {
      if (_active >= 2) {
        final slot = Completer<void>();
        _slots.add(slot);
        await slot.future;
      } else {
        _active++;
      }
      try {
        final access = await freshToken();
        if (access == null) throw const FormatException('Session unavailable');
        if (owner != account() ||
            address != addressId() ||
            revision != addressRevision() ||
            region != regionId())
          return null;
        final response = await client
            .post(
              Uri.parse(ApiConfig.buildUrl('/delivery-quotes')),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $access',
                'X-Customer-Id': owner!,
              },
              body: jsonEncode({
                'action': 'storefront_preview',
                'branchId': branch,
                'addressId': address,
                'items': selected,
                'hasGoodsDiscount': hasGoodsDiscount,
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (owner != account() ||
            address != addressId() ||
            revision != addressRevision() ||
            region != regionId())
          return null;
        final body = jsonDecode(response.body);
        if (response.statusCode != 200 || body['success'] != true) {
          final seconds = body['retryAfterSeconds'];
          _retryAt[k] = now().add(
            Duration(
              seconds:
                  seconds is int && seconds > 0 && seconds <= 60 ? seconds : 30,
            ),
          );
          // A route-only response is never placed in the price cache.
          if (response.statusCode != 401 &&
              response.statusCode != 403 &&
              response.statusCode != 429) {
            try {
              final routeResponse = await client
                  .post(
                    Uri.parse(ApiConfig.buildUrl('/delivery-quotes')),
                    headers: {
                      'Content-Type': 'application/json',
                      'Authorization': 'Bearer $access',
                      'X-Customer-Id': owner,
                    },
                    body: jsonEncode({
                      'action': 'storefront_route',
                      'branchId': branch,
                      'addressId': address,
                    }),
                  )
                  .timeout(const Duration(seconds: 20));
              if (owner != account() ||
                  address != addressId() ||
                  revision != addressRevision() ||
                  region != regionId())
                return null;
              final routeBody = jsonDecode(routeResponse.body);
              if (routeResponse.statusCode == 200 &&
                  routeBody['success'] == true) {
                final route = StorefrontRoute(
                  Map<String, dynamic>.from(routeBody['route']),
                );
                if (route.data['kind'] != 'STOREFRONT_ROUTE' ||
                    route.data['branchId'] != branch ||
                    route.data['addressId'] != address ||
                    !now().isBefore(route.expiresAt)) {
                  throw const FormatException('Route scope changed');
                }
                final routeKey = _routeKey(branch);
                if (routeKey != null) {
                  if (_routes.length >= 80) _routes.remove(_routes.keys.first);
                  _routes[routeKey] = route;
                }
              }
            } catch (_) {
              /* Preserve the pricing error; route failures never authorize checkout. */
            }
          }
          throw const FormatException('Preview unavailable');
        }
        final result = StorefrontPreview(
          Map<String, dynamic>.from(body['preview']),
        );
        if (result.data['branchId'] != branch ||
            result.data['addressId'] != address ||
            !now().isBefore(result.expiresAt))
          throw const FormatException('Preview scope changed');
        if (_cache.length >= 80) _cache.remove(_cache.keys.first);
        _cache[k] = result;
        final routeKey = _routeKey(branch);
        if (routeKey != null) {
          if (_routes.length >= 80) _routes.remove(_routes.keys.first);
          _routes[routeKey] = result;
        }
        _errors.remove(k);
        return result;
      } catch (_) {
        if (owner == account() &&
            address == addressId() &&
            revision == addressRevision() &&
            region == regionId()) {
          _errors[k] = 'تعذر حساب التوصيل. أعد المحاولة';
          _retryAt.putIfAbsent(k, () => now().add(const Duration(seconds: 30)));
        }
        return null;
      } finally {
        if (_slots.isNotEmpty) {
          _slots.removeAt(0).complete();
        } else {
          _active--;
        }
      }
    }

    final task = run();
    _running[k] = task;
    try {
      return await task;
    } finally {
      _running.remove(k);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _termsBoundary?.cancel();
    _addresses?.cancel();
    _sessions?.cancel();
    super.dispose();
  }
}
