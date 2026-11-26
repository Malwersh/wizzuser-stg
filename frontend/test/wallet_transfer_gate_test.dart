import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/wallet_transfer_gate.dart';
void main(){
 testWidgets('policy hides actions on disable or failed refresh and restores them after enable',(tester)async{
 var allowed=true,fail=false;
 await tester.pumpWidget(MaterialApp(home:Scaffold(body:WalletTransferGate(check:()async{if(fail)throw Exception('offline');return allowed;},builder:(enabled)=>enabled?const Text('تحويل الرصيد'):const SizedBox.shrink()))));
 await tester.pump();expect(find.text('تحويل الرصيد'),findsOneWidget);
 allowed=false;await tester.pump(const Duration(seconds:30));await tester.pump();expect(find.text('تحويل الرصيد'),findsNothing);
 allowed=true;await tester.pump(const Duration(seconds:30));await tester.pump();expect(find.text('تحويل الرصيد'),findsOneWidget);
 fail=true;await tester.pump(const Duration(seconds:30));await tester.pump();expect(find.text('تحويل الرصيد'),findsNothing);
 await tester.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('old scope response cannot reenable transfer for new scope',(tester)async{
 final pending=Completer<bool>();
 Widget view(String scope,Future<bool> Function() check)=>MaterialApp(home:WalletTransferGate(scope:scope,check:check,builder:(enabled)=>enabled?const Text('transfer'):const SizedBox.shrink()));
 await tester.pumpWidget(view('old',()=>pending.future));
 await tester.pumpWidget(view('new',()async=>false));await tester.pump();pending.complete(true);await tester.pump();expect(find.text('transfer'),findsNothing);await tester.pumpWidget(const SizedBox.shrink());
 });
}
