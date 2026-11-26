import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/screens/checkout_screen.dart';

void main() {
  testWidgets('first review click keeps the form and input mounted across async pricing and blocks duplicate taps', (t) async {
    final form = GlobalKey<FormState>();
    final pending = Completer<void>();
    var busy = false, reviews = 0, calls = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) => CheckoutLoadingBody(
        busy: busy, progress: const CircularProgressIndicator(),
        child: Form(key: form, child: Column(children: [
          TextFormField(initialValue: 'محمد', validator: (v) => v == 'محمد' ? null : 'invalid'),
          ElevatedButton(onPressed: () async {
            calls++;
            setState(() => busy = true);
            await pending.future;
            if (form.currentState!.validate()) reviews++;
            setState(() => busy = false);
          }, child: const Text('review')),
        ])),
      ),
    ))));
    final originalForm = form.currentState;
    await t.tap(find.text('review'));await t.pump();
    expect(form.currentState, same(originalForm));
    expect(find.text('محمد'), findsOneWidget);
    await t.tap(find.text('review'), warnIfMissed: false);await t.pump();
    expect(calls, 1);
    pending.complete();await t.pumpAndSettle();
    expect(reviews, 1);expect(calls, 1);expect(form.currentState, same(originalForm));
    expect(t.takeException(), isNull);
  });
}
