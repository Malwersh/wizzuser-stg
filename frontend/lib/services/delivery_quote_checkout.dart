import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../config/api_config.dart';
import 'scoped_checkout_attempt.dart';

void validateCommercialCheckoutAmounts(Map proposal, int quotedFeeMinor) {
  const fields = [
    'customerTotal',
    'goodsGross',
    'serviceFee',
    'discount',
    'deliveryFee',
  ];
  for (final key in [
    ...fields,
    if (proposal.containsKey('driverTip')) 'driverTip',
  ]) {
    final money = proposal[key];
    if (money is! Map ||
        money['currency'] != 'IQD' ||
        money['scale'] != 1000 ||
        money['moneySchemaVersion'] != 1 ||
        money['minorAmount'] is! int ||
        money['minorAmount'] < 0 ||
        money['minorAmount'] > 9007199254740991 ||
        money['minorAmount'] % 1000 != 0) {
      throw const FormatException('INVALID_COMMERCIAL_PREVIEW');
    }
  }
  BigInt amount(String key) => BigInt.from(proposal[key]['minorAmount'] as int);
  final tip =
      proposal.containsKey('driverTip') ? amount('driverTip') : BigInt.zero;
  if (proposal['deliveryFee']['minorAmount'] != quotedFeeMinor ||
      amount('discount') > amount('goodsGross') ||
      amount('goodsGross') -
              amount('discount') +
              amount('serviceFee') +
              amount('deliveryFee') +
              tip !=
          amount('customerTotal')) {
    throw const FormatException('INCONSISTENT_COMMERCIAL_PREVIEW');
  }
}

class DeliveryQuote {
  final String id, branchId, addressId;
  final DateTime expiresAt;
  final int feeMinor;
  DeliveryQuote.fromJson(Map<String, dynamic> row)
    : id = row['quoteId'] as String,
      branchId = row['branchId'] as String,
      addressId = row['addressId'] as String,
      expiresAt = DateTime.parse(row['expiresAt'] as String),
      feeMinor = row['customerDeliveryFee']['minorAmount'] as int {
    final money = row['customerDeliveryFee'];
    if (row['kind'] != 'DELIVERY_FEE_ONLY' ||
        row['schemaVersion'] != 1 ||
        money['currency'] != 'IQD' ||
        money['scale'] != 1000 ||
        money['moneySchemaVersion'] != 1 ||
        feeMinor < 0 ||
        feeMinor > 9007199254740991) {
      throw const FormatException('INVALID_QUOTE');
    }
  }
  double get fee => feeMinor / 1000;
}

