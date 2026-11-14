import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/interface_layout.dart';
import 'package:foodapp_user/services/interface_layout_service.dart';

InterfaceLayout layout(String title) => InterfaceLayout.fromJson({
  'configured': true,
  'validUntil':
      DateTime.now().add(const Duration(minutes: 1)).toIso8601String(),
  'sections': [
    {'id': 'a', 'title': title, 'source': 'curated', 'limit': 6},
  ],
});
void main() {
  test(
    'force refresh replaces fresh cached template without restarting service',
    () async {
      var calls = 0;
      final service = InterfaceLayoutService(
        scopeReader: () => 'u:r',
        fetcher: (_, __, ___) async => layout('نسخة ${++calls}'),
      );
      expect(
        (await service.load('store', 'b')).sections.single.title,
        'نسخة 1',
      );
      expect(
        (await service.load('store', 'b')).sections.single.title,
        'نسخة 1',
      );
      expect(
        (await service.load('store', 'b', force: true)).sections.single.title,
        'نسخة 2',
      );
      expect(calls, 2);
    },
  );
  test('simultaneous refreshes share one in-flight request', () async {
    var calls = 0;
    final gate = Completer<InterfaceLayout>();
    final service = InterfaceLayoutService(
      scopeReader: () => 'u:r',
      fetcher: (_, __, ___) {
        calls++;
        return gate.future;
      },
    );
    final a = service.load('store', 'b', force: true),
        b = service.load('store', 'b', force: true);
    expect(calls, 1);
    gate.complete(layout('جديد'));
    await Future.wait([a, b]);
    expect(calls, 1);
  });
  test('late response after account or region change is discarded', () async {
    var scope = 'one:r';
    final gate = Completer<InterfaceLayout>();
    final service = InterfaceLayoutService(
      scopeReader: () => scope,
      fetcher: (_, __, ___) => gate.future,
    );
    final pending = service.load('store', 'b');
    scope = 'two:other';
    gate.complete(layout('خاص'));
    await expectLater(pending, throwsStateError);
  });
  test(
    'failed refresh preserves still valid previous template cache',
    () async {
      var fail = false;
      final service = InterfaceLayoutService(
        scopeReader: () => 'u:r',
        fetcher: (_, __, ___) async {
          if (fail) throw StateError('offline');
          return layout('منشور');
        },
      );
      await service.load('store', 'b');
      fail = true;
      await expectLater(
        service.load('store', 'b', force: true),
        throwsStateError,
      );
      expect((await service.load('store', 'b')).sections.single.title, 'منشور');
    },
  );
  test(
    'background prefetch never replaces the visible screen snapshot',
    () async {
      var version = 0;
      final service = InterfaceLayoutService(
        scopeReader: () => 'u:r',
        fetcher: (_, __, ___) async => layout('نسخة ${++version}'),
      );
      final visible = InterfaceScreenSession();
      visible.accept('u:r', await service.load('store', 'b'), apply: true);
      final next = await service.load('store', 'b', force: true);
      expect(visible.accept('u:r', next, apply: false), false);
      expect(visible.current('u:r')!.sections.single.title, 'نسخة 1');
      final reopened = InterfaceScreenSession();
      reopened.accept('u:r', await service.load('store', 'b'), apply: true);
      expect(reopened.current('u:r')!.sections.single.title, 'نسخة 2');
      visible.accept('u:r', next, apply: true);
      expect(visible.current('u:r')!.sections.single.title, 'نسخة 2');
    },
  );
  test(
    'cache expiration alone cannot reset visible sections to default or leak identity',
    () {
      final expired = InterfaceLayout.fromJson({
        'configured': true,
        'validUntil': '2000-01-01T00:00:00Z',
        'sections': [
          {'id': 's', 'title': 'ترتيب الزبون الحالي', 'source': 'curated'},
        ],
      });
      final session = InterfaceScreenSession();
      session.accept('one:r', expired, apply: true);
      expect(expired.fresh, false);
      expect(
        session.current('one:r')!.sections.single.title,
        'ترتيب الزبون الحالي',
      );
      expect(session.current('two:r'), null);
    },
  );
}
