import 'session_service.dart';

class PendingOffer {
  static PendingOffer? _value;
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
      clear();
    return _value;
  }

  static void select(PendingOffer value) => _value = value;
  static void selectCode(String code, DateTime? endAt) {
    final expiry = DateTime.now().add(const Duration(hours: 1));
    select(
      PendingOffer('', '', {
        'source': 'platform',
        'code': code,
      }, endAt != null && endAt.isBefore(expiry) ? endAt : expiry),
    );
  }

  static void clear() => _value = null;
}
