enum TransactionType {
  init,
  topup,
  topupSuccess,
  spend,
  refund,
  failed
}

enum TransactionStatus {
  pending,
  success,
  failed
}

class WalletTransactionModel {
  final String transactionId;
  final String userId;
  final TransactionType type;
  final double amount;
  final String currency;
  final TransactionStatus status;
  final String description;
  final String? orderId;
  final String? reference;
  final String? payTabsRef;
  final DateTime timestamp;
  final DateTime? completedAt;
  final String displayType;
  final String displayAmount;
  final String displayStatus;

  WalletTransactionModel({
    required this.transactionId,
    required this.userId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.status,
    required this.description,
    this.orderId,
    this.reference,
    this.payTabsRef,
    required this.timestamp,
    this.completedAt,
    required this.displayType,
    required this.displayAmount,
    required this.displayStatus,
  });

  factory WalletTransactionModel.fromJson(Map<String, dynamic> json) {
    return WalletTransactionModel(
      transactionId: json['transactionId'] ?? '',
      userId: json['userId'] ?? '',
      type: _parseTransactionType(json['type']),
      amount: (json['amount'] ?? 0).toDouble(),
      currency: json['currency'] ?? 'IQD',
      status: _parseTransactionStatus(json['status']),
      description: json['description'] ?? '',
      orderId: json['orderId'],
      reference: json['reference'],
      payTabsRef: json['payTabsRef'],
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
      displayType: json['displayType'] ?? '',
      displayAmount: json['displayAmount']?.toString() ?? '',
      displayStatus: json['displayStatus'] ?? '',
    );
  }

  static TransactionType _parseTransactionType(String? type) {
    switch (type?.toUpperCase()) {
      case 'INIT':
        return TransactionType.init;
      case 'TOPUP':
        return TransactionType.topup;
      case 'TOPUP_SUCCESS':
        return TransactionType.topupSuccess;
      case 'SPEND':
        return TransactionType.spend;
      case 'REFUND':
        return TransactionType.refund;
      case 'FAILED':
        return TransactionType.failed;
      default:
        return TransactionType.init;
    }
  }

  static TransactionStatus _parseTransactionStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'PENDING':
        return TransactionStatus.pending;
      case 'SUCCESS':
        return TransactionStatus.success;
      case 'FAILED':
        return TransactionStatus.failed;
      default:
        return TransactionStatus.pending;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'transactionId': transactionId,
      'userId': userId,
      'type': type.name.toUpperCase(),
      'amount': amount,
      'currency': currency,
      'status': status.name.toUpperCase(),
      'description': description,
      'orderId': orderId,
      'reference': reference,
      'payTabsRef': payTabsRef,
      'timestamp': timestamp.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'displayType': displayType,
      'displayAmount': displayAmount,
      'displayStatus': displayStatus,
    };
  }

  String getFormattedAmount() {
    if (currency == 'USD') {
      return '\$${amount.toStringAsFixed(2)}';
    } else if (currency == 'IQD') {
      return '${amount.toStringAsFixed(0)} د.ع';
    }
    return '${amount.toStringAsFixed(2)} $currency';
  }

  bool get isPositiveTransaction => 
      type == TransactionType.topup || 
      type == TransactionType.topupSuccess || 
      type == TransactionType.refund;

  bool get isNegativeTransaction => type == TransactionType.spend;

  bool get isInProgress => status == TransactionStatus.pending;
  bool get isCompleted => status == TransactionStatus.success;
  bool get isFailed => status == TransactionStatus.failed;

  String getRelativeTime() {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      return 'منذ ${difference.inDays} ${difference.inDays == 1 ? 'يوم' : 'أيام'}';
    } else if (difference.inHours > 0) {
      return 'منذ ${difference.inHours} ${difference.inHours == 1 ? 'ساعة' : 'ساعات'}';
    } else if (difference.inMinutes > 0) {
      return 'منذ ${difference.inMinutes} ${difference.inMinutes == 1 ? 'دقيقة' : 'دقائق'}';
    } else {
      return 'منذ لحظات';
    }
  }
}
