import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/dish.dart';

void main() {
  test('branch unavailable choices are excluded from selectable options', () {
    final groups=OptionGroup.listFromAddons([{'id':'sides','title':'Sides','required':false,'maxSelections':1,'options':[
      {'id':'salad','name':'Salad','extraPrice':250,'isAvailable':true},
      {'id':'rice','name':'Rice','extraPrice':500,'isAvailable':false}
    ]}]);
    expect(groups.single.options.map((o)=>o.id).toList(),['salad']);
  });

  group('OptionGroup.listFromAddons', () {
    test('returns empty list for null input', () {
      expect(OptionGroup.listFromAddons(null), isEmpty);
    });

    test('returns empty list for empty list input', () {
      expect(OptionGroup.listFromAddons(const []), isEmpty);
    });

    test('returns empty list for unrecognized shapes', () {
      expect(OptionGroup.listFromAddons(42), isEmpty);
      expect(OptionGroup.listFromAddons('addon'), isEmpty);
      expect(OptionGroup.listFromAddons(const {'foo': 'bar'}), isEmpty);
    });

    test('parses grouped addons with canonical keys', () {
      final groups = OptionGroup.listFromAddons([
        {
          'id': 'cheese',
          'title': 'نوع الجبن',
          'required': true,
          'maxSelections': 1,
          'options': [
            {'id': 'c1', 'name': 'شيدر', 'extraPrice': 500},
            {'id': 'c2', 'name': 'موزاريلا', 'extraPrice': 0},
          ],
        },
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.id, 'cheese');
      expect(groups.single.title, 'نوع الجبن');
      expect(groups.single.required, isTrue);
      expect(groups.single.maxSelections, 1);
      expect(groups.single.options, hasLength(2));
      expect(groups.single.options.first.name, 'شيدر');
      expect(groups.single.options.first.extraPrice, 500);
    });

    test('parses grouped addons with alternative keys', () {
      final groups = OptionGroup.listFromAddons([
        {
          'name': 'الحجم',
          'isRequired': true,
          'max': 1,
          'choices': [
            {'value': 's', 'label': 'صغير', 'price': 0},
            {'value': 'l', 'label': 'كبير', 'price': 1000},
          ],
        },
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.title, 'الحجم');
      expect(groups.single.required, isTrue);
      expect(groups.single.maxSelections, 1);
      expect(groups.single.options, hasLength(2));
      expect(groups.single.options.last.name, 'كبير');
      expect(groups.single.options.last.extraPrice, 1000);
    });

    test('parses flat addon list into a single optional group', () {
      final groups = OptionGroup.listFromAddons([
        {'name': 'صوص إضافي', 'price': 250},
        {'name': 'بدون بصل', 'price': 0},
      ]);

      expect(groups, hasLength(1));
      final group = groups.single;
      expect(group.required, isFalse);
      expect(group.maxSelections, 2);
      expect(group.options.map((o) => o.name), ['صوص إضافي', 'بدون بصل']);
      expect(group.options.first.extraPrice, 250);
    });

    test('parses map containing a groups list', () {
      final groups = OptionGroup.listFromAddons({
        'groups': [
          {
            'title': 'الإضافات',
            'options': [
              {'name': 'جبن', 'extraPrice': 500},
            ],
          },
        ],
      });

      expect(groups, hasLength(1));
      expect(groups.single.options.single.name, 'جبن');
    });

    test('skips entries that have no recognizable option data', () {
      final groups = OptionGroup.listFromAddons([
        {'price': 100}, // no name
        {'id': 'x'}, // no name
      ]);
      expect(groups, isEmpty);
    });
  });
}