/// A saved confirmation is immutable until the server establishes its outcome.
/// Storage is scoped by account; account changes invalidate all in-flight UI results.
class DeliveryQuoteCheckout extends ChangeNotifier {
  final String? Function() account;
  final String? Function() token;
  final http.Client client;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final DateTime Function() now;
  final ScopedCheckoutAttempt? scopedAttempt;
  DeliveryQuote? quote;
  String? error;
  bool busy = false, ready = false;
  Map<String, dynamic>? _pending;
  String? _owner, _quoteAttempt, _scope;
  DateTime? _quoteRetryAt;
  int _generation = 0;
  bool _disposed = false;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  static final Set<String> _confirmingAccounts = {};
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'wizz_quoted_checkout',
    ),
    iOptions: IOSOptions(
      accountName: 'wizz_quoted_checkout',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static Future<void> forgetAccount(String owner) =>
      _storage.delete(key: 'quoted_checkout_v1_${Uri.encodeComponent(owner)}');
  DeliveryQuoteCheckout({
    required this.account,
    required this.token,
    http.Client? client,
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<void> Function(String)? remove,
    DateTime Function()? now,
    ScopedCheckoutAttempt? scopedAttempt,
  }) : scopedAttempt = scopedAttempt ?? ScopedCheckoutAttempt.fromBuild(),
       client = client ?? http.Client(),
       read = read ?? ((key) => _storage.read(key: key)),
       write =
           write ?? ((key, value) => _storage.write(key: key, value: value)),
       remove = remove ?? ((key) => _storage.delete(key: key)),
       now = now ?? DateTime.now;
  String _key(String user) => 'quoted_checkout_v1_${Uri.encodeComponent(user)}';
  bool get pending => _pending != null;
  bool get valid =>
      ready &&
      _owner == account() &&
      quote != null &&
      now().isBefore(quote!.expiresAt);
  bool matches(String branch, String address) =>
      valid && quote!.branchId == branch && quote!.addressId == address;
  Map<String, String> _headers(String owner) {
    final access = token();
    if (account() != owner || access == null || access.isEmpty) {
      throw StateError('يرجى تسجيل الدخول');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $access',
      'X-Customer-Id': owner,
    };
  }

  void _check(String owner, int generation) {
    if (account() != owner || _generation != generation) {
      throw StateError('تغير الحساب أو عنوان التوصيل؛ أعد المحاولة');
    }
  }

  Future<void> restore() async {
    final owner = account();
    final generation = ++_generation;
    if (_owner != owner) _quoteRetryAt = null;
    _owner = owner;
    quote = null;
    _pending = null;
    ready = false;
    if (owner == null || owner == 'guest') {
      error = 'سجل الدخول للحصول على سعر التوصيل';
      _emit();
      return;
    }
    try {
      final stored = await read(_key(owner));
      _check(owner, generation);
      if (stored != null) {
        final saved = Map<String, dynamic>.from(jsonDecode(stored));
        if (saved['userId'] != owner ||
            saved['quoteId'] is! String ||
            saved['idempotencyKey'] is! String) {
          throw const FormatException('INVALID_PENDING_CONFIRMATION');
        }
        _pending = saved;
      }
      ready = true;
      error = null;
    } catch (_) {
      error = 'تعذر استعادة محاولة التأكيد؛ أعد فتح الصفحة';
    }
    _emit();
  }

  Future<void> load(String branch, String address, {bool renew = false}) async {
    if (!ready || busy || pending) return;
    try {
      scopedAttempt?.check(_owner!, branch);
    } on StateError {
      quote = null;
      error = 'هذا الحساب أو النشاط خارج عينة الاختبار المعتمدة';
      _emit();
      return;
    }
    if (_quoteRetryAt != null && now().isBefore(_quoteRetryAt!)) {
      final seconds =
          (_quoteRetryAt!.difference(now()).inMilliseconds / 1000).ceil();
      error = 'طلبات تسعير كثيرة؛ أعد المحاولة بعد $seconds ثانية';
      _emit();
      return;
    }
    final owner = _owner!;
    final generation = ++_generation;
    final scope = '$branch/$address';
    if (renew || _scope != scope) _quoteAttempt = null;
    _scope = scope;
    _quoteAttempt ??= const Uuid().v4();
    quote = null;
    error = null;
    busy = true;
    _emit();
    try {
      final response = await client
          .post(
            Uri.parse(ApiConfig.buildUrl('/delivery-quotes')),
            headers: _headers(owner),
            body: jsonEncode({
              'branchId': branch,
              'addressId': address,
              'requestId': _quoteAttempt,
            }),
          )
          .timeout(ApiConfig.apiTimeout);
      _check(owner, generation);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 429 && data['code'] == 'QUOTE_RATE_LIMITED') {
        final requested = data['retryAfterSeconds'];
        final seconds =
            requested is int && requested >= 1 && requested <= 60
                ? requested
                : 60;
        _quoteRetryAt = now().add(Duration(seconds: seconds));
        error = 'طلبات تسعير كثيرة؛ أعد المحاولة بعد $seconds ثانية';
        return;
      }
      if (response.statusCode != 200 || data['success'] != true) {
        if ([
          'QUOTE_EXPIRED',
          'QUOTE_INVALIDATED',
          'QUOTE_CONSUMED',
        ].contains(data['code'])) {
          _quoteAttempt = null;
        }
        throw StateError('تعذر تسعير التوصيل؛ حدّث السعر للمحاولة مجددًا');
      }
      final loaded = DeliveryQuote.fromJson(
        Map<String, dynamic>.from(data['quote']),
      );
      if (loaded.branchId != branch ||
          loaded.addressId != address ||
          !now().isBefore(loaded.expiresAt)) {
        _quoteAttempt = null;
        throw StateError('انتهى عرض التوصيل؛ حدّث السعر');
      }
      _quoteRetryAt = null;
      quote = loaded;
    } catch (_) {
      if (account() == owner && generation == _generation) {
        error = 'تعذر تحميل سعر التوصيل؛ أعد المحاولة';
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        _emit();
      }
    }
  }

  void invalidate() {
    if (pending) return;
    ++_generation;
    quote = null;
    _scope = null;
    _quoteAttempt = null;
    busy = false;
    _emit();
  }

  Future<http.Response> confirm(
    Map<String, dynamic>? content, {
    Future<bool> Function(Map<String, dynamic>)? approveCommercial,
  }) async {
    if (busy || !ready || _owner == null) {
      throw StateError('تعذر تأكيد الطلب الآن');
    }
    final owner = _owner!, generation = _generation;
    if (!_confirmingAccounts.add(owner)) {
      throw StateError('توجد محاولة تأكيد قيد التنفيذ');
    }
    busy = true;
    _emit();
    try {
      if (_pending == null) {
        final existing = await read(_key(owner));
        _check(owner, generation);
        if (existing != null) {
          _pending = Map<String, dynamic>.from(jsonDecode(existing));
          throw StateError(
            'توجد محاولة سابقة؛ اضغط متابعة التأكيد لاستعادة نتيجتها',
          );
        }
        if (content == null ||
            !matches(content['storeId'], content['deliveryAddress']['id']) ||
            content['userId'] != owner) {
          throw StateError('انتهى عرض التوصيل؛ حدّث السعر ثم أكد مجددًا');
        }
        scopedAttempt?.check(owner, content['storeId']);
        final saved =
            jsonDecode(
                  jsonEncode({
                    ...content,
                    'quoteId': quote!.id,
                    'idempotencyKey':
                        scopedAttempt?.requestId ?? const Uuid().v4(),
                    'deliveryFee': quote!.fee,
                  }),
                )
                as Map<String, dynamic>;
        if (ApiConfig.commercialPricingEnabled) {
          if (approveCommercial == null) {
            throw StateError('يلزم تأكيد إجمالي الطلب');
          }
          final previewResponse = await client
              .post(
                Uri.parse(
                  ApiConfig.buildUrl(
                    '${ApiConfig.ordersEndpoint}/commercial-preview',
                  ),
                ),
                headers: _headers(owner),
                body: jsonEncode({...saved, 'action': 'preview_commercial'}),
              )
              .timeout(ApiConfig.apiTimeout);
          _check(owner, generation);
          final data = jsonDecode(previewResponse.body);
          final proposal = data['commercial'];
          if (previewResponse.statusCode != 200 ||
              data['success'] != true ||
              proposal is! Map ||
              proposal['schemaVersion'] != 1 ||
              proposal['digest'] is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(proposal['digest']) ||
              proposal['quoteId'] != saved['quoteId'] ||
              proposal['requestId'] != saved['idempotencyKey'] ||
              proposal['expiresAt'] is! String ||
              DateTime.tryParse(proposal['expiresAt']) == null ||
              DateTime.parse(proposal['expiresAt']).isAfter(quote!.expiresAt) ||
              !now().isBefore(DateTime.parse(proposal['expiresAt']))) {
            throw StateError(
              'تعذر إعداد السعر التجاري؛ حدّث السعر وأعد المحاولة',
            );
          }
          validateCommercialCheckoutAmounts(proposal, quote!.feeMinor);
          final accepted = await approveCommercial(
            Map<String, dynamic>.from(proposal),
          );
          _check(owner, generation);
          if (!accepted) throw StateError('أُلغي تأكيد السعر');
          if (!valid ||
              !now().isBefore(DateTime.parse(proposal['expiresAt']))) {
            throw StateError('انتهى السعر؛ حدّثه وأكد مجددًا');
          }
          saved['commercialConsent'] = {
            'digest': proposal['digest'],
            'customerTotalMinor': proposal['customerTotal']['minorAmount'],
          };
        }
        await write(
          _key(owner),
          jsonEncode(saved),
        ); // Persist before sending any order request.
        _check(owner, generation);
        _pending = saved;
      }
      if (_pending!['userId'] != owner) {
        throw const FormatException('INVALID_PENDING_ACCOUNT');
      }
      final response = await client
          .post(
            Uri.parse(ApiConfig.buildUrl(ApiConfig.ordersEndpoint)),
            headers: _headers(owner),
            body: jsonEncode(_pending),
          )
          .timeout(ApiConfig.apiTimeout);
      _check(owner, generation);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success =
          [200, 201].contains(response.statusCode) && data['success'] == true;
      if (success) {
        final order = data['order'];
        if (order is! Map ||
            (order['orderId'] ?? order['id']) is! String ||
            ((order['orderId'] ?? order['id']) as String).isEmpty ||
            order['userId'] != owner ||
            order['deliveryQuote'] is! Map ||
            order['deliveryQuote']['quoteId'] != _pending!['quoteId'] ||
            order['deliveryQuote']['requestId'] !=
                _pending!['idempotencyKey']) {
          throw const FormatException('INVALID_CONFIRMATION_RESPONSE');
        }
      }
      // Only explicit pre-commit failures release the attempt. Unknown failures retain it.
      final activeConflict =
          response.statusCode == 409 &&
          data['success'] == false &&
          data['activeOrder'] is Map;
      final definitive =
          activeConflict ||
          response.statusCode < 500 &&
              [
                'QUOTE_EXPIRED',
                'QUOTE_INVALIDATED',
                'QUOTE_UNAVAILABLE',
                'QUOTE_CONSUMED',
                'QUOTE_REQUEST_CONFLICT',
                'INVALID_QUOTE_ORDER',
                'QUOTE_NOT_ENABLED',
                'CART_PRICE_CHANGED',
                'DISCOUNT_PREVIEW_CHANGED',
                'DISCOUNT_UNAVAILABLE',
                'COMMERCIAL_DISCOUNT_UNSUPPORTED',
                'FUNDING_WALLET_PRECISION_UNSUPPORTED',
                'DISCOUNT_FUNDING_UNAUTHORIZED',
                'COMMERCIAL_ORDER_UNSUPPORTED',
                'COMMERCIAL_CONSENT_REQUIRED',
                'COMMERCIAL_QUOTE_EXPIRED',
                'DISCOUNT_FUNDING_UNAVAILABLE',
                'COMMERCIAL_SOURCE_UNAVAILABLE',
              ].contains(data['code']);
      if (success || definitive) {
        await remove(_key(owner));
        _check(owner, generation);
        _pending = null;
        quote = null;
        _quoteAttempt = null;
      }
      return response;
    } finally {
      _confirmingAccounts.remove(owner);
      busy = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    client.close();
    super.dispose();
  }
}
