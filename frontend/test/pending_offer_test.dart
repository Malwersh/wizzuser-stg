import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/pending_offer.dart';

void main() {
  tearDown(PendingOffer.clear);
  test('copied codes replace slideshow selections in one pending store', () {
    PendingOffer.select(
      PendingOffer('slide', 'branch', {
        'id': 'offer',
      }, DateTime.now().add(const Duration(minutes: 20))),
    );
    PendingOffer.selectCode('SAVE', null);
    expect(PendingOffer.current!.offer['code'], 'SAVE');
    expect(PendingOffer.current!.merchantId, isEmpty);
    expect(PendingOffer.current!.slideId, isEmpty);
    PendingOffer.clear();
    expect(PendingOffer.current, isNull);
  });
  test('expired codes never reach checkout', () {
    PendingOffer.selectCode(
      'OLD',
      DateTime.now().subtract(const Duration(seconds: 1)),
    );
    expect(PendingOffer.current, isNull);
  });
  test('selection expires at the earlier of campaign end or one hour', () {
    final now = DateTime.now();
    final end = now.add(const Duration(minutes: 5));
    PendingOffer.selectCode('SOON', end);
    expect(PendingOffer.current!.expiresAt, end);
    PendingOffer.selectCode('LATER', now.add(const Duration(days: 1)));
    expect(
      PendingOffer.current!.expiresAt.isBefore(
        now.add(const Duration(minutes: 61)),
      ),
      isTrue,
    );
  });
}
