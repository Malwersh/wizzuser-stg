import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/order_model.dart';

void main() {
  test('tracking preserves the accepted IQD breakdown during refresh and copy', () {
    final order = OrderModel.fromJson({
      'status': 'assigned',
      'pricing': {'goodsSubtotal': 7000000, 'deliveryFee': 1500000,
        'serviceFee': 500000, 'tip': 500000, 'total': 9500000},
    });
    expect(order.subtotal, 7000);
    expect(order.deliveryFee, 1500);
    expect(order.serviceFee, 500);
    expect(order.tip, 500);
    expect(order.total, 9500);
    expect(order.copyWith(status: OrderStatus.headingToStore).tip, 500);
    expect(OrderModel.fromJson(order.toJson()).serviceFee, 500);
  });
}
