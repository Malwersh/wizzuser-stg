import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/order_model.dart';
void main() {
  test('search exhaustion survives cache and copying without cancellation', () {
    final order = OrderModel.fromJson({'id':'o','status':'ready_for_pickup','driverSearchUnavailable':true});
    expect(order.driverSearchUnavailable, isTrue);
    expect(OrderModel.fromJson(order.toJson()).driverSearchUnavailable, isTrue);
    expect(order.copyWith().driverSearchUnavailable, isTrue);
    expect(order.status, isNot(OrderStatus.cancelled));
    expect(OrderModel.fromJson({'id':'old'}).driverSearchUnavailable, isFalse);
  });
}
