import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import 'delivery_address_manager.dart';
import 'delivery_quote_checkout.dart';
import 'discount_item_policy.dart';
import 'pending_offer.dart';
import 'session_service.dart';

Map<String, dynamic> invoiceRequest({
  required String branch,
  required List<Map<String, dynamic>> items,
  required Map<String, dynamic> address,
  String storeName = 'المطعم',
  String storeAddress = 'العنوان غير محدد',
  int tip = 0,
  double discount = 0,
  String? discountId,
  String? platformDiscountId,
  String? deliveryBenefitId,
  String? promoCode,
  String? offerSlideId,
}) => {
  'storeId': branch,
  'storeName': storeName,
  'storeAddress': storeAddress,
  'paymentMethod': 'cash',
  'deliveryAddress': address,
  'items':
      items
          .map(
            (item) => {
              'id': item['id'],
              'name': item['name'],
              'price': item['price'].toString(),
              'quantity': item['quantity'],
              'customizations':
                  item['selected_options'] ??
                  item['selectedOptions'] ??
                  item['customizations'] ??
                  [],
              ...discountSelectionFields(item),
            },
          )
          .toList(),
  'tip': tip,
  'discount': discount,
  'discountId': discountId,
  'promoCode': promoCode,
  if (platformDiscountId != null) 'platformDiscountId': platformDiscountId,
  if (deliveryBenefitId != null) 'deliveryBenefitId': deliveryBenefitId,
  'offerSlideId': offerSlideId,
};

class CheckoutInvoice {
  final Map<String, dynamic> proposal;
  final DeliveryQuote quote;
  CheckoutInvoice(Map<String, dynamic> value, this.quote)
    : proposal = Map.unmodifiable(
        jsonDecode(jsonEncode(value)) as Map<String, dynamic>,
      );
  DateTime get expiresAt => DateTime.parse(proposal['expiresAt']);
}

/// Volatile, bounded, account/address/basket-scoped invoices. Never creates an
/// order or persists consent. Reuse never extends a server expiry.
class CheckoutInvoiceStore extends ChangeNotifier {
  static final instance = CheckoutInvoiceStore();
  final String? Function() account;
  final Future<String?> Function() freshToken;
  final DeliveryQuoteCheckout Function() createCheckout;
  final DateTime Function() now;
  final _cache = <String, CheckoutInvoice>{};
  final _quotes = <String, DeliveryQuote>{};
  final _quoteRunning = <String, Future<DeliveryQuote>>{};
  final _running = <String, Future<CheckoutInvoice?>>{};
  final _retryAt = <String, DateTime>{};
  final _errors = <String, String>{};
  String? _owner;
  int _generation = 0;
  bool _disposed = false;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  CheckoutInvoiceStore({
    String? Function()? account,
    Future<String?> Function()? freshToken,
    DeliveryQuoteCheckout Function()? createCheckout,
    DateTime Function()? now,
  }) : account = account ?? (() => SessionService.instance.currentUserId),
       freshToken = freshToken ?? (() => SessionService.instance.getToken()),
       createCheckout =
           createCheckout ??
           (() => DeliveryQuoteCheckout(
             account: () => SessionService.instance.currentUserId,
             token: () => SessionService.instance.accessToken,
           )),
       now = now ?? DateTime.now;
  static dynamic _canonical(dynamic v) =>
      v is List
          ? v.map(_canonical).toList()
          : v is Map
          ? {
            for (final k in (v.keys.cast<String>().toList()..sort()))
              k: _canonical(v[k]),
          }
          : v is double && v.isFinite && v == v.truncateToDouble()
          ? v.toInt()
          : v;
  void _syncOwner() {
    if (_owner != account()) {
      _owner = account();
      _generation++;
      _cache.clear();
      _quotes.clear();
      _quoteRunning.clear();
      _errors.clear();
      _retryAt.clear();
      _running.clear();
    }
  }

  Map<String, dynamic> _pricingAddress(Map<String, dynamic> r) {
    final a = r['deliveryAddress'] as Map;
    return {
      'id': a['id'],
      'latitude': a['latitude'],
      'longitude': a['longitude'],
    };
  }

  String key(Map<String, dynamic> request) {
    _syncOwner();
    return jsonEncode(
      _canonical({
        'owner': account(),
        'branch': request['storeId'],
        'address': _pricingAddress(request),
        'items': request['items'],
        'paymentMethod': request['paymentMethod'],
        'tip': request['tip'] ?? 0,
        'discount': request['discount'] ?? 0,
        'discountId': request['discountId'],
        'platformDiscountId': request['platformDiscountId'],
        'deliveryBenefitId': request['deliveryBenefitId'],
        'promoCode': request['promoCode'],
        'offerSlideId': request['offerSlideId'],
      }),
    );
  }

  String _routeKey(Map<String, dynamic> r) =>
      jsonEncode(_canonical([account(), r['storeId'], _pricingAddress(r)]));
  CheckoutInvoice? peek(Map<String, dynamic> r) {
    final entry = _cache[key(r)];
    return entry != null &&
            now().isBefore(entry.expiresAt) &&
            now().isBefore(entry.quote.expiresAt)
        ? entry
        : null;
  }

  bool loading(Map<String, dynamic> r) => _running.containsKey(key(r));
  String? error(Map<String, dynamic> r) =>
      peek(r) != null ? null : _errors[key(r)];
  void clear() {
    _generation++;
    _cache.clear();
    _quotes.clear();
    _quoteRunning.clear();
    _retryAt.clear();
    _errors.clear();
    _running.clear();
    _emit();
  }

