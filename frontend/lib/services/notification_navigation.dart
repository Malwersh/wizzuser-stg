import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../models/inbox_notification.dart';
import '../screens/wallet_transfer_screen.dart';
import '../screens/order_tracking_screen.dart';

class NotificationNavigation {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static Future<void> Function(String)? campaignHandler;
  static Future<void> openCampaign(String id) async {
    if (!RegExp(r'^[\w-]{1,150}$').hasMatch(id)) return;
    if (campaignHandler != null) {
      await campaignHandler!(id);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingCampaignFromPushTap', id);
    }
  }

  static Future<void> open(InboxNotification item) async {
    if (item.campaignId?.isNotEmpty == true) {
      await openCampaign(item.campaignId!);
      return;
    }
    Widget? page;
    if (item.category == 'wallet') {
      page = const WalletTransferScreen();
    } else if (item.orderId != null) {
      page = OrderTrackingScreen(
        orderId: item.orderId!,
        orderNumber:
            item.orderNumber?.isNotEmpty == true
                ? item.orderNumber!
                : item.orderId!,
      );
    }
    if (page != null) {
      await navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => page!),
      );
    }
  }
}
