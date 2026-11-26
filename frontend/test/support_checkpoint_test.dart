import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:foodapp_user/services/support_conversation_checkpoint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('account backend and order checkpoints stay independent', () async {
    await SupportConversationCheckpoint.write(
      '["alice","staging","order1"]',
      'draft alice',
    );
    expect(
      await SupportConversationCheckpoint.read('["bob","staging","order1"]'),
      isNull,
    );
    expect(
      await SupportConversationCheckpoint.read(
        '["alice","production","order1"]',
      ),
      isNull,
    );
    expect(
      await SupportConversationCheckpoint.read('["alice","staging","order2"]'),
      isNull,
    );
    expect(
      await SupportConversationCheckpoint.read('["alice","staging","order1"]'),
      'draft alice',
    );
  });
  test('ordered writes retain latest edit when leaving screen', () async {
    final first = SupportConversationCheckpoint.write('draft', 'older');
    final last = SupportConversationCheckpoint.write('draft', 'latest');
    await Future.wait([first, last]);
    expect(await SupportConversationCheckpoint.read('draft'), 'latest');
  });
}
