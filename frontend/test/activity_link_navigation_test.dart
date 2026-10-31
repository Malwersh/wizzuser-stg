import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/activity_link_navigation.dart';
void main() {
 test('activity links select exactly one order, never an external URL', () {
   expect(ActivityLinkNavigation.orderIdFromUrl('wizuser://orders/17f87a39-0edf-57c8-8971-c2d6d7dd42aa'), '17f87a39-0edf-57c8-8971-c2d6d7dd42aa');
   for (final value in ['https://orders/id','wizuser://wallet/id','wizuser://orders/id/other','wizuser://orders/id?next=evil','wizuser://orders/%2Fbad']) {
     expect(ActivityLinkNavigation.orderIdFromUrl(value), isNull);
   }
 });
}
