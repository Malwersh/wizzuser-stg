import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../constants/app_colors.dart';
import '../models/inbox_notification.dart';
import '../services/notification_inbox_service.dart';
import '../services/notification_navigation.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.service, this.permissionLoader});
  final NotificationInboxService? service;
  final Future<AuthorizationStatus> Function()? permissionLoader;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  late final inbox = widget.service ?? NotificationInboxService.instance;
  bool _loading = true, _more = false, _marking = false;
  String _filter = 'all';
  AuthorizationStatus? _permission;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationInboxService.changed.addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationInboxService.changed.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more) setState(() => _more = true);
    try {
      await inbox.load(more: more);
      _permission =
          widget.permissionLoader != null
              ? await widget.permissionLoader!()
              : (await FirebaseMessaging.instance.getNotificationSettings())
                  .authorizationStatus;
    } catch (_) {
      inbox.error = 'تعذر تحميل الإشعارات. حاول مرة أخرى.';
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
          _more = false;
        });
    }
  }

  Future<void> _read(List<InboxNotification> list, {bool all = false}) async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      await inbox.markRead(list, all: all);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر حفظ حالة القراءة. حاول مرة أخرى.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _open(InboxNotification item) async {
    await _read([item]);
    if (!mounted) return;
    if (item.category == 'wallet' || item.orderId != null) {
      await NotificationNavigation.open(item);
    } else {
      await showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder:
            (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(item.body),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
      );
    }
  }

  String _date(DateTime date) {
    final local = date.toLocal(), today = DateTime.now();
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day)
      return 'اليوم · ${DateFormat('h:mm a', 'ar').format(local)}';
    return DateFormat('d MMM · h:mm a', 'ar').format(local);
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            size: 40,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _filter == 'unread'
              ? 'أنت مطّلع على كل جديد'
              : 'لا توجد إشعارات هنا بعد',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'ستجد هنا تحديثات طلباتك ومحفظتك.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final list =
        inbox.items
            .where(
              (x) =>
                  _filter == 'all' ||
                  (_filter == 'unread' && !x.isRead),
            )
            .toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text(
            'الإشعارات',
            style: TextStyle(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  _marking || inbox.items.every((x) => x.isRead)
                      ? null
                      : () => _read(inbox.items, all: true),
              child: const Text(
                'قراءة الكل',
                style: TextStyle(color: AppColors.secondary),
              ),
            ),
          ],
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : !inbox.isAuthenticated
                ? const Center(child: Text('سجّل الدخول لعرض إشعارات حسابك'))
                : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_permission == AuthorizationStatus.denied)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.notifications_off_outlined,
                                color: AppColors.secondary,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'فعّل إشعارات الجهاز لتصلك التحديثات فورًا.',
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await FirebaseMessaging.instance
                                      .requestPermission();
                                  await _load();
                                },
                                child: const Text('تفعيل'),
                              ),
                            ],
                          ),
                        ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final entry
                                in {
                                  'all': 'الكل',
                                  'unread': 'غير المقروءة',
                                }.entries)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 8,
                                ),
                                child: ChoiceChip(
                                  label: Text(entry.value),
                                  selected: _filter == entry.key,
                                  onSelected:
                                      (_) =>
                                          setState(() => _filter = entry.key),
                                  showCheckmark: false,
                                  selectedColor: AppColors.secondary,
                                  labelStyle: TextStyle(
                                    color:
                                        _filter == entry.key
                                            ? Colors.white
                                            : AppColors.secondary,
                                  ),
                                  backgroundColor: Colors.white,
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (inbox.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  inbox.error!,
                                  style: const TextStyle(
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _load(),
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      if (list.isEmpty) _empty(),
                      for (final item in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _open(item),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color:
                                        item.isRead
                                            ? const Color(0xFFE9ECF1)
                                            : AppColors.primary.withValues(
                                              alpha: 0.55,
                                            ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppColors.secondary.withValues(
                                          alpha: 0.06,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        item.category == 'wallet'
                                            ? Icons
                                                .account_balance_wallet_outlined
                                            : item.category == 'orders'
                                            ? Icons.receipt_long_outlined
                                            : Icons.notifications_none_rounded,
                                        color: AppColors.secondary,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        item.isRead
                                                            ? FontWeight.w500
                                                            : FontWeight.w700,
                                                    color: AppColors.secondary,
                                                  ),
                                                ),
                                              ),
                                              if (!item.isRead)
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color:
                                                            AppColors.primary,
                                                        shape: BoxShape.circle,
                                                      ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            item.body,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF555D6B),
                                              height: 1.5,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            _date(item.createdAt),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (inbox.cursor != null)
                        TextButton(
                          onPressed: _more ? null : () => _load(more: true),
                          child:
                              _more
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Text('تحميل المزيد'),
                        ),
                    ],
                  ),
                ),
      ),
    );
  }
}
