import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/screens/customer_order_complaint_screen.dart';
import 'package:foodapp_user/services/customer_order_complaint_service.dart';

class FakeComplaints extends CustomerOrderComplaintService {
  final calls = <Map<String, dynamic>>[];
  bool opened = false, uncertain = true;
  @override
  Future<Map<String, dynamic>> call(
    String orderId,
    Map<String, dynamic> input,
  ) async {
    if (input['action'] != 'READ') {
      calls.add({...input});
      if (uncertain) {
        uncertain = false;
        throw StateError('TIMEOUT');
      }
      opened = true;
    }
    return {
      'success': true,
      'orderId': orderId,
      'caseId': opened ? 'case' : null,
      'version': opened ? 1 : 0,
      'status': opened ? 'OPEN' : 'NOT_OPENED',
      'canOpen': true,
      'type': 'MISSING_ITEMS',
      'description': 'صنف ناقص في الطلب',
      'supportSessionId': 'session',
      'decision': null,
      'evidence': [],
      'canAppeal': false,
    };
  }
}

void main() {
  testWidgets(
    'uncertain complaint keeps description and reuses identity when customer retries',
    (tester) async {
      final service = FakeComplaints();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerOrderComplaintScreen(orderId: 'o', service: service),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'صنف ناقص في الطلب');
      await tester.ensureVisible(find.text('إرسال الشكوى'));
      await tester.tap(find.text('إرسال الشكوى'));
      await tester.pumpAndSettle();
      expect(find.textContaining('لم تُسجل'), findsNothing);
      expect(service.calls.length, 1);
      await tester.tap(find.text('إرسال الشكوى'));
      await tester.pumpAndSettle();
      expect(service.calls.length, 2);
      expect(service.calls[0]['requestId'], service.calls[1]['requestId']);
      expect(find.text('تم استلام الشكوى'), findsOneWidget);
      expect(find.text('محادثة الدعم بخصوص هذا الطلب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('validation stops empty report before calling server', (
    tester,
  ) async {
    final service = FakeComplaints();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerOrderComplaintScreen(orderId: 'o', service: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('إرسال الشكوى'));
    await tester.tap(find.text('إرسال الشكوى'));
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty);
    expect(find.textContaining('وصفًا واضحًا'), findsOneWidget);
  });
}
