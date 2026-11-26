import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/address_model.dart';
import 'package:foodapp_user/widgets/address_capacity_sheet.dart';

void main() {
  List<DetailedAddress> addresses() => List.generate(
    10,
    (i) => DetailedAddress.fromJson({
      'id': 'addr-$i',
      'user_id': 'owner',
      'name': 'عنوان $i',
      'full_address': 'النجف، شارع $i',
      'latitude': 31.9,
      'longitude': 44.4,
    }),
  );
  testWidgets(
    'full address book clearly offers owned existing selection and management',
    (tester) async {
      AddressCapacityChoice? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      choice = await showModalBottomSheet<
                        AddressCapacityChoice
                      >(
                        context: context,
                        isScrollControlled: true,
                        builder:
                            (_) => AddressCapacitySheet(addresses: addresses()),
                      );
                    },
                    child: const Text('فتح'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();
      expect(find.text('قائمة العناوين ممتلئة'), findsOneWidget);
      expect(find.text('إدارة العناوين والمتابعة'), findsOneWidget);
      await tester.tap(find.text('عنوان 0'));
      await tester.pumpAndSettle();
      expect(choice?.address?.id, 'addr-0');
      expect(choice?.manage, false);
    },
  );
  testWidgets('management is an explicit choice without automatic deletion', (
    tester,
  ) async {
    AddressCapacityChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    choice = await showModalBottomSheet<AddressCapacityChoice>(
                      context: context,
                      isScrollControlled: true,
                      builder:
                          (_) => AddressCapacitySheet(addresses: addresses()),
                    );
                  },
                  child: const Text('فتح'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدارة العناوين والمتابعة'));
    await tester.pumpAndSettle();
    expect(choice?.manage, true);
    expect(choice?.address, isNull);
  });
}
