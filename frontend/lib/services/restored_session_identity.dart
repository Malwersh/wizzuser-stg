/// Bind the cached profile to the immutable identity verified by Cognito.
/// Legacy profile IDs are permitted only with an explicit Cognito subject.
bool restoredProfileMatchesSubject(Map<String, dynamic>? profile, String? storedId, String liveSub) {
  if (profile == null || storedId == null || storedId.isEmpty || liveSub.isEmpty) return false;
  for (final key in ['userId', 'user_id']) {
    final id = profile[key];
    if (id is String && id.isNotEmpty && id != storedId) return false;
  }
  final bindings = ['cognitoSub', 'cognito_sub', 'sub', 'userSub']
      .map((key) => profile[key]).whereType<String>().where((value) => value.isNotEmpty).toList();
  return bindings.isEmpty ? storedId == liveSub : bindings.every((id) => id == liveSub);
}
