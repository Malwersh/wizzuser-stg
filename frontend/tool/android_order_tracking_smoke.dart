// Local-only UI smoke test. Does not create orders or contact the backend.
import 'dart:async';
import 'package:flutter/material.dart';
import '../lib/services/android_order_tracking.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    return true;
  }());
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('اختبار محلي لتتبع Android — دون طلب حقيقي')),
      ),
    ),
  );
  await AndroidOrderTracking.clear();
  await AndroidOrderTracking.initialize();
  final at = DateTime.now().toUtc(), id = 'LOCAL-TRACKING-100';
  Map<String, dynamic> value(String status, int seconds) => {
    'orderId': id,
    'storeName': 'مطعم تجريبي',
    'orderNumber': 'LOCAL-100',
    'status': status,
    'statusLabel': status == 'preparing' ? 'يجري تحضير طلبك' : 'تم تسليم الطلب',
    'etaText': 'الوصول المتوقع ٢٠–٢٥ دقيقة',
    'progress': status == 'preparing' ? 0.4 : 1,
    'updatedAt': at.add(Duration(seconds: seconds)).toIso8601String(),
  };
  await AndroidOrderTracking.show(value('preparing', 1));
  debugPrint('TRACKING100_VISIBLE');
  await Future<void>.delayed(const Duration(seconds: 40));
  await AndroidOrderTracking.show(value('delivered', 3));
  await AndroidOrderTracking.show(value('preparing', 2));
  debugPrint('TRACKING100_TERMINAL_AND_STALE_REPLAY_DONE');
}
