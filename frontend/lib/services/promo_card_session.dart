/// Dismissals live only for this app process, including background/resume and
/// home-screen recreation. A fresh app launch starts with an empty session.
class PromoCardSession {
  static final instance = PromoCardSession();
  final Set<String> _dismissedCodes = {};

  bool isDismissed(String code) => _dismissedCodes.contains(code);
  void dismiss(String code) => _dismissedCodes.add(code);
  void undo(String code) => _dismissedCodes.remove(code);
}
