import 'package:flutter/material.dart';
import '../models/order_model.dart';

class TrackingProgressCard extends StatelessWidget {
  final OrderModel order;
  const TrackingProgressCard({super.key, required this.order});
  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF00296B);
    final s = order.status.value;
    final ended = {
      'cancelled',
      'rejected',
      'expired',
      'failed',
      'returned',
    }.contains(s);
    final delivered = s == 'delivered';
    final traveling = {
      'picked_up',
      'heading_to_customer',
      'on_the_way',
      'arrived_at_customer',
    }.contains(s);
    final prepared = {
      'preparing',
      'ready',
      'ready_for_pickup',
      'assigned',
      'accepted',
      'heading_to_store',
      'arrived_at_store',
    }.contains(s);
    final index =
        delivered
            ? 3
            : traveling
            ? 2
            : prepared
            ? 1
            : 0;
    final late =
        DateTime.tryParse(
          order.deliveryEstimate?['latestAt']?.toString() ?? '',
        ) ??
        order.estimatedDeliveryTime;
    final early = DateTime.tryParse(
      order.deliveryEstimate?['earliestAt']?.toString() ?? '',
    );
    String estimate = 'سنحدّث وقت الوصول حسب تقدم طلبك';
    if (late != null && !ended && !delivered) {
      final max = late.difference(DateTime.now()).inMinutes;
      final min = early?.difference(DateTime.now()).inMinutes;
      if (max > 0)
        estimate =
            min != null && min > 0 && min < max
                ? 'الوصول المتوقع خلال $min–$max دقيقة'
                : 'الوصول المتوقع خلال نحو $max دقيقة';
      else
        estimate = 'نحدّث وقت الوصول المتوقع';
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.status.arabicName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
          const SizedBox(height: 6),
          if (!ended && !delivered)
            Text(
              estimate,
              style: const TextStyle(fontSize: 13, color: Color(0xFF647184)),
            ),
          if (order.cancellationStatus == 'REQUESTED')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'طلب الإلغاء قيد المراجعة',
                style: TextStyle(color: navy),
              ),
            ),
          if (!ended) ...[
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 2,
                                color:
                                    i == 0
                                        ? Colors.transparent
                                        : i <= index
                                        ? navy
                                        : const Color(0xFFE8ECF2),
                              ),
                            ),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    i <= index ? navy : const Color(0xFFF0F3F8),
                              ),
                              child: Icon(
                                i < index || delivered
                                    ? Icons.check
                                    : [
                                      Icons.receipt_long_outlined,
                                      Icons.restaurant,
                                      Icons.delivery_dining,
                                      Icons.home_outlined,
                                    ][i],
                                size: 16,
                                color:
                                    i <= index
                                        ? Colors.white
                                        : const Color(0xFF7A879A),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color:
                                    i == 3
                                        ? Colors.transparent
                                        : i < index
                                        ? navy
                                        : const Color(0xFFE8ECF2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ['تأكيد الطلب', 'التحضير', 'في الطريق', 'التسليم'][i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: i <= index ? navy : const Color(0xFF7A879A),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
