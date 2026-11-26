import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/order_model.dart';

void main() {
  test('saved configurations retain separate line IDs and the same product ID', () {
    final items = ['salad', 'rice'].map((choice) => OrderItem.fromJson({
      'itemId': 'product', 'lineId': 'CONFIG#$choice', 'name': 'Meal',
      'unitPrice': 2750000, 'quantity': 1,
      'selectedOptions': {'sides': [choice]},
    })).toList();
    expect(items[0].id, isNot(items[1].id));
    expect(items.map((i)=>i.productId).toList(), ['product','product']);
    expect(items[0].selectedOptions, {'sides':['salad']});
    expect(OrderItem.fromJson(items[1].toJson()).selectedOptions, {'sides':['rice']});
    expect(OrderItem.fromJson(items[1].toJson()).id, items[1].id);
  });
}
