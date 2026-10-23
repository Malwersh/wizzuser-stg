import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/order_model.dart';
import 'package:foodapp_user/widgets/order_arrival_card.dart';
void main(){
 final now=DateTime.utc(2026,10,17,12);
 OrderModel order({String status='preparing',Map<String,dynamic>? estimate})=>OrderModel.fromJson({'orderId':'o','status':status,'createdAt':now.toIso8601String(),'items':[],'deliveryAddress':<String,dynamic>{},if(estimate!=null)'deliveryEstimate':estimate,'driverId':'driver','driverName':'Driver','estimatedPreparationTime':20});
 testWidgets('arrival window uses server estimates and preparation',(tester)async{
  final o=order(estimate:{'earliestAt':'2026-10-17T12:20:00Z','latestAt':'2026-10-17T12:25:00Z'});
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:OrderArrivalCard(order:o,now:()=>now))));
  expect(find.text('20–25 دقيقة'),findsOneWidget);expect(find.textContaining('وقت التحضير المحدد: 20'),findsOneWidget);
  await tester.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('no fabricated minutes when missing or overdue',(tester)async{
  await tester.pumpWidget(MaterialApp(home:OrderArrivalCard(order:order(),now:()=>now)));
  expect(find.text('قيد التقدير'),findsOneWidget);
  await tester.pumpWidget(MaterialApp(home:OrderArrivalCard(order:order(estimate:{'latestAt':'2026-10-17T11:59:00Z'}),now:()=>now)));
  expect(find.text('نحدّث وقت الوصول'),findsOneWidget);
  await tester.pumpWidget(const SizedBox.shrink());
 });
 test('status copies preserve server timing and driver identity',(){final o=order(estimate:{'latestAt':'2026-10-17T12:25:00Z'});final next=o.copyWith(status:OrderStatus.confirmed);expect(next.deliveryEstimate,o.deliveryEstimate);expect(next.driverId,'driver');expect(next.estimatedPreparationTime,20);});

test('stale search exhaustion cannot override an assigned driver', () {
  for (final status in ['assigned', 'accepted', 'heading_to_store', 'picked_up']) {
    final order = OrderModel.fromJson({
      'orderId': 'order', 'status': status, 'items': [],
      'deliveryAddress': <String, dynamic>{},
      'driverId': 'driver', 'driverSearchUnavailable': true,
    });
    expect(order.driverSearchUnavailable, isFalse);
  }
});

}
