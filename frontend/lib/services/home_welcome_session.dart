/// Per-process browsing session; stores no names and performs no network/storage writes.
class HomeWelcomeSession {
  static final instance = HomeWelcomeSession();
  static const returnAfter = Duration(minutes: 30);
  String? _identity;
  DateTime? _backgroundAt;
  bool _consumed = false;

  bool visible(String identity) {
    if (_identity != identity) {
      _identity = identity;
      _consumed = false;
    }
    return !_consumed;
  }

  void consume() => _consumed = true;
  void background(DateTime now) => _backgroundAt ??= now;
  void resume(DateTime now) {
    if (_backgroundAt != null && now.difference(_backgroundAt!) >= returnAfter)
      _consumed = false;
    _backgroundAt = null;
  }

  static String greeting({
    required bool signedIn,
    Map<String, dynamic>? user,
    Map<String, dynamic> settings = const {},
  }) {
    if (!signedIn)
      return settings['guest'] as String? ?? 'أهلًا ضيفنا الكريم، تشعر بالجوع؟';
    for (final key in ['given_name', 'firstName', 'name', 'fullName']) {
      final raw = user?[key];
      if (raw is! String) continue;
      final name =
          raw
              .replaceAll(
                RegExp(r'[\x00-\x1F\x7F\u202A-\u202E\u2066-\u2069]'),
                '',
              )
              .trim()
              .split(RegExp(r'\s+'))
              .first;
      if (name.isEmpty ||
          name.contains('@') ||
          RegExp(r'[0-9٠-٩]').hasMatch(name) ||
          !RegExp(r'[A-Za-z\u0621-\u064A]').hasMatch(name) ||
          ['مستخدم', 'ضيف', 'User', 'Guest'].contains(name))
        continue;
      return (settings['signedIn'] as String? ?? 'أهلًا {name}، تشعر بالجوع؟')
          .replaceAll('{name}', '\u2068$name\u2069');
    }
    return settings['anonymous'] as String? ?? 'أهلًا، تشعر بالجوع؟';
  }
}
