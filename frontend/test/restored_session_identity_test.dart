import 'package:flutter_test/flutter_test.dart';
import '../lib/services/restored_session_identity.dart';
void main() {
  test('new phone account profile matches its live immutable identity', () => expect(restoredProfileMatchesSubject({'userId':'new','cognitoSub':'new'}, 'new','new'), isTrue));
  test('valid new token cannot restore the old deleted profile', () => expect(restoredProfileMatchesSubject({'userId':'old','cognitoSub':'old'}, 'old','new'), isFalse));
  test('legacy local ID requires the matching Cognito subject', () {
    expect(restoredProfileMatchesSubject({'userId':'legacy','cognitoSub':'new'}, 'legacy','new'), isTrue);
    expect(restoredProfileMatchesSubject({'userId':'legacy'}, 'legacy','new'), isFalse);
  });
  test('partially written profile or conflicting identity fields fail closed', () {
    expect(restoredProfileMatchesSubject({'userId':'old','cognitoSub':'new'}, 'new','new'), isFalse);
    expect(restoredProfileMatchesSubject({'userId':'new','cognitoSub':'new','sub':'old'}, 'new','new'), isFalse);
    expect(restoredProfileMatchesSubject(null, 'new','new'), isFalse);
  });
}
