import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/home_layout.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/models/browsing_location.dart';

void main() {
  final now = DateTime.parse('2026-10-30T12:00:00Z');
  BusinessModel business(
    String id, {
    double lat = 32,
    double rating = 4.5,
    bool closed = false,
  }) => BusinessModel(
    id: id,
    businessName: id,
    address: '',
    businessPhotoUrl: '',
    businessType: 'restaurant',
    latitude: lat,
    longitude: 44,
    rating: rating,
    metadata: {
      'reviewCount': 10,
      'created_at': '2026-10-25T00:00:00Z',
      'isClosed': closed,
    },
  );
  HomeSection section({
    String ranking = 'default',
    String source = 'region',
    Map<String, dynamic> filters = const {},
    List<String> ids = const [],
  }) => HomeSection.fromJson({
    'id': 's',
    'title': 'قسم',
    'source': source,
    'ranking': ranking,
    'filters': filters,
    'merchantIds': ids,
    'limit': 6,
  });
  final facts = <String, dynamic>{
    'catalog': {
      'profiles': {
        'a': {
          'cuisineIds': ['pizza'],
          'brandId': 'brand',
        },
        'b': {
          'cuisineIds': ['chicken'],
          'brandId': null,
        },
      },
    },
    'stats': {
      'expiresAt': '2026-10-30T13:00:00Z',
      'counts': {
        'a': {'days7': 2, 'days30': 3},
        'b': {'days7': 1, 'days30': 9},
      },
    },
    'offers': {
      'expiresAt': '2026-10-30T12:01:00Z',
      'merchantIds': ['a'],
      'allMerchants': false,
    },
  };
  List<String> select(
    HomeSection s, {
    Map<String, dynamic>? data,
    List<BusinessModel>? rows,
  }) =>
      selectHomeBusinesses(
        s,
        rows ?? [business('a'), business('b', lat: 32.1)],
        facts: data ?? facts,
        isFavorite: (id) => id == 'b',
        point: BrowsingLocation(
          regionId: 'r',
          regionName: 'منطقة',
          latitude: 32,
          longitude: 44,
          source: 'gps',
        ),
        now: now,
      ).map((b) => b.id).toList();
  test(
    'cuisine, brand and eligible offer filters combine without title matching',
    () {
      expect(
        select(
          section(
            filters: {
              'cuisineIds': ['pizza'],
              'brandIds': ['brand'],
              'offersOnly': true,
            },
          ),
        ),
        ['a'],
      );
      expect(
        select(
          section(
            filters: {
              'cuisineIds': ['unknown'],
            },
          ),
        ),
        isEmpty,
      );
    },
  );
  test(
    'distance ranking uses point and open-now filter excludes closed businesses',
    () {
      expect(select(section(ranking: 'distance')), ['a', 'b']);
      expect(
        select(
          section(filters: {'openNow': true}),
          rows: [business('a', closed: true), business('b')],
        ),
        ['b'],
      );
    },
  );
  test(
    'saved completed-order counts determine popularity and stale metrics hide results',
    () {
      expect(select(section(ranking: 'orders')), ['b', 'a']);
      expect(
        select(
          section(ranking: 'orders'),
          data: {
            ...facts,
            'stats': {'expiresAt': '2026-10-29T00:00:00Z', 'counts': {}},
          },
        ),
        isEmpty,
      );
    },
  );
  test('expired offer facts cannot keep a restaurant in offers section', () {
    expect(
      select(
        section(filters: {'offersOnly': true}),
        data: {
          ...facts,
          'offers': {'expiresAt': '2026-10-29T00:00:00Z', 'allMerchants': true},
        },
      ),
      isEmpty,
    );
  });
  test(
    'manual choices preserve configured order and cannot add unauthorized restaurants',
    () {
      expect(
        select(
          section(
            source: 'curated',
            ranking: 'manual',
            ids: ['b', 'missing', 'a'],
          ),
        ),
        ['b', 'a'],
      );
    },
  );
  test('favorites filter uses current account favorites only', () {
    expect(select(section(source: 'favorites')), ['b']);
  });
}
