import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/home_layout.dart';

void main() {
  Map<String, dynamic> section({String source = 'curated', int limit = 6}) => {
    'id': 'one',
    'title': 'مختارات ويز',
    'source': source,
    'merchantIds': ['m2', 'm1'],
    'limit': limit,
    'startAt': '2026-10-01T00:00:00Z',
    'endAt': '2026-11-01T00:00:00Z',
  };
  test(
    'published layout preserves ordered sections and curated merchant order',
    () {
      final layout = HomeLayout.fromJson({
        'configured': true,
        'sections': [
          section(),
          {...section(source: 'rating'), 'id': 'two'},
        ],
      });
      expect(layout.configured, isTrue);
      expect(layout.sections.map((s) => s.source), ['curated', 'rating']);
      expect(layout.sections.first.merchantIds, ['m2', 'm1']);
    },
  );
  test(
    'scheduled section respects exact beginning and end while feed is cached',
    () {
      final s = HomeSection.fromJson(section());
      expect(s.activeAt(DateTime.parse('2026-09-30T23:59:59Z')), isFalse);
      expect(s.activeAt(DateTime.parse('2026-10-01T00:00:00Z')), isTrue);
      expect(s.activeAt(DateTime.parse('2026-11-01T00:00:00Z')), isFalse);
    },
  );
  test(
    'unconfigured layout and intentionally empty published layout differ',
    () {
      expect(HomeLayout.fromJson({'configured': false}).configured, isFalse);
      final empty = HomeLayout.fromJson({'configured': true, 'sections': []});
      expect(empty.configured, isTrue);
      expect(empty.sections, isEmpty);
    },
  );
  test('unsupported source and unbounded section are rejected', () {
    expect(
      () => HomeSection.fromJson(section(source: 'fake-popular')),
      throwsFormatException,
    );
    expect(
      () => HomeSection.fromJson(section(limit: 100)),
      throwsFormatException,
    );
  });
}