  bool remember(
    Map<String, dynamic> r,
    Map<String, dynamic> p,
    DeliveryQuote quote,
  ) {
    if (p['quoteId'] != quote.id ||
        r['storeId'] != quote.branchId ||
        r['deliveryAddress']['id'] != quote.addressId ||
        !now().isBefore(quote.expiresAt))
      return false;
    validateCommercialCheckoutAmounts(p, quote.feeMinor);
    final expiry = DateTime.tryParse(p['expiresAt'] ?? '');
    if (expiry == null ||
        !now().isBefore(expiry) ||
        expiry.isAfter(quote.expiresAt))
      return false;
    final k = key(r);
    if (_cache.length >= 12 && !_cache.containsKey(k))
      _cache.remove(_cache.keys.first);
    _cache[k] = CheckoutInvoice(p, quote);
    _quotes[_routeKey(r)] = quote;
    if (_quotes.length > 12) _quotes.remove(_quotes.keys.first);
    _errors.remove(k);
    _retryAt.remove(k);
    _emit();
    return true;
  }

  Future<CheckoutInvoice?> ensure(
    Map<String, dynamic> r, {
    bool retry = false,
    bool refresh = false,
  }) {
    final k = key(r), cached = peek(r);
    if (cached != null && !refresh) return Future.value(cached);
    final running = _running[k];
    if (running != null) return running;
    if (account() == null ||
        account() == 'guest' ||
        (r['items'] as List).isEmpty)
      return Future.value(null);
    if (!retry && _retryAt[k] != null && now().isBefore(_retryAt[k]!))
      return Future.value(null);
    final generation = _generation, owner = account();
    final task = _prepare(r, k, owner!, generation);
    _running[k] = task;
    return task.whenComplete(() {
      if (identical(_running[k], task)) {
        _running.remove(k);
        _emit();
      }
    });
  }

  Future<CheckoutInvoice?> _prepare(
    Map<String, dynamic> request,
    String k,
    String owner,
    int generation,
  ) async {
    final r = Map<String, dynamic>.from(jsonDecode(jsonEncode(request)));
    final checkout = createCheckout();
    try {
      await freshToken();
      if (account() != owner || _generation != generation) return null;
      if (!checkout.ready) await checkout.restore();
      if (checkout.busy || checkout.pending) return null;
      final routeKey = _routeKey(r);
      var routeTask = _quoteRunning[routeKey];
      if (routeTask == null) {
        final task = () async {
          final old = _quotes[routeKey];
          if (old != null) checkout.adoptCachedQuote(old, owner);
          await checkout.ensureFresh(r['storeId'], r['deliveryAddress']['id']);
          if (account() != owner ||
              _generation != generation ||
              !checkout.matches(r['storeId'], r['deliveryAddress']['id']))
            throw StateError('QUOTE_UNAVAILABLE');
          final quote = checkout.quote!;
          _quotes[routeKey] = quote;
          return quote;
        }();
        routeTask = task;
        _quoteRunning[routeKey] = task;
      }
      DeliveryQuote quote;
      try {
        quote = await routeTask;
      } finally {
        if (identical(_quoteRunning[routeKey], routeTask))
          _quoteRunning.remove(routeKey);
      }
      if (account() != owner || _generation != generation) return null;
      checkout.adoptCachedQuote(quote, owner);
      final proposal = await checkout.previewInvoice(r);
      if (account() != owner || _generation != generation) return null;
      remember(r, proposal, quote);
      return _cache[k];
    } catch (e) {
      if (account() == owner && _generation == generation) {
        if (_retryAt.length >= 24 && !_retryAt.containsKey(k)) {
          final old = _retryAt.keys.first;
          _retryAt.remove(old);
          _errors.remove(old);
        }
        _retryAt[k] = now().add(
          Duration(
            seconds:
                e is InvoicePreviewUnavailable &&
                        e.code == 'MINIMUM_ORDER_NOT_MET'
                    ? 60
                    : 10,
          ),
        );
        _errors[k] =
            e is InvoicePreviewUnavailable && e.code == 'MINIMUM_ORDER_NOT_MET'
                ? 'أكمل الحد الأدنى للمطعم لعرض الفاتورة'
                : 'تعذر تحديث الفاتورة الآن';
      }
      return null;
    } finally {
      checkout.dispose();
    }
  }

  Map<String, dynamic>? basketRequest(
    String branch,
    List<Map<String, dynamic>> items, {
    String storeName = 'المطعم',
    String storeAddress = 'العنوان غير محدد',
  }) {
    final a = DeliveryAddressManager.instance.activeAddress;
    if (a?.addressId == null ||
        items.isEmpty ||
        items.any((i) => i['store_id'] != branch))
      return null;
    return invoiceRequest(
      branch: branch,
      items: items,
      storeName: storeName,
      storeAddress: storeAddress,
      address: {
        'id': a!.addressId,
        'latitude': a.latitude,
        'longitude': a.longitude,
        'fullAddress': a.formattedAddress,
      },
      offerSlideId:
          PendingOffer.current?.merchantId == branch
              ? PendingOffer.current?.slideId
              : null,
    );
  }

  Future<void> warmBasket(
    String branch,
    List<Map<String, dynamic>> items, {
    String storeName = 'المطعم',
    String storeAddress = 'العنوان غير محدد',
  }) async {
    if (!ApiConfig.commercialPricingEnabled) return;
    final r = basketRequest(
      branch,
      items,
      storeName: storeName,
      storeAddress: storeAddress,
    );
    if (r != null) {
      final cached = peek(r);
      await ensure(
        r,
        refresh:
            cached != null &&
            cached.expiresAt.difference(now()) < const Duration(seconds: 30),
      );
    }
  }
}
