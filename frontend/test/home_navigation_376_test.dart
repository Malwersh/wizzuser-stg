import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/models/home_layout.dart';
import 'package:foodapp_user/models/home_navigation.dart';
import 'package:foodapp_user/widgets/discovery/home_discovery_header.dart';

void main() {
  test(
    'legacy activity aliases match canonical selectors without overriding explicit IDs',
    () {
      final legacy = BusinessModel(
        id: 'b',
        businessName: 'مطعم',
        address: '',
        businessPhotoUrl: '',
        businessType: 'restaurant',
      );
      expect(canonicalHomeActivity(legacy), 'RESTAURANT');
      expect(
        canonicalHomeActivity(
          BusinessModel(
            id: 'b',
            businessName: 'مطعم',
            address: '',
            businessPhotoUrl: '',
            businessType: 'restaurant',
            businessTypeId: 'CAFE',
          ),
        ),
        'CAFE',
      );
    },
  );

  BusinessModel business(String id, String type) => BusinessModel(
    id: id,
    businessName: 'بيتزا صحية',
    address: '',
    businessPhotoUrl: '',
    businessType: type,
    latitude: 32,
    longitude: 44,
  );
  HomeNavigationItem chip(String kind, String? value) =>
      HomeNavigationItem.fromJson({
        'id': 'custom',
        'label': 'اختيار الإدارة',
        'kind': kind,
        'value': value,
        'icon': 'pizza',
      });
  const facts = {
    'catalog': {
      'profiles': {
        'b': {
          'cuisineIds': ['pizza', 'healthy'],
          'brandId': 'chain',
        },
      },
    },
  };
  test(
    'classification can match multiple tags, independent of activity and never inferred from merchant name',
    () {
      final b = business('b', 'restaurant'),
          unclassified = business('other', 'restaurant');
      expect(chip('cuisine', 'pizza').matches(b, facts), true);
      expect(chip('cuisine', 'healthy').matches(b, facts), true);
      expect(chip('cuisine', 'pizza').matches(unclassified, facts), false);
      expect(chip('brand', 'chain').matches(b, facts), true);
      expect(chip('brand', 'chain').matches(unclassified, facts), false);
      expect(chip('activity', 'restaurant').matches(b, facts), true);
      expect(chip('activity', 'grocery').matches(b, facts), false);
      expect(chip('all', null).matches(unclassified, facts), true);
    },
  );
  test(
    'canonical activity and published product classifications survive parsing and copies',
    () {
      final b = BusinessModel.fromJson({
        'businessId': 'b',
        'businessName': 'مطعم',
        'businessType': 'restaurant',
        'businessTypeId': 'PIZZERIA',
        'publishedCuisineIds': ['pizza'],
      });
      expect(chip('activity', 'PIZZERIA').matches(b, {}), true);
      expect(chip('activity', 'OTHER').matches(b, {}), false);
      expect(chip('cuisine', 'pizza').matches(b, {}), true);
      expect(
        chip(
          'cuisine',
          'pizza',
        ).matches(b.copyWith(businessName: 'اسم جديد'), {}),
        true,
      );
      expect(BusinessModel.fromJson(b.toJson()).businessTypeId, 'PIZZERIA');
    },
  );
  test(
    'older publications retain legacy strip; explicit disabled navigation remains disabled',
    () {
      expect(
        HomeLayout.fromJson({'configured': true, 'sections': []}).navigation,
        isNull,
      );
      expect(
        HomeLayout.fromJson({
          'configured': true,
          'sections': [],
          'navigation': {'enabled': false, 'items': []},
        }).navigation!.enabled,
        false,
      );
      expect(() => chip('unsupported', 'pizza'), throwsFormatException);
    },
  );
  testWidgets(
    'published labels order and selection are passed unchanged to circular category controls',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: HomeTypeCategories(
                categories: const [
                  HomeTypeCategory('all', 'الكل', 'assets/icons/cat_rest.png'),
                  HomeTypeCategory(
                    'season',
                    'فطورك هنا',
                    'assets/icons/cat_break.png',
                  ),
                ],
                selected: 'all',
                onChanged: (id) => selected = id,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('فطورك هنا'));
      expect(selected, 'season');
      expect(tester.takeException(), isNull);
    },
  );
}
