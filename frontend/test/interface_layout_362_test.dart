import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/interface_layout.dart';
import 'package:foodapp_user/models/product_model.dart';

InterfaceSection section(
  String source, {
  Map<String, dynamic> patch = const {},
}) => InterfaceSection.fromJson({
  'id': 's',
  'title': 'قسم',
  'source': source,
  'limit': 12,
  ...patch,
});
ProductModel product(
  String id, {
  String branch = 'b',
  String category = 'c',
  double price = 3000,
  bool available = true,
}) => ProductModel(
  id: id,
  businessId: branch,
  categoryId: category,
  name: id,
  description: '',
  imageUrl: '',
  price: price,
  isAvailable: available,
  createdAt: DateTime(2026),
);
void main() {
  test(
    'previous orders resolve current catalog only, with current prices and branch-provided input',
    () {
      final all = [product('new'), product('p', price: 5000)];
      final result = selectInterfaceProducts(
        section('lastOrder'),
        all,
        discounted: {},
        last: ['deleted', 'p'],
      );
      expect(result.map((p) => p.id), ['p']);
      expect(result.single.price, 5000);
    },
  );
  test(
    'similar excludes current product, complementary selectors never invent recommendations',
    () {
      final a = product('a'),
          b = product('b'),
          c = product('c', category: 'other');
      expect(
        selectInterfaceProducts(
          section('similar'),
          [a, b, c],
          discounted: {},
          current: a,
        ).map((p) => p.id),
        ['b'],
      );
      expect(
        selectInterfaceProducts(
          section(
            'complementary',
            patch: {
              'categoryIds': ['other'],
            },
          ),
          [a, b, c],
          discounted: {},
          current: a,
        ).map((p) => p.id),
        ['c'],
      );
    },
  );
  test(
    'discount and popularity sources require real eligibility/count evidence',
    () {
      final all = [product('a'), product('b')];
      expect(
        selectInterfaceProducts(
          section('discounted'),
          all,
          discounted: {'b'},
        ).single.id,
        'b',
      );
      expect(
        selectInterfaceProducts(
          section('bestsellers'),
          all,
          discounted: {},
          counts: {},
        ),
        isEmpty,
      );
      expect(
        selectInterfaceProducts(
          section('bestsellers'),
          all,
          discounted: {},
          counts: {'a': 2, 'b': 8},
        ).map((p) => p.id),
        ['b', 'a'],
      );
    },
  );
  test(
    'dedup, availability and price filters combine; full catalog remains untouched',
    () {
      final all = [
        product('a'),
        product('b', available: false),
        product('c', price: 1000),
      ];
      final result = selectInterfaceProducts(
        section(
          'curated',
          patch: {
            'productIds': ['a', 'b', 'c'],
            'deduplicate': true,
            'filters': {'availableOnly': true, 'minPrice': 2000},
          },
        ),
        all,
        discounted: {},
        seen: {'a'},
      );
      expect(result, isEmpty);
      expect(all.length, 3);
    },
  );
  test('time/audience boundaries and bounded parse', () {
    final now = DateTime(2026);
    expect(
      section('featured', patch: {'audience': 'signedIn'}).visible(false, now),
      false,
    );
    expect(
      section(
        'featured',
        patch: {'endAt': now.toIso8601String()},
      ).visible(true, now),
      false,
    );
    expect(
      () => section('featured', patch: {'layout': 'javascript'}),
      throwsFormatException,
    );
  });
}
