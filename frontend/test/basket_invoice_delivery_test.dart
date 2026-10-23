import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/checkout_invoice_store.dart';
import 'package:foodapp_user/widgets/basket_invoice.dart';

class EmptyInvoiceStore extends CheckoutInvoiceStore {
  EmptyInvoiceStore() : super(account: () => 'test');
  @override
  Map<String,dynamic>? basketRequest(String branch,List<Map<String,dynamic>> items,
      {String storeName='المطعم',String storeAddress='العنوان غير محدد'}) => invoiceRequest(
        branch:branch,items:items,address:{'id':'a','latitude':31.9,'longitude':44.4});
  void update() => notifyListeners();
}
void main() {
  testWidgets('waiting for shared invoice never mounts a second storefront pricing request', (t) async {
    final store=EmptyInvoiceStore();var fallbackBuilds=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:BasketInvoiceDelivery(
      branch:'b',items:const [{'id':'p','price':3000,'quantity':5}],store:store,
      fallback:Builder(builder:(_){fallbackBuilds++;return const Text('parallel request');}),
    ))));
    expect(find.text('تُحدّد مع الفاتورة'),findsOneWidget);
    expect(fallbackBuilds,0);
    store.update();await t.pump();
    expect(fallbackBuilds,0);
    await t.pumpWidget(const SizedBox());store.dispose();
  });
}
