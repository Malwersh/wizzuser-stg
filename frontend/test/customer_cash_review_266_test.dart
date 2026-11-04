import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/screens/customer_cash_review_screen.dart';
import 'package:foodapp_user/services/customer_cash_review_service.dart';

void main() {
  Map<String, dynamic> view({List<Map<String, dynamic>> refunds = const []}) =>
      {
        'success': true,
        'orderId': 'order1',
        'version': 1,
        'expectedIqd': 10000,
        'reports': [],
        'refunds': refunds,
      };
  testWidgets(
    'report requires an explicit physical payment declaration and retains its retry key',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      await t.pumpWidget(
        MaterialApp(
          home: CustomerCashReviewScreen(
            call: (v) async {
              if (v['action'] == 'READ_CUSTOMER_CASH_CASE') return view();
              writes.add(Map.of(v));
              throw Exception('LOST_RESPONSE');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'إرسال إفادة الدفع للمراجعة'),
            )
            .onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField).at(0), '8000');
      await t.enterText(
        find.byType(TextField).at(1),
        'دفعت المبلغ الموضح فعليًا',
      );
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('إرسال إفادة الدفع للمراجعة'));
      await t.tap(find.text('إرسال إفادة الدفع للمراجعة'));
      await t.pumpAndSettle();
      await t.tap(find.text('إرسال إفادة الدفع للمراجعة'));
      await t.pumpAndSettle();
      expect(writes.length, 2);
      expect(writes[0]['idempotencyKey'], writes[1]['idempotencyKey']);
      expect(writes[0]['reportedPaidIqd'], 8000);
      expect(writes[0]['confirmActualPayment'], true);
      expect(writes[0].containsKey('actorId'), false);
      expect(writes[0].containsKey('liability'), false);
    },
  );
  testWidgets(
    'customer confirms only the displayed refund after explicitly acknowledging full receipt',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      final refund = {
        'refundId': 'refund1',
        'amountIqd': 2000,
        'voucherNumber': 'CRV-TEST',
        'status': 'EXECUTED',
        'source': {'kind': 'COMPANY_CASHBOX'},
      };
      await t.pumpWidget(
        MaterialApp(
          home: CustomerCashReviewScreen(
            call: (v) async {
              if (v['action'] != 'READ_CUSTOMER_CASH_CASE')
                writes.add(Map.of(v));
              return view(refunds: [refund]);
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('تأكيد استلام الرد كاملًا'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('تأكيد استلام الرد كاملًا'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'حفظ الإقرار'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(CheckboxListTile),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('حفظ الإقرار'));
      await t.pumpAndSettle();
      expect(writes.single['action'], 'ACKNOWLEDGE_CUSTOMER_REFUND');
      expect(writes.single['confirmFullReceipt'], true);
      expect(writes.single['refundId'], 'refund1');
      expect(writes.single.containsKey('amountIqd'), false);
      expect(writes.single.containsKey('customerId'), false);
    },
  );
  test(
    'original credential and order binding survive the transport boundary',
    () async {
      final s = CustomerCashReviewService(
        token: () async => 'original-access-token',
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer original-access-token');
          final b = jsonDecode(r.body);
          expect(b['orderId'], 'order1');
          expect(b['action'], 'READ_CUSTOMER_CASH_CASE');
          return http.Response(jsonEncode(view()), 200);
        }),
      );
      expect(
        (await s.call('order1', {
          'action': 'READ_CUSTOMER_CASH_CASE',
        }))['orderId'],
        'order1',
      );
    },
  );
  test(
    'changed session or foreign response cannot acknowledge another account receipt',
    () async {
      var credential = 'first';
      final s = CustomerCashReviewService(
        token: () async => credential,
        client: MockClient((_) async {
          credential = 'second';
          return http.Response(jsonEncode(view()), 200);
        }),
      );
      await expectLater(
        s.call('order1', {'action': 'READ_CUSTOMER_CASH_CASE'}),
        throwsException,
      );
      final foreign = CustomerCashReviewService(
        token: () async => 'token',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({...view(), 'orderId': 'foreign'}), 200),
        ),
      );
      await expectLater(
        foreign.call('order1', {'action': 'READ_CUSTOMER_CASH_CASE'}),
        throwsException,
      );
    },
  );

  testWidgets(
    'payment submission shows visible confirmation and persists own latest report after refresh',
    (t) async {
      var submitted = false;
      final report = {'actorKind': 'DRIVER', 'reportedPaidIqd': 9000};
      await t.pumpWidget(
        MaterialApp(
          home: CustomerCashReviewScreen(
            driver: true,
            call: (body) async {
              if (body['action'] == 'REPORT_CASH_PAYMENT') submitted = true;
              return {
                ...view(),
                'reports': [
                  if (submitted) report,
                  {'actorKind': 'CUSTOMER', 'reportedPaidIqd': 8250},
                ],
              };
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(0), '9000');
      await t.enterText(
        find.byType(TextField).at(1),
        'اختبار استلام الفرق دون تداول مال حقيقي',
      );
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('إرسال إفادة الدفع للمراجعة'));
      await t.tap(find.text('إرسال إفادة الدفع للمراجعة'));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'تم إرسال إفادة الدفع بنجاح. بانتظار مراجعة الإدارة.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('آخر إفادة مرسلة: 9000 د.ع'), findsOneWidget);
      expect(find.text('آخر إفادة مرسلة: 8250 د.ع'), findsNothing);
      await t.tap(find.byTooltip('تحديث الحالة'));
      await t.pumpAndSettle();
      expect(find.text('آخر إفادة مرسلة: 9000 د.ع'), findsOneWidget);
    },
  );
}
