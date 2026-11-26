import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/order_model.dart';

void main() {
  test('stored unitPrice uses thousandths of IQD and quantity', () {
    final item = OrderItem.fromJson({'unitPrice': 3500125, 'quantity': 2});
    expect(item.unitPrice, 3500.125);
    expect(item.totalPrice, 7000.25);
  });
  test('API and cached item fields already use IQD', () {
    final item = OrderItem.fromJson({
      'unit_price': 3500, 'total_price': 7000, 'quantity': 2,
    });
    expect(item.unitPrice, 3500);
    expect(item.totalPrice, 7000);
  });
}
