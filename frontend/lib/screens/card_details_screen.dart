import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:flutter/services.dart';

class CardDetailsScreen extends StatefulWidget {
  final Function(Map<String, String>) onCardVerified;

  const CardDetailsScreen({
    super.key,
    required this.onCardVerified,
  });

  @override
  State<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends State<CardDetailsScreen>
    with SingleTickerProviderStateMixin {
  
  // Controllers
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _cardHolderController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  
  // Focus nodes
  final FocusNode _cardNumberFocus = FocusNode();
  final FocusNode _cardHolderFocus = FocusNode();
  final FocusNode _expiryFocus = FocusNode();
  final FocusNode _cvvFocus = FocusNode();
  
  // State variables
  bool _isVerifying = false;
  String _cardType = '';
  bool _isCardValid = false;
  String? _errorMessage;
  
  // Animation controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  // ألوان التطبيق
  static const Color _primaryColor = AppColors.primary;
  static const Color _successColor = Color(0xFF40E0B0);
  static const Color _errorColor = Color(0xFFF26B8A);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupListeners();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _animationController.forward();
  }

  void _setupListeners() {
    _cardNumberController.addListener(_validateCard);
    _cardHolderController.addListener(_validateForm);
    _expiryController.addListener(_validateForm);
    _cvvController.addListener(_validateForm);
  }

  void _validateCard() {
    final cardNumber = _cardNumberController.text.replaceAll(' ', '');
    setState(() {
      _cardType = _getCardType(cardNumber);
      _validateForm();
    });
  }

  void _validateForm() {
    final cardNumber = _cardNumberController.text.replaceAll(' ', '');
    final cardHolder = _cardHolderController.text.trim();
    final expiry = _expiryController.text;
    final cvv = _cvvController.text;
    
    setState(() {
      _isCardValid = cardNumber.length >= 13 &&
          cardHolder.isNotEmpty &&
          expiry.length == 5 &&
          cvv.length >= 3;
      _errorMessage = null;
    });
  }

  String _getCardType(String cardNumber) {
    if (cardNumber.startsWith('4')) return 'Visa';
    if (cardNumber.startsWith('5') || cardNumber.startsWith('2')) return 'Mastercard';
    if (cardNumber.startsWith('3')) return 'American Express';
    if (cardNumber.startsWith('6')) return 'Discover';
    return 'Unknown';
  }

  IconData _getCardIcon(String cardType) {
    switch (cardType) {
      case 'Visa':
        return Icons.credit_card;
      case 'Mastercard':
        return Icons.credit_card;
      case 'American Express':
        return Icons.credit_card;
      default:
        return Icons.credit_card_outlined;
    }
  }

