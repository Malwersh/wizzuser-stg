import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'delivery_address_manager.dart';
import 'session_service.dart';

class StorefrontPreview {
  final Map<String, dynamic> data;
  StorefrontPreview(Map<String, dynamic> value)
    : data = Map.unmodifiable(value) {
    final m = data['customerDeliveryFee'];
    if (data['kind'] != 'STOREFRONT_PREVIEW' ||
        data['schemaVersion'] != 1 ||
        m is! Map ||
        m['moneySchemaVersion'] != 1 ||
        m['currency'] != 'IQD' ||
        m['scale'] != 1000 ||
        m['minorAmount'] is! int ||
        m['minorAmount'] < 0 ||
        DateTime.tryParse(data['expiresAt'] ?? '') == null)
      throw const FormatException('Invalid storefront preview');
    for (final f in ['roadDistanceMeters', 'deliveryDurationSeconds']) {
      if (data[f] is! num || !data[f].isFinite || data[f] < 0)
        throw const FormatException('Invalid route');
    }
    final p = data['preparationMinutes'];
    if (p != null && (p is! int || p < 5 || p > 120))
      throw const FormatException('Invalid preparation time');
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

/// Shared, bounded cache for informational prices. Account/address/coordinates and
/// basket are part of the key; an old asynchronous result can never replace a new address.
class StorefrontPricing extends ChangeNotifier {
  static final instance = StorefrontPricing();
  final String? Function() account, token, addressId, addressRevision;
  final Future<String?> Function() freshToken;
  final http.Client client;
  final DateTime Function() now;
  final _cache = <String, StorefrontPreview>{};
  final _running = <String, Future<StorefrontPreview?>>{};
  final _errors = <String, String>{};
  final _retryAt = <String, DateTime>{};
  StreamSubscription? _addresses, _sessions;
  String? _lastAccount;
  int _active = 0;
  final _slots = <Completer<void>>[];
  StorefrontPricing({
    String? Function()? account,
    String? Function()? token,
    Future<String?> Function()? freshToken,
    String? Function()? addressId,
    String? Function()? addressRevision,
    http.Client? client,
    DateTime Function()? now,
    bool listenToAddress = true,
  }) : account = account ?? (() => SessionService.instance.currentUserId),
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
          _errors.clear();
          notifyListeners();
        }
      });
    }
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
            revision != addressRevision())
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
            revision != addressRevision())
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
        _errors.remove(k);
        return result;
      } catch (_) {
        if (owner == account() &&
            address == addressId() &&
            revision == addressRevision()) {
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
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _addresses?.cancel();
    _sessions?.cancel();
    super.dispose();
  }
}
