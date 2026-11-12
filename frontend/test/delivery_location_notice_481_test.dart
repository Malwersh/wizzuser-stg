import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:foodapp_user/widgets/delivery_location_notice.dart';

Position position({bool stale = false}) => Position(
  latitude: 31.9,
  longitude: 44.4,
  timestamp: DateTime.now().subtract(Duration(minutes: stale ? 20 : 0)),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
void main() {
  testWidgets(
    'nearby, missing and stale device locations do not prompt or block',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
        ),
      );
      expect(
        await confirmDeliveryDistance(
          context,
          31.9,
          44.4,
          readPosition: () async => position(),
        ),
        true,
      );
      expect(
        await confirmDeliveryDistance(
          context,
          35,
          44,
          readPosition: () async => null,
        ),
        true,
      );
      expect(
        await confirmDeliveryDistance(
          context,
          35,
          44,
          readPosition: () async => position(stale: true),
        ),
        true,
      );
      expect(find.text('عنوان التوصيل بعيد عن موقعك'), findsNothing);
    },
  );
  testWidgets(
    'far address requires explicit acceptance and allows returning to edit',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
        ),
      );
      final rejected = confirmDeliveryDistance(
        context,
        35,
        44,
        readPosition: () async => position(),
      );
      await tester.pumpAndSettle();
      expect(find.text('عنوان التوصيل بعيد عن موقعك'), findsOneWidget);
      await tester.tap(find.text('العودة لتعديل العنوان'));
      await tester.pumpAndSettle();
      expect(await rejected, false);
      final accepted = confirmDeliveryDistance(
        context,
        35,
        44,
        readPosition: () async => position(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('نعم، التوصيل لهذا العنوان'));
      await tester.pumpAndSettle();
      expect(await accepted, true);
    },
  );
}
