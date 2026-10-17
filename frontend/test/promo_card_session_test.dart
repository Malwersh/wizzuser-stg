import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/services/promo_card_session.dart';

void main() {
  test('dismissal survives refresh and home recreation within the same process', () {
    final firstHome = PromoCardSession.instance;
    firstHome.dismiss('SESSION_OFFER');
    final rebuiltHome = PromoCardSession.instance;
    expect(rebuiltHome.isDismissed('SESSION_OFFER'), isTrue);
    expect(rebuiltHome.isDismissed('NEW_OFFER'), isFalse);
    rebuiltHome.undo('SESSION_OFFER');
  });

  test('a new app session ignores legacy permanent dismissals', () async {
    SharedPreferences.setMockInitialValues({'dismissed_promo_ids': ['ERE1']});
    final oldSession = PromoCardSession()..dismiss('ERE1');
    expect(oldSession.isDismissed('ERE1'), isTrue);
    final restartedSession = PromoCardSession();
    expect(restartedSession.isDismissed('ERE1'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('dismissed_promo_ids'), ['ERE1']);
  });

  test('Undo makes only the selected offer eligible for the next feed refresh', () {
    final session = PromoCardSession()..dismiss('A')..dismiss('B');
    session.undo('A');
    expect(session.isDismissed('A'), isFalse);
    expect(session.isDismissed('B'), isTrue);
  });
}
