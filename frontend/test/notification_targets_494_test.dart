import 'dart:convert';
import 'package:foodapp_user/services/notification_navigation.dart';
import 'package:foodapp_user/screens/customer_order_complaint_screen.dart';
import 'package:foodapp_user/screens/customer_support_chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/services/notification_inbox_service.dart';
import 'package:foodapp_user/models/inbox_notification.dart';

void main() {
  test(
    'complaint update opens its complaint, while support reply opens chat',
    () {
      final complaint = InboxNotification.fromJson({
        'id': 'CN:complaint',
        'type': 'order_complaint_updated',
        'orderId': 'order-1',
        'sessionId': 'complaint-session',
      });
      final page = NotificationNavigation.destinationFor(complaint);
      expect(page, isA<CustomerOrderComplaintScreen>());
      expect((page as CustomerOrderComplaintScreen).orderId, 'order-1');
      final reply = InboxNotification.fromJson({
        'id': 'CN:reply',
        'type': 'support_reply',
        'orderId': 'order-2',
        'sessionId': 'support-session',
      });
      final chat = NotificationNavigation.destinationFor(reply);
      expect(chat, isA<CustomerSupportChatScreen>());
      expect((chat as CustomerSupportChatScreen).sessionId, 'support-session');
    },
  );
  test('complaint notification retains its exact order and conversation', () {
    final n = InboxNotification.fromJson({
      'id': 'CN:complaint',
      'type': 'order_complaint_updated',
      'orderId': 'order-1',
      'sessionId': 'complaint-session',
      'target': 'complaint',
    });
    final saved = InboxNotification.fromJson(n.toJson());
    expect(saved.type, 'order_complaint_updated');
    expect(saved.orderId, 'order-1');
    expect(saved.target, 'complaint');
    expect(saved.sessionId, 'complaint-session');
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'notification_account_binding': jsonEncode({
        'sub': 'customer',
        'legacyId': 'legacy',
      }),
    }),
  );
  test(
    'campaign survives persistence with its actionable identifier',
    () async {
      final n = await NotificationInboxService.recordPush(
        const RemoteMessage(
          messageId: 'push',
          data: {
            'eventId': 'campaign-event',
            'subjectId': 'customer',
            'type': 'campaign_offer',
            'campaignId': 'campaign-1',
          },
        ),
      );
      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'notification_inbox_customer',
                )!,
              )
              as List;
      expect(n!.campaignId, 'campaign-1');
      expect(
        InboxNotification.fromJson(
          Map<String, dynamic>.from(stored.single),
        ).campaignId,
        'campaign-1',
      );
      expect(
        await NotificationInboxService.recordPush(
          const RemoteMessage(
            messageId: 'other-push',
            data: {'eventId': 'campaign-event', 'subjectId': 'customer'},
          ),
        ),
        isNull,
      );
    },
  );
  test(
    'support opens conversation rather than treating order-linked reply as order update',
    () async {
      final n = await NotificationInboxService.recordPush(
        const RemoteMessage(
          messageId: 'support',
          data: {
            'eventId': 'CN:support-event',
            'subjectId': 'customer',
            'type': 'support_reply',
            'sessionId': 'session-1',
            'orderId': 'order-1',
          },
        ),
      );
      expect(n!.category, 'support');
      expect(n.source, 'server');
      expect(n.sessionId, 'session-1');
      expect(n.orderId, 'order-1');
      expect(
        InboxNotification.fromJson(n.toJson()).read().sessionId,
        'session-1',
      );
    },
  );
  test('other account campaign is rejected', () async {
    expect(
      await NotificationInboxService.recordPush(
        const RemoteMessage(
          messageId: 'x',
          data: {'subjectId': 'other', 'campaignId': 'secret'},
        ),
      ),
      isNull,
    );
  });
  test(
    'push tap for another account cannot enter pending navigation',
    () async {
      expect(
        await NotificationInboxService.acceptsPush(
          const RemoteMessage(data: {'subjectId': 'other'}),
        ),
        isFalse,
      );
      expect(
        await NotificationInboxService.acceptsPush(
          const RemoteMessage(data: {'subjectId': 'customer'}),
        ),
        isTrue,
      );
      SharedPreferences.setMockInitialValues({});
      expect(
        await NotificationInboxService.acceptsPush(
          const RemoteMessage(data: {'subjectId': 'customer'}),
        ),
        isFalse,
      );
    },
  );
}
