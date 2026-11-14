import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/screens/map_screen_new.dart';

BusinessModel shop(
  String id, {
  double rating = 0,
  bool busy = false,
  double? lat = 32,
}) => BusinessModel(
  id: id,
  businessName: id,
  address: '',
  businessPhotoUrl: '',
  businessType: 'restaurant',
  rating: rating,
  latitude: lat,
  longitude: 44,
  metadata: {
    'isBusy': busy,
    'reviewCount': rating > 0 ? 2 : 0,
    'isAvailableNow': !busy,
    'availabilityCheckedAt': DateTime.now().toUtc().toIso8601String(),
  },
);
void main() {
  test(
    'open filter requires fresh authoritative availability including working hours',
    () {
      final now = DateTime.utc(2026, 11, 9, 12);
      BusinessModel row(Map<String, dynamic> metadata) => BusinessModel(
        id: 'b',
        businessName: 'b',
        address: '',
        businessPhotoUrl: '',
        businessType: 'restaurant',
        metadata: metadata,
      );
      expect(
        explorationAvailable(
          row({
            'isOnline': true,
            'acceptingOrders': true,
            'isAvailableNow': false,
            'availabilityCheckedAt': now.toIso8601String(),
          }),
          now: now,
        ),
        false,
      );
      expect(
        explorationAvailable(
          row({
            'isAvailableNow': true,
            'availabilityCheckedAt': now.toIso8601String(),
          }),
          now: now,
        ),
        true,
      );
      expect(
        explorationAvailable(
          row({
            'isAvailableNow': true,
            'availabilityCheckedAt':
                now.subtract(const Duration(minutes: 3)).toIso8601String(),
          }),
          now: now,
        ),
        false,
      );
      expect(explorationAvailable(row({'isOnline': true}), now: now), false);
    },
  );
  test('rating requires actual reviews even when a numeric average exists', () {
    final b = BusinessModel(
      id: 'b',
      businessName: 'b',
      address: '',
      businessPhotoUrl: '',
      businessType: 'restaurant',
      rating: 4.8,
    );
    expect(explorationFilter([b], ratedOnly: true), isEmpty);
  });

  test('combined filters retain only matching available rated stores', () {
    final rows = [
      shop('Pizza', rating: 4.5),
      shop('Pizza busy', rating: 5, busy: true),
      shop('Burger', rating: 4.8),
      shop('Pizza new'),
    ];
    expect(
      explorationFilter(
        rows,
        query: ' pizza ',
        openOnly: true,
        ratedOnly: true,
      ).map((b) => b.id),
      ['Pizza'],
    );
    expect(rows.length, 4);
  });
  test('missing and invalid ratings are not four star stores', () {
    expect(
      explorationFilter([
        shop('new'),
        shop('invalid', rating: 6),
      ], ratedOnly: true),
      isEmpty,
    );
  });
  test('invalid map coordinates are excluded without hiding list data', () {
    final rows = [
      shop('valid'),
      shop('missing', lat: null),
      shop('bad', lat: double.nan),
      shop('outside', lat: 91),
    ];
    expect(rows.where(explorationHasPoint).map((b) => b.id), ['valid']);
    expect(explorationFilter(rows).length, 4);
  });
  test('updated catalog is filtered with the same user choices', () {
    expect(
      explorationFilter(
        [shop('Pizza', busy: true)],
        query: 'pizza',
        openOnly: true,
      ),
      isEmpty,
    );
    expect(
      explorationFilter([shop('Pizza')], query: 'pizza', openOnly: true).length,
      1,
    );
  });
}
