import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/services/notification_inbox_service.dart';
void main() {
  test('push receipt persists once under its account and does not reset read state', () async {
    SharedPreferences.setMockInitialValues({'notification_account_binding':jsonEncode({'sub':'customer','legacyId':'legacy'})});
    final message=RemoteMessage(messageId:'msg',data:{'eventId':'event','driverId':'customer','type':'wallet_transfer_completed','action':'open_wallet'},notification:const RemoteNotification(title:'وصل تحويل',body:'5000 دينار'));
    expect((await NotificationInboxService.recordPush(message))!.title,'وصل تحويل');
    final prefs=await SharedPreferences.getInstance();final stored=jsonDecode(prefs.getString('notification_inbox_customer')!) as List;
    stored[0]['readAt']='2026-10-12T00:00:00Z';await prefs.setString('notification_inbox_customer',jsonEncode(stored));
    expect(await NotificationInboxService.recordPush(message),isNull);
    expect((jsonDecode(prefs.getString('notification_inbox_customer')!) as List).single['readAt'],isNotNull);
  });
  test('push addressed to another account is not displayed or cached', () async {
    SharedPreferences.setMockInitialValues({'notification_account_binding':jsonEncode({'sub':'customer','legacyId':'legacy'})});
    expect(await NotificationInboxService.recordPush(const RemoteMessage(messageId:'other',data:{'driverId':'another-account'})),isNull);
    expect((await SharedPreferences.getInstance()).getString('notification_inbox_customer'),isNull);
  });
  test('receipt without logged account binding is not assigned to the next account', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await NotificationInboxService.recordPush(const RemoteMessage(messageId:'guest')),isNull);
  });
}
