import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/home_welcome_session.dart';

void main() {
  test(
    'uses authenticated display name, guest wording, never phone/email/username',
    () {
      expect(
        HomeWelcomeSession.greeting(
          signedIn: true,
          user: {'name': 'Mohammed Ali'},
        ),
        'أهلًا \u2068Mohammed\u2069، تشعر بالجوع؟',
      );
      expect(
        HomeWelcomeSession.greeting(
          signedIn: false,
          user: {'name': 'Old User'},
        ),
        'أهلًا ضيفنا الكريم، تشعر بالجوع؟',
      );
      expect(
        HomeWelcomeSession.greeting(
          signedIn: true,
          user: {'name': '07812345', 'username': 'private@example.com'},
        ),
        'أهلًا، تشعر بالجوع؟',
      );
      expect(
        HomeWelcomeSession.greeting(
          signedIn: true,
          user: {'name': '  محمد   علي '},
        ),
        'أهلًا \u2068محمد\u2069، تشعر بالجوع؟',
      );
    },
  );
  test(
    'welcome consumed by browsing does not return on rebuild or short app switch',
    () {
      final s = HomeWelcomeSession();
      expect(s.visible('u'), true);
      s.consume();
      expect(s.visible('u'), false);
      final t = DateTime(2026, 11, 1);
      s.background(t);
      s.resume(t.add(const Duration(minutes: 2)));
      expect(s.visible('u'), false);
      s.background(t);
      s.resume(t.add(const Duration(minutes: 30)));
      expect(s.visible('u'), true);
    },
  );
  test(
    'account changes reset scope without carrying previous users greeting state',
    () {
      final s = HomeWelcomeSession();
      s.visible('a');
      s.consume();
      expect(s.visible('a'), false);
      expect(s.visible('guest'), true);
      s.consume();
      expect(s.visible('b'), true);
    },
  );
}
