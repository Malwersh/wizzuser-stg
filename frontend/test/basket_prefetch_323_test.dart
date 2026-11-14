import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/providers/app_state_provider.dart';

void main() {
  testWidgets(
    'basket mutations prefetch only the latest settled quantity; disposal cancels pending warmup',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final seen = <int>[];
      final branches = <String>[];
      final state = AppStateProvider(
        canWarmInvoice: () => true,
        warmInvoice: (branch, items, name) async {
          branches.add(branch);
          seen.add(items.single['quantity'] as int);
        },
      );
      await state.addToCart({
        'id': 'p',
        'name': 'وجبة',
        'price': 3000,
        'quantity': 1,
        'store_id': 'b',
        'store_name': 'مطعم',
      });
      await state.updateCartItemQuantity('p', 2);
      await state.updateCartItemQuantity('p', 3);
      await tester.pump(const Duration(milliseconds: 300));
      expect(seen, isEmpty);
      await tester.pump(const Duration(milliseconds: 60));
      expect(seen, [3]);
      expect(branches, ['b']);
      await state.updateCartItemQuantity('p', 4);
      state.dispose();
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen, [3]);
    },
  );
}
