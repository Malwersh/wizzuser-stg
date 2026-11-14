import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'session_service.dart';
import 'discount_item_policy.dart';

class PendingOffer {
  static PendingOffer? _value;
  static final revision = ValueNotifier<int>(0);
  static final _dismissedAutomatic = <String>{};
  static String basketScope(
    String branch,
    List<Map<String, dynamic>> items,
    Object? lat,
    Object? lng,
  ) => jsonEncode(
    _canonical([
      SessionService.instance.currentUserId,
      branch,
      items
          .map(
            (item) => {
              'id': item['id'],
              'price': item['price']?.toString(),
              'quantity': item['quantity'],
              ...discountSelectionFields(item),
            },
          )
          .toList(),
      lat,
      lng,
    ]),
  );
  static dynamic _canonical(dynamic value) =>
      value is Map
          ? {
            for (final key in (value.keys.cast<String>().toList()..sort()))
              key: _canonical(value[key]),
          }
          : value is List
          ? value.map(_canonical).toList()
          : value is num && value.isFinite && value == value.truncateToDouble()
          ? value.toInt()
          : value;
  bool get automaticDelivery =>
      offer['automaticBasketScope'] is String && offer['source'] == 'platform';
  bool get deliverySelection =>
      automaticDelivery || offer['deliverySelection'] == true;
  static bool automaticDismissed(String scope) =>
      _dismissedAutomatic.contains(scope);
  bool matchesBasket(
    String branch,
    List<Map<String, dynamic>> items,
    Object? lat,
    Object? lng,
  ) =>
      offer['automaticBasketScope'] == null ||
      offer['automaticBasketScope'] == basketScope(branch, items, lat, lng);
  final String slideId, merchantId, account;
  final Map<String, dynamic> offer;
  final DateTime expiresAt;
  PendingOffer(this.slideId, this.merchantId, this.offer, this.expiresAt)
    : account = SessionService.instance.currentUserId ?? 'guest';
  static PendingOffer? get current {
    final value = _value;
    if (value != null &&
        (value.account != (SessionService.instance.currentUserId ?? 'guest') ||
            !value.expiresAt.isAfter(DateTime.now())))
      clear(notify: false);
    return _value;
  }

  static void select(PendingOffer value) {
    _value = value;
    revision.value++;
  }

  static void selectCode(
    String code,
    DateTime? endAt, {
    String? deliveryBenefitId,
  }) {
    final expiry = DateTime.now().add(const Duration(hours: 1));
    select(
      PendingOffer('', '', {
        'source': 'platform',
        'code': code,
        if (deliveryBenefitId != null) 'deliveryBenefitId': deliveryBenefitId,
      }, endAt != null && endAt.isBefore(expiry) ? endAt : expiry),
    );
  }

  static void clear({bool notify = true, bool dismissAutomatic = true}) {
    final scope = _value?.offer['automaticBasketScope'];
    if (dismissAutomatic && scope is String) {
      if (_dismissedAutomatic.length >= 30)
        _dismissedAutomatic.remove(_dismissedAutomatic.first);
      _dismissedAutomatic.add(scope);
    }
    _value = null;
    if (notify) revision.value++;
  }
}