  Color _getCardColor(String cardType) {
    switch (cardType) {
      case 'Visa':
        return const Color(0xFF1A1F71);
      case 'Mastercard':
        return const Color(0xFFEB001B);
      case 'American Express':
        return const Color(0xFF006FCF);
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _cardNumberFocus.dispose();
    _cardHolderFocus.dispose();
    _expiryFocus.dispose();
    _cvvFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: _buildAppBar(),
        body: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildBody(),
              ),
            );
          },
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
      ),
      title: const Text(
        'معلومات البطاقة المصرفية',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Preview
          _buildCardPreview(),
          const SizedBox(height: 32),
          
          // Card Form
          _buildCardForm(),
          const SizedBox(height: 24),
          
          // Security Notice
          _buildSecurityNotice(),
          const SizedBox(height: 100), // Space for bottom button
        ],
      ),
    );
  }

  Widget _buildCardPreview() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _cardType.isNotEmpty ? _getCardColor(_cardType) : _primaryColor,
            _cardType.isNotEmpty ? _getCardColor(_cardType).withValues(alpha: 0.8) : _primaryColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _cardType.isNotEmpty ? _cardType : 'بطاقة مصرفية',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _getCardIcon(_cardType),
                  color: Colors.white,
                  size: 32,
                ),
              ],
            ),
            const Spacer(),
            Text(
              _cardNumberController.text.isNotEmpty 
                  ? _formatCardNumber(_cardNumberController.text)
                  : '•••• •••• •••• ••••',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'اسم حامل البطاقة',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      _cardHolderController.text.isNotEmpty 
                          ? _cardHolderController.text.toUpperCase()
                          : 'اسم حامل البطاقة',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'تاريخ الانتهاء',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      _expiryController.text.isNotEmpty 
                          ? _expiryController.text
                          : 'MM/YY',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Number
          _buildInputField(
            label: 'رقم البطاقة',
            controller: _cardNumberController,
            focusNode: _cardNumberFocus,
            hintText: '1234 5678 9012 3456',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _CardNumberFormatter(),
            ],
            prefixIcon: Icon(
              _getCardIcon(_cardType),
              color: _cardType.isNotEmpty ? _getCardColor(_cardType) : Colors.grey,
            ),
            onFieldSubmitted: (_) => _cardHolderFocus.requestFocus(),
          ),
          
          const SizedBox(height: 20),
          
          // Cardholder Name
          _buildInputField(
            label: 'اسم حامل البطاقة',
            controller: _cardHolderController,
            focusNode: _cardHolderFocus,
            hintText: 'مثال: أحمد محمد علي',
            keyboardType: TextInputType.text,
            prefixIcon: const Icon(Icons.person_outline),
            onFieldSubmitted: (_) => _expiryFocus.requestFocus(),
          ),
          
          const SizedBox(height: 20),
          
          // Expiry and CVV
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  label: 'تاريخ الانتهاء',
                  controller: _expiryController,
                  focusNode: _expiryFocus,
                  hintText: 'MM/YY',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _ExpiryDateFormatter(),
                  ],
                  prefixIcon: const Icon(Icons.calendar_month),
                  onFieldSubmitted: (_) => _cvvFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInputField(
                  label: 'CVV',
                  controller: _cvvController,
                  focusNode: _cvvFocus,
                  hintText: '123',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  prefixIcon: const Icon(Icons.lock_outline),
                  obscureText: true,
                ),
              ),
            ],
          ),
          
          // Error message
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _errorColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: _errorColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: _errorColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextInputType keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? prefixIcon,
    bool obscureText = false,
    Function(String)? onFieldSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          onSubmitted: onFieldSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _successColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _successColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.security, color: _successColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'معلوماتك آمنة',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _successColor,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'نحن نستخدم تشفير SSL لحماية بياناتك المصرفية',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isCardValid && !_isVerifying ? _verifyCard : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isCardValid ? _primaryColor : Colors.grey[400],
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: _isCardValid ? 2 : 0,
            ),
            child: _isVerifying
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'جارٍ التحقق...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'التحقق من البطاقة',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String _formatCardNumber(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      buffer.write(input[i]);
      final nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != input.length) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  Future<void> _verifyCard() async {
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      // تجهيز البيانات للإرسال إلى Backend
      // ignore: unused_local_variable
      final cardData = {
        'card_number': _cardNumberController.text.replaceAll(' ', ''),
        'expiry_month': int.parse(_expiryController.text.split('/')[0]),
        'expiry_year': int.parse('20${_expiryController.text.split('/')[1]}'),
        'cvv': _cvvController.text,
        'cardholder_name': _cardHolderController.text.trim(),
        'card_type': _cardType,
      };

      // TODO: إرسال البيانات إلى FastAPI Backend
      // استبدل هذا التعليق بالكود التالي عند ربط Backend:
      // 
      // final response = await http.post(
      //   Uri.parse('${BaseURL}/api/payments/verify-card'),
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'Authorization': 'Bearer $userToken',
      //   },
      //   body: json.encode(cardData), // <- استخدام cardData هنا
      // );
      // 
      // final responseData = json.decode(response.body);
      // if (response.statusCode == 200 && responseData['success']) {
      //   // معالجة الاستجابة الناجحة
      // } else {
      //   // معالجة الخطأ
      // }
      
      // محاكاة استجابة ناجحة للوقت الحالي (احذف هذا القسم عند ربط Backend)
      await Future.delayed(const Duration(seconds: 2));
      
      // ملاحظة: cardData جاهز للإرسال إلى Backend عند التطبيق
      
      // محاكاة استجابة Backend (احذف هذا عند ربط Backend الحقيقي)
      final mockResponse = {
        'success': true,
        'message': 'تم التحقق من البطاقة بنجاح',
        'transaction_id': 'TXN_${DateTime.now().millisecondsSinceEpoch}',
      };

      if (mockResponse['success'] == true) {
        // البطاقة صالحة - إرجاع البيانات للشاشة الرئيسية
        widget.onCardVerified({
          'cardNumber': _maskCardNumber(_cardNumberController.text),
          'cardType': _cardType,
          'cardHolder': _cardHolderController.text,
          'isVerified': 'true',
          'transactionId': mockResponse['transaction_id'] as String,
        });
        
        // إظهار رسالة نجاح
        _showSuccessDialog();
      } else {
        // البطاقة غير صالحة
        setState(() {
          _errorMessage = mockResponse['message'] as String? ?? 'فشل في التحقق من البطاقة';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ في الاتصال بالخادم: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  String _maskCardNumber(String cardNumber) {
    final clean = cardNumber.replaceAll(' ', '');
    if (clean.length < 4) return cardNumber;
    return '**** **** **** ${clean.substring(clean.length - 4)}';
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _successColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: _successColor,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'تم التحقق بنجاح!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'تم التحقق من صحة بيانات البطاقة المصرفية',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // إغلاق الـ dialog
              Navigator.pop(context); // العودة لشاشة تأكيد الطلب
            },
            child: const Text(
              'موافق',
              style: TextStyle(
                color: _primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Card Number Formatter
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.length > 19) return oldValue;

    final buffer = StringBuffer();
    for (int i = 0; i < newText.length; i++) {
      buffer.write(newText[i]);
      final nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != newText.length) {
        buffer.write(' ');
      }
    }

    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

// Expiry Date Formatter
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.length > 5) return oldValue;

    final buffer = StringBuffer();
    for (int i = 0; i < newText.length; i++) {
      buffer.write(newText[i]);
      if (i == 1 && newText.length > 2) {
        buffer.write('/');
      }
    }

    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}
