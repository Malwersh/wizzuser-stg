import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/order_service.dart';
import 'package:foodapp_user/widgets/promo_floating_card.dart';

void main() {
  testWidgets('a campaign from the active feed renders and closes with X', (tester) async {
    final promos = await http.runWithClient(
      () => OrderService().getActivePromoCodes(),
      () => MockClient((request) async {
        expect(request.url.path.endsWith('/promo-codes/active'), isTrue);
        return http.Response(jsonEncode({
          'success': true,
          'promos': [{
            'code': 'ERE1', 'title': 'Campaign offer', 'description': 'Save on your order',
            'type': 'percentage', 'value': 10, 'minOrderAmount': 10000,
            'endDate': '2026-10-19',
          }],
        }), 200);
      }),
    );
    expect(promos, hasLength(1));
    bool visible = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) => visible
          ? PromoFloatingCard(promo: promos.single, onDismiss: () => setState(() => visible = false))
          : const SizedBox.shrink(),
    ))));
    expect(find.text('ERE1'), findsOneWidget);
    expect(find.text('Campaign offer'), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق العرض'));
    await tester.pump();
    expect(find.byType(PromoFloatingCard), findsNothing);
  });
}
