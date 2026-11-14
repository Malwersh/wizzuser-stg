import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/order_model.dart';
void main(){
 test('pending cancellation does not change commercial status and survives cache/refresh',(){
  final o=OrderModel.fromJson({'orderId':'order1','status':'preparing','exceptionCancellation':{'state':'REQUESTED','caseId':'OEX:one'}});
  expect(o.status,OrderStatus.preparing);expect(o.cancellationStatus,'REQUESTED');expect(o.canBeCancelled,true);
  final copy=o.copyWith(status:OrderStatus.readyForPickup);expect(copy.cancellationCaseId,'OEX:one');
  final cached=OrderModel.fromJson(copy.toJson());expect(cached.cancellationStatus,'REQUESTED');expect(cached.status,OrderStatus.readyForPickup);
 });
 test('post-pickup and returned orders cannot offer ordinary cancellation',(){
  for(final state in ['picked_up','heading_to_customer','arrived_at_customer','returned','returning','delivered','cancelled']){
   expect(OrderModel.fromJson({'status':state}).canBeCancelled,false,reason:state);
  }
 });
}
