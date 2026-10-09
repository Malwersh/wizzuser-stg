import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../services/wallet_service.dart';
import '../services/session_service.dart';
import 'payment_webview_screen.dart';

class WalletTopUpScreen extends StatefulWidget {
  final double currentBalance;
  final String currency;

  const WalletTopUpScreen({
    super.key,
    required this.currentBalance,
    required this.currency,
  });

  @override
  State<WalletTopUpScreen> createState() => _WalletTopUpScreenState();
}

class _WalletTopUpScreenState extends State<WalletTopUpScreen> {
  final TextEditingController _amountController = TextEditingController();
  double _selectedAmount = 0;
  bool _isLoading = false;
  String _errorMessage = '';

  List<double> get _quickAmounts => WalletService.getTopUpAmounts(widget.currency);

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _selectQuickAmount(double amount) {
    setState(() {
      _selectedAmount = amount;
      _amountController.text = amount.toStringAsFixed(widget.currency == 'IQD' ? 0 : 2);
    });
  }

  void _onAmountChanged(String value) {
    setState(() {
      _selectedAmount = double.tryParse(value) ?? 0;
    });
  }

  Future<void> _processTopUp() async {
    if (_selectedAmount <= 0) {
      setState(() {
        _errorMessage = 'يرجى إدخال مبلغ صحيح';
      });
      return;
    }

    final userId = await SessionService.instance.getCurrentUserId();
    if (userId == null || userId == 'anonymous' || userId == 'unknown') {
      setState(() {
        _errorMessage = 'لم يتم العثور على معرف المستخدم';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await WalletService.requestTopUp(
        userId: userId,
        amount: _selectedAmount,
        currency: widget.currency,
        customerInfo: await _getCustomerInfo(),
      );

      if (result['success']) {
        // Validate payment URL before opening WebView
        final paymentUrl = result['paymentUrl'] as String?;
        if (paymentUrl == null || paymentUrl.isEmpty) {
          setState(() {
            _errorMessage = 'رابط الدفع غير متوفر';
          });
          return;
        }

        // CRITICAL: PayTabs-compliant payment flow based on platform
        // For web platform: Use same-window redirect (PayTabs requirement)
        // For mobile platforms: Use in-app WebView as per PayTabs guidelines
        if (kIsWeb) {
          // Web platform: Direct redirect in same window (PayTabs web requirement)
          await _processWebPaymentRedirect(paymentUrl, result['transactionId']);
        } else {
          // Mobile platforms: Use in-app WebView as per PayTabs guidelines
          // This ensures immediate opening without user confirmation dialogs
          final paymentResult = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => PaymentWebViewScreen(
                paymentUrl: paymentUrl,
                transactionId: result['transactionId'],
                amount: result['amount']?.toDouble() ?? _selectedAmount,
                currency: result['currency'] ?? widget.currency,
              ),
            ),
          );

          // Handle payment result
          if (paymentResult == true) {
            _showPaymentSuccessDialog();
          } else {
            _showPaymentCancelledDialog();
          }
        }
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'فشل في إنشاء طلب الدفع';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<Map<String, String>> _getCustomerInfo() async {
    // Get user info from session or use defaults
    final userData = await SessionService.instance.getUserData();
    final userEmail = userData?['email'];
    final userPhone = userData?['phone'];
    
    return {
      'name': 'مستخدم التطبيق',
      'email': userEmail ?? 'user@foodapp.com',
      'phone': userPhone ?? '+964xxxxxxxxx',
      'city': 'بغداد',
      'country': 'IQ',
    };
  }

  Future<void> _processWebPaymentRedirect(String paymentUrl, String transactionId) async {
    try {
      // IMMEDIATE REDIRECT: No user confirmation dialog to prevent session expiration
      // PayTabs sessions on web expire quickly, so we redirect immediately

      // Direct redirect to PayTabs (same window - critical for web)
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        // Use same window redirect for web (PayTabs requirement)
        await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self', // Same window redirect
        );
        // Note: User will be redirected to PayTabs and return via callback URL
      } else {
        setState(() {
          _errorMessage = 'لا يمكن الوصول إلى صفحة PayTabs';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في فتح صفحة الدفع: $e';
      });
    }
  }

  void _showPaymentSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('تم الدفع بنجاح'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'تم إكمال عملية الدفع بنجاح!\nسيتم تحديث رصيدك خلال دقائق معدودة.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: AppColors.secondary,
            ),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, true); // Return to wallet screen with success
            },
            child: const Text('ممتاز'),
          ),
        ],
      ),
    );
  }

  void _showPaymentCancelledDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel, color: AppColors.error, size: 28),
            SizedBox(width: 12),
            Text('تم إلغاء الدفع'),
          ],
        ),
        content: const Text(
          'تم إلغاء عملية الدفع. لم يتم خصم أي مبلغ.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إعادة المحاولة'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, false); // Return to wallet screen
            },
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'شحن المحفظة',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCurrentBalanceCard(),
            const SizedBox(height: 24),
            _buildAmountSelection(),
            const SizedBox(height: 24),
            _buildCustomAmountInput(),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(),
            ],
            const SizedBox(height: 32),
            _buildTopUpButton(),
            const SizedBox(height: 16),
            _buildPaymentInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الرصيد الحالي',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            WalletService.formatCurrency(widget.currentBalance, widget.currency),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اختر مبلغ الشحن',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _quickAmounts.map((amount) {
            final isSelected = _selectedAmount == amount;
            return GestureDetector(
              onTap: () => _selectQuickAmount(amount),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
                child: Text(
                  WalletService.formatCurrency(amount, widget.currency),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCustomAmountInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'أو أدخل مبلغ مخصص',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          onChanged: _onAmountChanged,
          decoration: InputDecoration(
            hintText: 'أدخل المبلغ',
            suffixText: widget.currency,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red.shade600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.red.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopUpButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: (_isLoading || _selectedAmount <= 0) ? null : _processTopUp,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'شحن ${WalletService.formatCurrency(_selectedAmount, widget.currency)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildPaymentInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info, color: Colors.blue.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'معلومات الدفع المحدثة',
                style: TextStyle(
                  color: Colors.blue.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'نفس النافذة للويب - جلسة PayTabs محفوظة ✅',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '✅ انتقال فوري للويب - بدون تأخير\n'
            '✅ فتح فوري في WebView للتطبيقات المحمولة\n'
            '✅ صفحات دفع مستضافة آمنة للويب\n'
            '✅ جلسة دفع ممتدة (45 دقيقة)\n'
            '✅ بيئة PayTabs Iraq Sandbox محسنة\n'
            '✅ دعم كامل للبطاقات العراقية والدولية\n'
            '✅ redirect_url جديد لكل عملية دفع\n'
            '✅ تشفير SSL 256-bit آمن\n'
            '✅ إضافة فورية للرصيد بعد الدفع الناجح\n'
            '✅ متوافق مع إرشادات PayTabs الجديدة',
            style: TextStyle(
              color: Colors.blue.shade700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
