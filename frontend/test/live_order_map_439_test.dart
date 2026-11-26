import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:foodapp_user/models/order_model.dart';
import 'package:foodapp_user/models/live_driver_point.dart';
import 'package:foodapp_user/widgets/live_order_map.dart';

void main() {
  testWidgets(
    'simulated points animate driver, ignore foreign and older points, clear at delivery',
    (t) async {
      final stream = StreamController<LiveDriverPoint>(sync: true);
      var markers = <Marker>{};
      final now = DateTime.now();
      OrderModel order(String status) => OrderModel.fromJson({
        'orderId': 'o',
        'driverId': 'd',
        'status': status,
        'createdAt': now.toIso8601String(),
        'items': [],
        'deliveryAddress': {'latitude': 31.92, 'longitude': 44.48},
      });
      Future<void> show(String status) async => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveOrderMap(
              order: order(status),
              locationStream: stream.stream,
              mapBuilder: (m, p) {
                markers = m;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      LiveDriverPoint point(double lat, int second, {String driver = 'd'}) =>
          LiveDriverPoint(
            orderId: 'o',
            driverId: driver,
            latitude: lat,
            longitude: 44.476014,
            heading: 90,
            accuracy: 8,
            observedAt: now.add(Duration(seconds: second)),
          );
      Marker? driver() =>
          markers.where((m) => m.markerId.value == 'driver').firstOrNull;
      await show('heading_to_customer');
      await t.pump();
      stream.add(point(31.913292, 0));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1200));
      expect(driver()!.position.latitude, closeTo(31.913292, .000001));
      stream.add(point(31.915, 5));
      await t.pump();
      await t.pump(const Duration(milliseconds: 550));
      expect(driver()!.position.latitude, greaterThan(31.913292));
      expect(driver()!.position.latitude, lessThan(31.915));
      await t.pump(const Duration(milliseconds: 600));
      expect(driver()!.position.latitude, closeTo(31.915, .000001));
      stream.add(point(40, 4));
      stream.add(point(41, 7, driver: 'other'));
      await t.pump();
      expect(driver()!.position.latitude, closeTo(31.915, .000001));
      await show('delivered');
      await t.pump();
      expect(driver(), isNull);
      await t.pumpWidget(const SizedBox());
      unawaited(stream.close());
      expect(t.takeException(), isNull);
    },
  );
}
