import 'dart:async';
import 'dart:convert';
import '../models/platform_benefit.dart';
import 'basket_automatic_benefit.dart';
import 'platform_benefits_service.dart';
import 'pending_offer.dart';
import 'point_invoice_321.dart';
import 'browsing_location_service.dart';
import 'delivery_address_manager.dart';
import 'session_service.dart';

// Short-lived, account/address/point-scoped discovery shared across store/cart.
// The invoice preview still validates every candidate against the exact basket.
class _EarlyBenefits {
  static final _entries =
      <String, ({DateTime until, Future<List<PlatformBenefit>> value})>{};
  static Future<List<PlatformBenefit>> load(String branch) {
    final key = jsonEncode([
      SessionService.instance.currentUserId,
      DeliveryAddressManager.instance.activeAddress?.addressId,
      BrowsingLocationService.instance.selection?.toJson(),
      branch,
    ]);
    final now = DateTime.now();
    _entries.removeWhere((_, v) => !now.isBefore(v.until));
    final existing = _entries[key];
    if (existing != null) return existing.value;
    final service = PlatformBenefitsService();
    final future = service.load(branchId: branch).whenComplete(service.dispose);
    _entries[key] = (
      until: now.add(const Duration(seconds: 30)),
      value: future,
    );
    // Handle failures immediately even when the basket invoice is still loading.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_entries[key]?.value, future)) _entries.remove(key);
        },
      ),
    );
    return future;
  }
}

/// Shared preparation for store, cart and explicit removal in checkout.
/// No permanent "attempted" flag: removing a replacement can restore a still
/// eligible delivery benefit, using a fresh server-priced proposal.
class BasketPreparation {
  static final instance = BasketPreparation();
  final Future<List<PlatformBenefit>> Function(String) loadBenefits;
  final Map<String, dynamic>? Function(String, List<Map<String, dynamic>>)
  request;
  final Future<void> Function(Map<String, dynamic>) ensure;
  final Map<String, dynamic>? Function(Map<String, dynamic>) peek;
  final bool Function() signedIn;
  final String? Function() owner;
  final _running = <String, Future<void>>{};
  BasketPreparation({
    Future<List<PlatformBenefit>> Function(String)? loadBenefits,
    Map<String, dynamic>? Function(String, List<Map<String, dynamic>>)? request,
    Future<void> Function(Map<String, dynamic>)? ensure,
    Map<String, dynamic>? Function(Map<String, dynamic>)? peek,
    bool Function()? signedIn,
    String? Function()? owner,
  }) : loadBenefits = loadBenefits ?? _EarlyBenefits.load,
       request = request ?? ((b, i) => PointInvoice321.basketRequest(b, i)),
       ensure = ensure ?? ((r) => PointInvoice321.instance.ensure(r)),
       peek = peek ?? PointInvoice321.instance.peek,
       signedIn = signedIn ?? (() => SessionService.instance.isLoggedIn),
       owner = owner ?? (() => SessionService.instance.currentUserId);

  Future<void> prepare(
    String branch,
    List<Map<String, dynamic>> items, {
    required bool Function() current,
  }) async {
    if (!signedIn() || !current()) return;
    final benefits = loadBenefits(branch);
    // Attach a handler before awaiting the baseline request.
    unawaited(
      benefits.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    final initial = request(branch, items);
    if (initial == null) return;
    final point = initial['pricingPoint'];
    final scope = PendingOffer.basketScope(
      branch,
      items,
      point['latitude'],
      point['longitude'],
    );
    final existing = _running[scope];
    if (existing != null) return existing;
    final account = owner();
    bool valid() {
      final latest = request(branch, items);
      return current() &&
          account == owner() &&
          latest != null &&
          scope ==
              PendingOffer.basketScope(
                branch,
                items,
                latest['pricingPoint']['latitude'],
                latest['pricingPoint']['longitude'],
              );
    }

    late final Future<void> task;
    task = () async {
      try {
        final previous = PendingOffer.current;
        if (previous?.automaticDelivery == true &&
            !previous!.matchesBasket(
              branch,
              items,
              point['latitude'],
              point['longitude'],
            )) {
          PendingOffer.clear(dismissAutomatic: false);
        }
        final baselineRequest = request(branch, items);
        if (baselineRequest == null) return;
        await ensure(baselineRequest);
        if (!valid() ||
            PendingOffer.current != null ||
            PendingOffer.automaticDismissed(scope))
          return;
        final baseline = peek(baselineRequest);
        if (baseline == null) return;
        final choice = await selectAutomaticDeliveryBenefit(
          branch: branch,
          baseline: baseline,
          benefits: await benefits,
          current: () => valid() && PendingOffer.current == null,
          preview: (benefit) async {
            final candidate = {
              ...baselineRequest,
              'deliveryBenefitId': benefit.id,
            };
            await ensure(candidate);
            return peek(candidate);
          },
        );
        if (choice == null || !valid() || PendingOffer.current != null) return;
        PendingOffer.select(
          PendingOffer('', branch, {
            'source': 'platform',
            'id': choice.benefit.id,
            'title': choice.benefit.title,
            'automaticBasketScope': scope,
            'savingMinor': choice.savingMinor,
            'previousTotalMinor': baseline['customerTotal']['minorAmount'],
          }, choice.benefit.endAt),
        );
      } catch (_) {
        // Optional discovery must not invent savings or block a valid basket.
      }
    }().whenComplete(() {
      if (identical(_running[scope], task)) _running.remove(scope);
    });
    _running[scope] = task;
    return task;
  }
}
