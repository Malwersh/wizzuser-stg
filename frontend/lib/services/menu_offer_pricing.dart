import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/store_discount.dart';
import 'pending_offer.dart';
import 'session_service.dart';

class PricedMenuOffer {
  final StoreDiscount offer;
  final MenuUnitPrice unit;
  final DateTime expiresAt;
  const PricedMenuOffer(this.offer, this.unit, this.expiresAt);
}

/// Short-lived server projections for display; never replace catalog/cart prices.
class MenuOfferPricing extends ChangeNotifier {
  static final instance = MenuOfferPricing();
  final DateTime Function() now;
  final String Function() account;
  MenuOfferPricing({DateTime Function()? now, String Function()? account})
    : now = now ?? DateTime.now,
      account =
          account ?? (() => SessionService.instance.currentUserId ?? 'guest');
  final _branches = <String, Map<String, PricedMenuOffer>>{};
  String? _owner;
  Timer? _timer;
  void absorb(String branch, List<StoreDiscount> offers) {
    _checkOwner();
    final prices = <String, PricedMenuOffer>{};
    for (final offer in offers) {
      final expiry = offer.itemPricesValidUntil;
      if (offer.businessId != branch ||
          offer.calculationMode != 'perItem' ||
          expiry == null ||
          !expiry.isAfter(now()))
        continue;
      for (final unit in offer.itemPrices) {
        final existing = prices[unit.productId];
        if (existing == null || unit.netFils < existing.unit.netFils)
          prices[unit.productId] = PricedMenuOffer(offer, unit, expiry);
      }
    }
    _branches[branch] = prices;
    _timer?.cancel();
    if (_branches.values.any((v) => v.isNotEmpty)) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        var removed = false;
        for (final prices in _branches.values) {
          final count = prices.length;
          prices.removeWhere((_, p) => !p.expiresAt.isAfter(now()));
          removed = removed || count != prices.length;
        }
        if (removed) notifyListeners();
        if (_branches.values.every((v) => v.isEmpty)) _timer?.cancel();
      });
    }
    notifyListeners();
  }

  void _checkOwner() {
    if (_owner != account()) {
      _owner = account();
      _branches.clear();
    }
  }

  PricedMenuOffer? price(
    String branch,
    String product,
    num original, {
    bool basket = false,
  }) {
    _checkOwner();
    final p = _branches[branch]?[product];
    if (p == null ||
        !p.expiresAt.isAfter(now()) ||
        (original * 1000 - p.unit.originalFils).abs() > .001)
      return null;
    if (basket &&
        (PendingOffer.current?.merchantId != branch ||
            PendingOffer.current?.offer['id'] != p.offer.discountId))
      return null;
    return p;
  }

  bool select(String branch, String product, num original) {
    final p = price(branch, product, original);
    if (p == null) return false;
    final current = PendingOffer.current;
    if (current != null &&
        current.merchantId == branch &&
        current.offer['id'] != p.offer.discountId)
      return false;
    PendingOffer.select(
      PendingOffer('', branch, {
        'source': 'merchant',
        'id': p.offer.discountId,
        'title': p.offer.title,
        'type': p.offer.type,
        'value': p.offer.value,
      }, p.offer.validTo ?? now().add(const Duration(hours: 1))),
    );
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
