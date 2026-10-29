import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'session_service.dart';
import 'browsing_location_service.dart';
import 'delivery_address_manager.dart';
import 'checkout_invoice_store.dart' show invoiceRequest;
import 'pending_offer.dart';
import 'delivery_quote_checkout.dart';

class PointInvoiceFailure implements Exception {
  const PointInvoiceFailure(this.status, this.code);
  final int status;
  final String code;
  String get message {
    if (status == 401 ||
        code == 'AUTH_REQUIRED' ||
        code == 'ACCOUNT_UNAVAILABLE') {
      return 'تعذر التحقق من جلسة الدخول. أعد تسجيل الدخول ثم تابع طلبك.';
    }
    return switch (code) {
      'INSUFFICIENT_STOCK' || 'GOODS_UNAVAILABLE' =>
        'الكمية المطلوبة غير متوفرة الآن. حدّث السلة أو خفّض الكمية ثم أعد المحاولة.',
      'CART_PRICE_CHANGED' =>
        'تغيّر سعر أحد الأصناف. حدّث السلة من المطعم ثم تابع.',
      'MINIMUM_ORDER_NOT_MET' =>
        'قيمة الأصناف أقل من الحد الأدنى للمطعم. أضف أصنافًا للمتابعة.',
      'DISCOUNT_UNAVAILABLE' ||
      'OFFER_NOT_ELIGIBLE' ||
      'BENEFIT_EXPIRED' ||
      'BENEFIT_PAUSED' =>
        'العرض المختار غير متاح الآن. أزله أو اختر عرضًا آخر ثم تابع.',
      'QUOTE_EXPIRED' || 'COMMERCIAL_QUOTE_EXPIRED' =>
        'انتهت صلاحية حساب الإجمالي. أعد المحاولة لتحديثه.',
      _ => 'تعذر تجهيز إجمالي الطلب من الخدمة حاليًا. أعد المحاولة بعد قليل.',
    };
  }
}

/// Display-only complete invoice by confirmed point, never a checkout consent.
class PointInvoice321 extends ChangeNotifier {
  static final instance = PointInvoice321();
  final http.Client client;
  final String? Function() owner;
  final Future<String?> Function() token;
  final DateTime Function() now;
  final _cache = <String, Map<String, dynamic>>{}, _errors = <String, String>{};
  final _running = <String, Future<void>>{};
  String? _scope;
  int _generation = 0;
  PointInvoice321({
    http.Client? client,
    String? Function()? owner,
    Future<String?> Function()? token,
    DateTime Function()? now,
  }) : client = client ?? http.Client(),
       owner = owner ?? (() => SessionService.instance.currentUserId),
       token = token ?? (() => SessionService.instance.getToken()),
       now = now ?? DateTime.now;
  static dynamic canonical(dynamic v) =>
      v is Map
          ? {
            for (final k in (v.keys.cast<String>().toList()..sort()))
              k: canonical(v[k]),
          }
          : v is List
          ? v.map(canonical).toList()
          : v is double && v.isFinite && v == v.truncateToDouble()
          ? v.toInt()
          : v;

  String key(Map<String, dynamic> content) {
    if (_scope != owner()) {
      _scope = owner();
      _generation++;
      _cache.clear();
      _errors.clear();
      _running.clear();
    }
    final pricing =
        Map<String, dynamic>.from(content)
          ..remove('storeName')
          ..remove('storeAddress');
    return jsonEncode(canonical([owner(), pricing]));
  }

  Map<String, dynamic>? peek(Map<String, dynamic> r) {
    final p = _cache[key(r)];
    return p != null && now().isBefore(DateTime.parse(p['expiresAt']))
        ? p
        : null;
  }

