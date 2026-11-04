import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/discount_item_policy.dart';
import 'package:foodapp_user/services/order_service.dart';

void main() {
  test('canonical option IDs pass while conflicting aliases fail', () {
    expect(hasDiscountCustomizations([{'selected_options': {'sides':['salad']}, 'customizations': {'sides':['salad']}}]), false);
    expect(hasDiscountCustomizations([{'selected_options': {'sides':['salad']}, 'customizations': {'sides':['rice']}}]), true);
  });

  test(
    'all populated selection aliases including free choices are rejected',
    () {
      for (final field in [
        'modifiers',
        'customizations',
        'selectedOptions',
        'selected_options',
        'variantId',
        'variant_id',
        'sizeId',
        'size_id',
      ]) {
        final item = <String, dynamic>{
          'id': 'p',
          field: [
            {'id': 'choice', 'price': 0},
          ],
        };
        expect(hasDiscountCustomizations([item]), true, reason: field);
        expect(discountSelectionFields(item)[field], item[field]);
      }
      expect(
        hasDiscountCustomizations([
          {'modifiers': {}},
        ]),
        true,
      );
    },
  );
  test('empty option groups and cooking instructions remain valid', () {
    expect(
      hasDiscountCustomizations([
        {
          'selected_options': {'sides': []},
          'modifiers': [],
          'special_instructions': 'No salt',
        },
      ]),
      false,
    );
  });
  test('both offer previews reject choices before making a request', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        final service = OrderService();
        final items = <Map<String, dynamic>>[
          {
            'id': 'p',
            'quantity': 1,
            'selected_options': {
              'sides': [
                {'id': 'free', 'price': 0},
              ],
            },
          },
        ];
        final results = [
          await service.validatePromoCode(
            code: 'CODE',
            storeId: 'b',
            items: items,
            orderTotal: 1000,
          ),
          await service.validateDiscount(
            storeId: 'b',
            discountId: 'd',
            items: items,
            orderTotal: 1000,
          ),
        ];
        for (final result in results) {
          expect(result['valid'], false);
          expect(result['message'], unsupportedDiscountItemsMessage);
        }
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    expect(calls, 0);
  });
}
