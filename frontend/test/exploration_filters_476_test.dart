import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/business_model.dart';
import 'package:foodapp_user/models/home_layout.dart';
import 'package:foodapp_user/screens/map_screen_new.dart';

void main() {
  testWidgets(
    'explore uses published filters and taxonomy, combines and resets choices',
    (tester) async {
      final layout = HomeLayout.fromJson({
        'configured': true,
        'filters': {
          'enabled': true,
          'items': [
            {
              'id': 'rating',
              'label': 'تقييم موثق',
              'kind': 'rating',
              'enabled': true,
              'value': 4,
            },
            {
              'id': 'offers',
              'label': 'عروض منطقتك',
              'kind': 'offers',
              'enabled': true,
            },
          ],
        },
        'navigation': {
          'enabled': true,
          'items': [
            {
              'id': 'restaurants',
              'label': 'مطاعم',
              'kind': 'activity',
              'value': 'RESTAURANT',
            },
            {
              'id': 'stores',
              'label': 'متاجر',
              'kind': 'activity',
              'value': 'STORE',
            },
            {
              'id': 'pizza',
              'label': 'بيتزا',
              'kind': 'cuisine',
              'value': 'pizza',
              'parentActivities': ['RESTAURANT'],
            },
          ],
        },
        'discovery': {
          'catalog': {
            'profiles': {
              'r': {
                'cuisineIds': ['pizza'],
              },
            },
          },
          'offers': {
            'expiresAt':
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'merchantIds': ['r'],
          },
        },
      });
      BusinessModel shop(String id, String type, double rating) =>
          BusinessModel(
            id: id,
            businessName: id == 'r' ? 'مطعم الاختبار' : 'متجر الاختبار',
            address: '',
            businessPhotoUrl: '',
            businessType: type,
            rating: rating,
            metadata: {'reviewCount': 3},
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapScreenNew(
              layout: layout,
              businesses: [shop('r', 'restaurant', 4.5), shop('s', 'store', 3)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('استكشف حولك · 2'), findsOneWidget);
      expect(find.text('تقييم موثق'), findsNothing);
      await tester.tap(find.byTooltip('الفلاتر'));
      await tester.pumpAndSettle();
      expect(find.text('تقييم موثق'), findsOneWidget);
      await tester.tap(find.text('متاجر'));
      await tester.pumpAndSettle();
      expect(find.text('استكشف حولك · 1'), findsOneWidget);
      expect(find.text('بيتزا'), findsNothing);
      await tester.tap(find.text('تقييم موثق'));
      await tester.pumpAndSettle();
      expect(find.text('استكشف حولك · 0'), findsOneWidget);
      await tester.tap(find.text('تقييم موثق'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متاجر'));
      expect(find.text('إعادة ضبط'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('استكشف حولك · 2'), findsOneWidget);
      await tester.tap(find.text('بيتزا'));
      await tester.pumpAndSettle();
      expect(find.text('استكشف حولك · 1'), findsOneWidget);
      await tester.tap(find.text('بيتزا'));
      await tester.pumpAndSettle();
      expect(find.text('استكشف حولك · 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
