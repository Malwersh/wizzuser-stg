import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/screens/customer_phone_auth_screen.dart';
import 'package:foodapp_user/services/customer_phone_auth_service.dart';

class FakePhoneAuth extends CustomerPhoneAuthService {
  int sends = 0, verifies = 0;
  @override
  Future<void> send(String phone) async {
    sends++;
  }

  @override
  Future<bool> verify(
    String code, {
    String? name,
    bool accepted = false,
  }) async {
    verifies++;
    return false;
  }
}

void main() {
  testWidgets(
    'new number asks for name and consent in the existing OTP session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FakePhoneAuth();
      await tester.pumpWidget(
        MaterialApp(home: CustomerPhoneAuthScreen(service: api)),
      );
      await tester.enterText(find.byType(TextField).first, '07831367435');
      await tester.tap(find.text('إرسال رمز التحقق'));
      await tester.pumpAndSettle();
      expect(api.sends, 1);
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.tap(find.text('تأكيد ومتابعة'));
      await tester.pumpAndSettle();
      expect(api.verifies, 1);
      expect(find.text('الاسم الكامل'), findsOneWidget);
      await tester.ensureVisible(find.text('تأكيد ومتابعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد ومتابعة'));
      await tester.pumpAndSettle();
      expect(api.verifies, 1);
      expect(api.sends, 1);
      expect(
        find.text('أدخل اسمك ووافق على الشروط وسياسة الخصوصية'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
