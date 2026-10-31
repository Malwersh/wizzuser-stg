import '../widgets/wallet_transfer_gate.dart';
import '../services/wallet_transfer_service.dart';
import 'wallet_transfer_screen.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/wallet_model.dart';
import '../models/wallet_transaction_model.dart';
import '../services/wallet_service.dart';
import '../services/session_service.dart';
import 'wallet_topup_screen.dart';
import 'login_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isLoading = true;
  bool _isLoadingTransactions = false;
  WalletModel? _wallet;
  List<WalletTransactionModel> _transactions = [];
  String? _lastTransactionKey;
  bool _hasMoreTransactions = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeWallet();
  }

  Future<void> _initializeWallet() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Check if user is logged in using unified session service
      final sessionService = SessionService.instance;
      if (!sessionService.isLoggedIn) {
        setState(() {
          _errorMessage = 'login_required';
          _isLoading = false;
        });
        return;
      }

      final userId = await SessionService.instance.getCurrentUserId();
      if (userId == 'anonymous' || userId == 'unknown') {
        setState(() {
          _errorMessage = 'login_required';
          _isLoading = false;
        });
        return;
      }

      // Initialize wallet if not exists
      if (userId != null) {
        await WalletService.initializeWallet(userId);
      }

      // Get wallet balance
      await _loadWalletBalance();

      // Load recent transactions
      await _loadTransactions();
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadWalletBalance() async {
    // Check if user is still logged in
    final sessionService = SessionService.instance;
    if (!sessionService.isLoggedIn) {
      setState(() {
        _errorMessage = 'login_required';
        _isLoading = false;
      });
      return;
    }

    final userId = await SessionService.instance.getCurrentUserId();
    if (userId == null || userId == 'anonymous' || userId == 'unknown') {
      setState(() {
        _errorMessage = 'login_required';
        _isLoading = false;
      });
      return;
    }

    final result = await WalletService.getWalletBalance(userId);

    if (result['success']) {
      setState(() {
        _wallet = WalletModel(
          userId: userId,
          balance: result['balance'],
          currency: result['currency'] ?? 'IQD',
          isActive: result['isActive'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.parse(
            result['updatedAt'] ?? DateTime.now().toIso8601String(),
          ),
        );
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result['message'];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTransactions({bool loadMore = false}) async {
    // Check if user is still logged in
    final sessionService = SessionService.instance;
    if (!sessionService.isLoggedIn) return;

    final userId = await SessionService.instance.getCurrentUserId();
    if (userId == null || userId == 'anonymous' || userId == 'unknown') return;

    if (!loadMore) {
      setState(() {
        _isLoadingTransactions = true;
      });
    }

    final result = await WalletService.getWalletTransactions(
      userId: userId,
      limit: 10,
      lastKey: loadMore ? (_lastTransactionKey ?? '') : '',
    );

    if (result['success']) {
      setState(() {
        if (loadMore) {
          _transactions.addAll(result['transactions']);
        } else {
          _transactions = result['transactions'];
        }
        _lastTransactionKey = result['lastKey'];
        _hasMoreTransactions = result['hasMore'];
        _isLoadingTransactions = false;
      });
    } else {
      setState(() {
        _isLoadingTransactions = false;
      });
    }
  }

  Future<void> _refreshWallet() async {
    await _loadWalletBalance();
    await _loadTransactions();
  }

  void _navigateToTopUp() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => WalletTopUpScreen(
              currentBalance: _wallet?.balance ?? 0,
              currency: _wallet?.currency ?? 'IQD',
            ),
      ),
    );

    if (result == true) {
      // Refresh wallet after successful top-up
      await _refreshWallet();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WalletTransferGate(
      check:
          () async =>
              (await WalletTransferService().call('context'))['canTransfer'] ==
              true,
      builder:
          (transfersEnabled) => Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: AppBar(
              title: const Text(
                'محفظتي',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00296B),
                ),
              ),
              backgroundColor: AppColors.primary,
              elevation: 0,
              actions: [
                if (transfersEnabled)
                  IconButton(
                    tooltip: 'التحويل بين المحافظ',
                    icon: const Icon(
                      Icons.swap_horiz,
                      color: AppColors.secondary,
                    ),
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WalletTransferScreen(),
                          ),
                        ),
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: const Color(0xFF00296B),
                  ),
                  onPressed: _refreshWallet,
                ),
              ],
            ),
            body:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage.isNotEmpty
                    ? _buildErrorWidget()
                    : RefreshIndicator(
                      onRefresh: _refreshWallet,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildWalletCard(),
                            const SizedBox(height: 24),
                            _buildActionButtons(),
                            if (transfersEnabled)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder:
                                            (_) => const WalletTransferScreen(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.swap_horiz),
                                  label: const Text('التحويل بين المحافظ'),
                                ),
                              ),
                            const SizedBox(height: 24),
                            _buildTransactionsSection(),
                          ],
                        ),
                      ),
                    ),
          ),
    );
  }

  Widget _buildErrorWidget() {
    // Special handling for login required
    if (_errorMessage == 'login_required') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  size: 64,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'مرحباً بك في محفظة زاد',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'للوصول إلى محفظتك الرقمية وإدارة رصيدك\nيرجى تسجيل الدخول أولاً',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'مميزات محفظة زاد:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• دفع آمن وسريع بالدينار العراقي\n• تتبع جميع معاملاتك\n• شحن المحفظة بسهولة\n• استخدام الرصيد في الطلبات',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                    if (result == true) {
                      _initializeWallet();
                    }
                  },
                  icon: const Icon(Icons.login),
                  label: const Text(
                    'تسجيل الدخول',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // General error handling
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _initializeWallet,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: const Color(0xFF00296B),
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'رصيد المحفظة',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_wallet?.isActive == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'نشطة',
                    style: TextStyle(color: AppColors.secondary, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _wallet?.getFormattedBalance() ?? '0.00 USD',
            style: const TextStyle(
              color: AppColors.secondary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'آخر تحديث: ${_getFormattedUpdateTime()}',
            style: TextStyle(
              color: AppColors.secondary.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.add,
            label: 'شحن المحفظة',
            onTap: _navigateToTopUp,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionButton(
            icon: Icons.history,
            label: 'سجل المعاملات',
            onTap: () => _showAllTransactions(),
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'المعاملات الأخيرة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_transactions.isNotEmpty)
              TextButton(
                onPressed: _showAllTransactions,
                child: const Text('عرض الكل'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingTransactions)
          const Center(child: CircularProgressIndicator())
        else if (_transactions.isEmpty)
          _buildEmptyTransactions()
        else
          ..._transactions.take(5).map(_buildTransactionItem),
        if (_hasMoreTransactions && _transactions.length >= 5)
          TextButton(
            onPressed: _showAllTransactions,
            child: const Text('عرض المزيد'),
          ),
      ],
    );
  }

  Widget _buildEmptyTransactions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'لا توجد معاملات حتى الآن',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'قم بشحن محفظتك لبدء استخدامها',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(WalletTransactionModel transaction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          _buildTransactionIcon(transaction),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.displayType,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  transaction.getRelativeTime(),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                transaction.displayAmount,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color:
                      transaction.isPositiveTransaction
                          ? Colors.green
                          : transaction.isNegativeTransaction
                          ? Colors.red
                          : Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              _buildStatusChip(transaction.status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionIcon(WalletTransactionModel transaction) {
    IconData iconData;
    Color iconColor;

    switch (transaction.type) {
      case TransactionType.topup:
      case TransactionType.topupSuccess:
        iconData = Icons.add_circle;
        iconColor = Colors.green;
        break;
      case TransactionType.spend:
        iconData = Icons.remove_circle;
        iconColor = Colors.red;
        break;
      case TransactionType.refund:
        iconData = Icons.replay_circle_filled;
        iconColor = Colors.blue;
        break;
      default:
        iconData = Icons.account_balance_wallet;
        iconColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: iconColor, size: 24),
    );
  }

  Widget _buildStatusChip(TransactionStatus status) {
    Color color;
    String text;

    switch (status) {
      case TransactionStatus.success:
        color = Colors.green;
        text = 'مكتملة';
        break;
      case TransactionStatus.pending:
        color = AppColors.primary;
        text = 'في الانتظار';
        break;
      case TransactionStatus.failed:
        color = Colors.red;
        text = 'فاشلة';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getFormattedUpdateTime() {
    if (_wallet?.updatedAt == null) return '';

    final now = DateTime.now();
    final difference = now.difference(_wallet!.updatedAt);

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

  void _showAllTransactions() {
    // TODO: Navigate to full transactions screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('سيتم تطوير شاشة المعاملات الكاملة قريباً')),
    );
  }
}
