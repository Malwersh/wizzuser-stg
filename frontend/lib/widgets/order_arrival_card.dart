import 'dart:async';
import 'package:flutter/material.dart';
import '../models/order_model.dart';

/// Server ETA is an estimate. Ring progress reflects confirmed milestones, not
/// an invented countdown that declares arrival when a local clock reaches zero.
class OrderArrivalCard extends StatefulWidget {
  final OrderModel order;
  final DateTime Function()? now;
  const OrderArrivalCard({super.key, required this.order, this.now});
  @override
  State<OrderArrivalCard> createState() => _OrderArrivalCardState();
}

class _OrderArrivalCardState extends State<OrderArrivalCard>
    with WidgetsBindingObserver {
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _start();
    } else {
      _ticker?.cancel();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order, status = o.status.value;
    final terminal = [
      'cancelled',
      'rejected',
      'expired',
      'failed',
      'returned',
    ].contains(status);
    if (terminal) return const SizedBox.shrink();
    final delivered = ['delivered', 'completed'].contains(status);
    final pending = status == 'pending';
    final returning = ['returning','return_arrived'].contains(status);
    final now = (widget.now ?? DateTime.now)();
    final estimate = o.deliveryEstimate;
    final early =
        DateTime.tryParse(estimate?['earliestAt']?.toString() ?? '') ??
        o.estimatedDeliveryTime;
    final late =
        DateTime.tryParse(estimate?['latestAt']?.toString() ?? '') ?? early;
    String time = 'قيد التقدير',
        title =
            estimate?['driverWaitIncluded'] == false
                ? 'وقت مبدئي للوصول'
                : 'الوصول المتوقع';
    if (returning) {
      title = o.returnStatus=='REQUESTED'?'متابعة معالجة تعذر التسليم':'متابعة إرجاع الطلب';
      time = o.returnStatus=='REQUESTED'?'بانتظار تعليمات معالجة الطلب':o.returnStatus == 'REVIEW_REQUIRED' ? 'استلام المرتجع قيد المراجعة' : status == 'returning' ? 'السائق يعيد الطلب للمطعم' : 'بانتظار تأكيد استلام المطعم';
    } else if (delivered) {
      time = 'تم التسليم';
      title = 'بالعافية!';
    } else if (pending) {
      time = 'بانتظار القبول';
      title = 'أرسلنا طلبك إلى المطعم';
    } else if (o.driverSearchUnavailable) {
      title = 'متابعة الطلب مع المنصة';
      time = 'تعذر العثور على سائق';
    } else if (o.driverReplacementSearch) {
      title = 'الطلب جاهز لدى المطعم';
      time = 'نبحث عن سائق بديل';
    } else if (late != null && late.isAfter(now)) {
      final min = early!.difference(now).inSeconds;
      final from = (min / 60).ceil().clamp(1, 1440),
          to = (late.difference(now).inSeconds / 60).ceil().clamp(1, 1440);
      time = from == to ? '$to دقيقة' : '$from–$to دقيقة';
    } else if (late != null) {
      time = 'نحدّث وقت الوصول';
    }
    final progress =
        returning
            ? (status == 'returning' ? 0.5 : 0.75)
            : delivered
            ? 1.0
            : pending
            ? 0.08
            : ['confirmed'].contains(status)
            ? 0.2
            : ['preparing', 'in_kitchen'].contains(status)
            ? 0.4
            : ['ready', 'ready_for_pickup'].contains(status)
            ? 0.55
            : [
              'assigned',
              'heading_to_store',
              'arrived_at_store',
            ].contains(status)
            ? 0.65
            : [
              'picked_up',
              'heading_to_customer',
              'on_the_way',
            ].contains(status)
            ? 0.85
            : status == 'arrived_at_customer'
            ? 0.95
            : 0.08;
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            Semantics(
              label: 'حالة الطلب: ${o.status.arabicName}. $time',
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 9,
                        backgroundColor: color.withValues(alpha: 0.1),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            delivered
                                ? Icons.check_rounded
                                : Icons.delivery_dining_rounded,
                            color: color,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          Flexible(child: Text(
                            time,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold, fontSize: returning ? 16 : null),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              o.status.arabicName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!returning && !pending && !delivered && o.estimatedPreparationTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'وقت التحضير المحدد: ${o.estimatedPreparationTime} دقيقة',
                  textAlign: TextAlign.center,
                ),
              ),
            if (!returning && !pending && !delivered)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'الوقت تقديري ويتحدث حسب تجهيز الطلب وحركة السائق.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
