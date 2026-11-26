import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/order_service.dart';

void main() {
  test('service failure is not presented as customer ineligibility', () async {
    await http.runWithClient(
      () async {
        final r = await OrderService().validateDiscount(
          storeId: 'branch',
          discountId: 'offer',
          orderTotal: 15000,
          items: [
            {'id': 'burger', 'price': 3000, 'quantity': 5},
          ],
        );
        expect(r['valid'], false);
        expect(r['message'], contains('مشكلة في الخدمة'));
        expect(r['message'], isNot(contains('الحد الأدنى')));
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({'valid': false, 'message': 'DISCOUNT_UNAVAILABLE'}),
          503,
        ),
      ),
    );
  });
  test('nonmatching goods and minimum are actionable and distinct', () async {
    for (final entry
        in {
          'OFFER_NO_MATCHING_ITEMS': 'أصنافًا محددة',
          'OFFER_MINIMUM_ORDER': 'الحد الأدنى',
        }.entries) {
      await http.runWithClient(
        () async {
          final r = await OrderService().validateDiscount(
            storeId: 'branch',
            discountId: 'offer',
            orderTotal: 15000,
            items: [
              {'id': 'burger', 'price': 3000, 'quantity': 5},
            ],
          );
          expect(r['valid'], false);
          expect(r['message'], contains(entry.value));
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({'valid': false, 'message': entry.key}),
            409,
          ),
        ),
      );
    }
  });
}
