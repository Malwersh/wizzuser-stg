class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.type,
    this.readAt,
    this.source = 'local',
    this.orderId,
    this.orderNumber,
    this.target = '',
  });
  final String id, title, body, type, source, target;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? orderId, orderNumber;
  bool get isRead => readAt != null;
  String get category =>
      type == 'order_update' || orderId != null
          ? 'orders'
          : type.contains('wallet') || target == 'wallet'
          ? 'wallet'
          : 'general';
  factory InboxNotification.fromJson(Map<String, dynamic> j) =>
      InboxNotification(
        id: j['id'].toString(),
        title: j['title']?.toString() ?? 'إشعار جديد',
        body: j['body']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        type: j['type']?.toString() ?? '',
        readAt: DateTime.tryParse(j['readAt']?.toString() ?? ''),
        source: j['source']?.toString() ?? 'local',
        orderId: j['orderId']?.toString(),
        orderNumber: j['orderNumber']?.toString(),
        target: j['target']?.toString() ?? '',
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'type': type,
    'readAt': readAt?.toIso8601String(),
    'source': source,
    'orderId': orderId,
    'orderNumber': orderNumber,
    'target': target,
  };
  InboxNotification read() => InboxNotification.fromJson({
    ...toJson(),
    'readAt': DateTime.now().toIso8601String(),
  });
}
