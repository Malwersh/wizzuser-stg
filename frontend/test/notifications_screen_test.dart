import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:foodapp_user/models/inbox_notification.dart';
import 'package:foodapp_user/screens/notifications_screen.dart';
import 'package:foodapp_user/services/notification_inbox_service.dart';
class FakeInbox extends NotificationInboxService {
  FakeInbox() { items = [InboxNotification(id:'one',title:'وصل تحويل',body:'أُضيف 5000 دينار',createdAt:DateTime.now(),type:'wallet_transfer_completed'),InboxNotification(id:'two',title:'تحديث الطلب',body:'طلبك قيد التحضير',createdAt:DateTime.now(),type:'order_update',orderId:'order',readAt:DateTime.now())]; }
  @override
  bool get isAuthenticated => true;
  @override
  Future<void> load({bool more=false}) async {}
  @override
  Future<void> markRead(List<InboxNotification> selected,{bool all=false}) async {items=items.map((x)=>x.read()).toList();NotificationInboxService.changed.value++;}
}
void main() {
  setUpAll(() async {await initializeDateFormatting('ar');});
  testWidgets('filters show real inbox entries and read-all clears unread view', (tester) async {
    final inbox=FakeInbox();
    await tester.pumpWidget(MaterialApp(home:NotificationsScreen(service:inbox,permissionLoader:()async=>AuthorizationStatus.authorized)));
    await tester.pumpAndSettle();
    expect(find.text('الطلبات'), findsNothing);
    expect(find.text('المحفظة'), findsNothing);
    expect(find.text('الكل'), findsOneWidget);
    expect(find.text('وصل تحويل'),findsOneWidget);
    expect(find.text('تحديث الطلب'),findsOneWidget);
    await tester.tap(find.text('غير المقروءة'));await tester.pumpAndSettle();
    expect(find.text('وصل تحويل'),findsOneWidget);expect(find.text('تحديث الطلب'),findsNothing);
    await tester.tap(find.text('قراءة الكل'));await tester.pumpAndSettle();
    expect(find.text('أنت مطّلع على كل جديد'),findsOneWidget);
  });
}
