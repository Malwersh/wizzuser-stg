import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/widgets/rotating_search_hint.dart';
import 'package:foodapp_user/services/home_welcome_session.dart';
import 'package:foodapp_user/widgets/custom_bottom_navigation.dart';
void main() {
 test('custom greeting substitutes only the sanitized first name', () {
  expect(HomeWelcomeSession.greeting(signedIn:true,user:{'name':'محمد علي'},settings:{'signedIn':'رمضان كريم {name}'}),'رمضان كريم \u2068محمد\u2069');
  expect(HomeWelcomeSession.greeting(signedIn:false,settings:{'guest':'مرحبًا بضيوفنا'}),'مرحبًا بضيوفنا');
  expect(HomeWelcomeSession.greeting(signedIn:true,user:{'name':'07812345'},settings:{'anonymous':'أهلًا بك'}),'أهلًا بك');
 });
 testWidgets('types and deletes examples, fixes search icon position and respects reduced motion',(tester) async {
  Widget screen(bool reduced)=>MaterialApp(home:MediaQuery(data:MediaQueryData(disableAnimations:reduced),child:Scaffold(bottomNavigationBar:CustomBottomNavigation(currentIndex:0,onTap:(_){},searchHints:const ['بيتزا','فروج المدينة'],hintIntervalSeconds:4))));
  String text()=>tester.widget<Text>(find.descendant(of:find.byType(RotatingSearchHint),matching:find.byType(Text))).textSpan!.toPlainText();
  await tester.pumpWidget(screen(false));
  final position=tester.getCenter(find.byIcon(Icons.search));
  expect(text().contains('بيتزا'),false);
  await tester.pump(const Duration(milliseconds:200));expect(text().startsWith('بي'),true);
  await tester.pump(const Duration(milliseconds:300));expect(text().startsWith('بيتزا'),true);
  expect(tester.getCenter(find.byIcon(Icons.search)),position);
  await tester.pump(const Duration(milliseconds:5200));expect(text().startsWith('فروج'),true);
  expect(tester.getCenter(find.byIcon(Icons.search)),position);
  await tester.pumpWidget(screen(true));expect(text(),'فروج المدينة');
  await tester.pump(const Duration(seconds:8));expect(text(),'فروج المدينة');
  await tester.pumpWidget(const SizedBox());expect(tester.takeException(),isNull);
 });
}
