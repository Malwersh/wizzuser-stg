import 'dart:async';
import 'package:flutter/material.dart';

/// Fail-closed presentation only. Server checks the live policy at execution.
class WalletTransferGate extends StatefulWidget {
 const WalletTransferGate({super.key,required this.check,required this.builder,this.scope});
 final Future<bool> Function() check;
 final Widget Function(bool enabled) builder;
 final Object? scope;
 @override State<WalletTransferGate> createState()=>_WalletTransferGateState();
}
class _WalletTransferGateState extends State<WalletTransferGate> with WidgetsBindingObserver {
 bool enabled=false;int generation=0;Timer? timer;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_read();timer=Timer.periodic(const Duration(seconds:30),(_)=>_read());}
 @override void didUpdateWidget(covariant WalletTransferGate old){super.didUpdateWidget(old);if(old.scope!=widget.scope){generation++;enabled=false;_read();}}
 @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)_read();}
 Future<void> _read()async{final current=++generation;var next=false;try{next=await widget.check();}catch(_){}if(mounted&&current==generation)setState(()=>enabled=next);}
 @override void dispose(){generation++;timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
 @override Widget build(BuildContext context)=>widget.builder(enabled);
}