  String? error(Map<String, dynamic> r) => _errors[key(r)];
  Future<void> ensure(
    Map<String, dynamic> r, {
    bool retry = false,
    bool refresh = false,
  }) {
    final k = key(r);
    if (owner() == null ||
        !refresh && peek(r) != null ||
        !retry && _errors.containsKey(k))
      return Future.value();
    final running = _running[k];
    if (running != null) return running;
    late final Future<void> task;
    task = _load(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(r))),
      k,
      owner()!,
      _generation,
    ).whenComplete(() {
      if (identical(_running[k], task)) _running.remove(k);
    });
    _running[k] = task;
    return task;
  }

  static Map<String, dynamic>? basketRequest(
    String branch,
    List<Map<String, dynamic>> items, {
    String storeName = 'المطعم',
    String storeAddress = 'العنوان غير محدد',
  }) {
    final selected = BrowsingLocationService.instance.selection;
    final active = DeliveryAddressManager.instance.activeAddress;
    final lat = selected == null ? active?.latitude : selected.latitude;
    final lng = selected == null ? active?.longitude : selected.longitude;
    if (branch.isEmpty ||
        items.isEmpty ||
        items.any((i) => i['store_id'] != branch) ||
        lat == null ||
        lng == null)
      return null;
    final r = invoiceRequest(
      branch: branch,
      items: items,
      address: {},
      storeName: storeName,
      storeAddress: storeAddress,
      offerSlideId:
          PendingOffer.current?.merchantId == branch
              ? PendingOffer.current?.slideId
              : null,
    );
    r.remove('deliveryAddress');
    r['pricingPoint'] = {'latitude': lat, 'longitude': lng};
    return r;
  }

  Future<void> warmRequest(Map<String, dynamic> r) async {
    final current = peek(r);
    if (error(r) != null) return;
    await ensure(
      r,
      refresh:
          current != null &&
          DateTime.parse(current['expiresAt']).difference(now()) <
              const Duration(seconds: 30),
    );
  }

  Future<void> warmBasket(
    String branch,
    List<Map<String, dynamic>> items, {
    String storeName = 'المطعم',
  }) async {
    if (!ApiConfig.commercialPricingEnabled) return;
    final r = basketRequest(branch, items, storeName: storeName);
    if (r != null) await warmRequest(r);
  }

  Future<void> _load(
    Map<String, dynamic> r,
    String k,
    String id,
    int gen,
  ) async {
    try {
      final t = await token();
      if (owner() != id || _generation != gen) return;
      if (t == null) throw const PointInvoiceFailure(401, 'AUTH_REQUIRED');
      final response = await client
          .post(
            Uri.parse(
              ApiConfig.buildUrl(
                '${ApiConfig.ordersEndpoint}/commercial-preview',
              ),
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $t',
              'X-Customer-Id': id,
            },
            body: jsonEncode({
              ...r,
              'userId': id,
              'action': 'preview_commercial_point',
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (owner() != id || _generation != gen) return;
      final result = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || result['success'] != true) {
        final code = result['code'];
        throw PointInvoiceFailure(
          response.statusCode,
          code is String && RegExp(r'^[A-Z0-9_]{2,80}$').hasMatch(code)
              ? code
              : 'POINT_INVOICE_UNAVAILABLE',
        );
      }
      final p = result['pointInvoice'];
      if (response.statusCode != 200 ||
          result['success'] != true ||
          p is! Map ||
          p['kind'] != 'POINT_INVOICE' ||
          p['informationalOnly'] != true ||
          p['requiresFinalConfirmation'] != true ||
          p['branchId'] != r['storeId'] ||
          jsonEncode(canonical(p['point'])) !=
              jsonEncode(canonical(r['pricingPoint'])))
        throw const FormatException();
      final expires = DateTime.tryParse(p['expiresAt'] ?? '');
      if (expires == null ||
          !now().isBefore(expires) ||
          expires.difference(now()).inSeconds > 120)
        throw const FormatException();
      validateCommercialCheckoutAmounts(
        p,
        (p['referenceDeliveryFee'] ?? p['deliveryFee'])['minorAmount'],
      );
      if (_cache.length >= 20) _cache.remove(_cache.keys.first);
      _cache[k] = Map<String, dynamic>.from(p);
      _errors.remove(k);
    } catch (failure) {
      if (owner() == id && _generation == gen) {
        _errors[k] =
            failure is PointInvoiceFailure
                ? failure.message
                : failure is TimeoutException || failure is http.ClientException
                ? 'تعذر الاتصال بخدمة حساب الإجمالي. تحقق من الإنترنت ثم أعد المحاولة.'
                : 'تعذر التحقق من إجمالي الطلب حاليًا. أعد المحاولة بعد قليل.';
        if (failure is PointInvoiceFailure) {
          debugPrint(
            'Point invoice rejected: status=${failure.status}, code=${failure.code}',
          );
        }
      }
    }
    if (owner() == id && _generation == gen) notifyListeners();
  }
}
