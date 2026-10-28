import '../utils/currency_format.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:flutter/services.dart';

class PaymentScreen extends StatefulWidget {
  final double totalAmount;
  final String orderSummary;
  final VoidCallback onPaymentSuccess;

  const PaymentScreen({
    super.key,
    required this.totalAmount,
    required this.orderSummary,
    required this.onPaymentSuccess,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedPaymentMethod = 0; // 0: بطاقة مصرفية، 1: محفظة رقمية، 2: نقداً عند التسليم
  
  // بيانات البطاقة المصرفية
  final _cardNameController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  
  // بيانات المحفظة الرقمية
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  
  // معلومات العميل
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();
  
  bool _isProcessing = false;
  String? _cardType;
  
  // ألوان التطبيق
  static const Color _primaryColor = AppColors.primary;
  static const Color _secondaryColor = Color(0xFFe91e63);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cardNameController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.payment,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'إتمام الدفع',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: _primaryColor,
          foregroundColor: AppColors.secondary,
          elevation: 3,
          shadowColor: _primaryColor.withValues(alpha: 0.3),
        ),
        body: Column(
          children: [
            // ملخص الطلب
            _buildOrderSummary(),
            
            // معلومات العميل
            _buildCustomerInfo(),
            
            // طرق الدفع
            Expanded(
              child: Column(
                children: [
                  _buildPaymentMethodTabs(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCreditCardForm(),
                        _buildDigitalWalletForm(),
                        _buildCashOnDeliveryForm(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildPaymentButton(),
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.receipt_long,
                    color: _primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'ملخص الطلب',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${formatIqd(widget.totalAmount)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.orderSummary,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _secondaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person,
                    color: _secondaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'معلومات العميل',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _customerNameController,
                    label: 'الاسم كاملاً',
                    icon: Icons.person_outline,
                    inputType: TextInputType.name,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _customerPhoneController,
                    label: 'رقم الهاتف',
                    icon: Icons.phone,
                    inputType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _customerEmailController,
              label: 'البريد الإلكتروني (اختياري)',
              icon: Icons.email_outlined,
              inputType: TextInputType.emailAddress,
              isRequired: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodTabs() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.payment,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'اختر طريقة الدفع',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            onTap: (index) {
              setState(() {
                _selectedPaymentMethod = index;
              });
            },
            labelColor: _primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _primaryColor,
            indicatorWeight: 3,
            tabs: const [
              Tab(
                icon: Icon(Icons.credit_card),
                text: 'بطاقة مصرفية',
              ),
              Tab(
                icon: Icon(Icons.account_balance_wallet),
                text: 'محفظة رقمية',
              ),
              Tab(
                icon: Icon(Icons.money),
                text: 'نقداً عند التسليم',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditCardForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // بطاقة تمثيلية
              _buildCreditCard(),
              
              const SizedBox(height: 24),
              
              // اسم حامل البطاقة
              _buildTextField(
                controller: _cardNameController,
                label: 'اسم حامل البطاقة',
                icon: Icons.person_outline,
                inputType: TextInputType.name,
              ),
              
              const SizedBox(height: 16),
              
              // رقم البطاقة
              _buildTextField(
                controller: _cardNumberController,
                label: 'رقم البطاقة',
                icon: Icons.credit_card,
                inputType: TextInputType.number,
                maxLength: 19,
                formatter: [_CardNumberFormatter()],
                onChanged: (value) {
                  setState(() {
                    _cardType = _getCardType(value);
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // تاريخ الانتهاء و CVV
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _expiryController,
                      label: 'تاريخ الانتهاء',
                      icon: Icons.calendar_today,
                      inputType: TextInputType.number,
                      placeholder: 'MM/YY',
                      maxLength: 5,
                      formatter: [_ExpiryDateFormatter()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _cvvController,
                      label: 'رمز CVV',
                      icon: Icons.security,
                      inputType: TextInputType.number,
                      maxLength: 4,
                      isObscure: true,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // ملاحظة الأمان
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.security,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'جميع المعاملات محمية بتشفير SSL 256-bit',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDigitalWalletForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // أيقونات المحافظ الرقمية
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildWalletOption('زين كاش', Icons.phone_android, Colors.purple),
                  _buildWalletOption('آسيا باي', Icons.account_balance_wallet, Colors.blue),
                  _buildWalletOption('الكي كارد', Icons.credit_card, AppColors.primary),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // رقم الهاتف
              _buildTextField(
                controller: _phoneController,
                label: 'رقم الهاتف المربوط بالمحفظة',
                icon: Icons.phone,
                inputType: TextInputType.phone,
                placeholder: '07xxxxxxxx',
              ),
              
              const SizedBox(height: 16),
              
              // رمز PIN
              _buildTextField(
                controller: _pinController,
                label: 'رمز PIN',
                icon: Icons.lock_outline,
                inputType: TextInputType.number,
                maxLength: 6,
                isObscure: true,
              ),
              
              const SizedBox(height: 16),
              
              // ملاحظة
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'سيتم إرسال رمز تأكيد إلى رقم هاتفك',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCashOnDeliveryForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // أيقونة كبيرة
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.money,
                  color: Colors.green,
                  size: 48,
                ),
              ),
              
              const SizedBox(height: 24),
              
              const Text(
                'الدفع نقداً عند التسليم',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              
              const SizedBox(height: 12),
              
              Text(
                'ادفع نقداً للسائق عند استلام طلبك',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 24),
              
              // معلومات مهمة
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'معلومات مهمة',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• تأكد من توفر المبلغ كاملاً مع السائق\n'
                      '• يُفضل إحضار فئات صغيرة لتسهيل عملية الدفع\n'
                      '• في حالة عدم توفر المبلغ سيتم إلغاء الطلب',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // المبلغ المطلوب
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'المبلغ المطلوب:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${formatIqd(widget.totalAmount)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    bool isObscure = false,
    bool isRequired = true,
    String? placeholder,
    int? maxLength,
    List<TextInputFormatter>? formatter,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      obscureText: isObscure,
      maxLength: maxLength,
      inputFormatters: formatter,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        hintText: placeholder,
        prefixIcon: Icon(icon, color: _primaryColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
        counterText: '',
        suffixIcon: _cardType != null && controller == _cardNumberController
            ? Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.asset(
                  _getCardImage(_cardType!),
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) => 
                      Icon(Icons.credit_card, color: Colors.grey[400]),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildCreditCard() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryColor,
            _primaryColor.withValues(alpha: 0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'بطاقة مصرفية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_cardType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _cardType!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              _cardNumberController.text.isEmpty 
                  ? '**** **** **** ****'
                  : _cardNumberController.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
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
                      _cardNameController.text.isEmpty 
                          ? 'اسم حامل البطاقة'
                          : _cardNameController.text.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'صالحة حتى',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      _expiryController.text.isEmpty 
                          ? 'MM/YY'
                          : _expiryController.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
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

  Widget _buildWalletOption(String name, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 32,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ملخص سريع
            if (_selectedPaymentMethod != 2)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedPaymentMethod == 0 
                          ? 'دفع بالبطاقة المصرفية'
                          : 'دفع بالمحفظة الرقمية',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${formatIqd(widget.totalAmount)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 12),
            
            // زر الدفع
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                  shadowColor: _primaryColor.withValues(alpha: 0.3),
                ),
                onPressed: _isProcessing ? null : _processPayment,
                child: _isProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'جارٍ المعالجة...',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _selectedPaymentMethod == 2 
                                ? Icons.check_circle
                                : Icons.payment,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _selectedPaymentMethod == 2
                                ? 'تأكيد الطلب'
                                : 'ادفع الآن ${formatIqd(widget.totalAmount)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _processPayment() async {
    if (!_validateForm()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // محاكاة معالجة الدفع
      await Future.delayed(const Duration(seconds: 3));

      if (_selectedPaymentMethod == 0) {
        // معالجة البطاقة المصرفية
        if (_validateCard()) {
          _showSuccessDialog();
        } else {
          _showErrorDialog('بيانات البطاقة غير صحيحة');
        }
      } else if (_selectedPaymentMethod == 1) {
        // معالجة المحفظة الرقمية
        _showSuccessDialog();
      } else {
        // نقداً عند التسليم
        _showSuccessDialog();
      }
    } catch (e) {
      _showErrorDialog('حدث خطأ أثناء معالجة الدفع');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  bool _validateForm() {
    if (_customerNameController.text.trim().isEmpty ||
        _customerPhoneController.text.trim().isEmpty) {
      _showErrorDialog('يرجى إكمال معلومات العميل');
      return false;
    }

    if (_selectedPaymentMethod == 0) {
      if (_cardNameController.text.trim().isEmpty ||
          _cardNumberController.text.trim().isEmpty ||
          _expiryController.text.trim().isEmpty ||
          _cvvController.text.trim().isEmpty) {
        _showErrorDialog('يرجى إكمال بيانات البطاقة');
        return false;
      }
    } else if (_selectedPaymentMethod == 1) {
      if (_phoneController.text.trim().isEmpty ||
          _pinController.text.trim().isEmpty) {
        _showErrorDialog('يرجى إكمال بيانات المحفظة الرقمية');
        return false;
      }
    }

    return true;
  }

  bool _validateCard() {
    final cardNumber = _cardNumberController.text.replaceAll(' ', '');
    return _validateCardLuhn(cardNumber) && 
           _validateExpiryDate(_expiryController.text) &&
           _cvvController.text.length >= 3;
  }

  bool _validateCardLuhn(String cardNumber) {
    if (cardNumber.length < 13 || cardNumber.length > 19) return false;
    
    int sum = 0;
    bool alternate = false;
    
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int n = int.parse(cardNumber[i]);
      
      if (alternate) {
        n *= 2;
        if (n > 9) n = (n % 10) + 1;
      }
      
      sum += n;
      alternate = !alternate;
    }
    
    return sum % 10 == 0;
  }

  bool _validateExpiryDate(String expiry) {
    if (expiry.length != 5) return false;
    
    final parts = expiry.split('/');
    if (parts.length != 2) return false;
    
    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);
    
    if (month == null || year == null) return false;
    if (month < 1 || month > 12) return false;
    
    final now = DateTime.now();
    final currentYear = now.year % 100;
    final currentMonth = now.month;
    
    if (year < currentYear) return false;
    if (year == currentYear && month < currentMonth) return false;
    
    return true;
  }

  String? _getCardType(String cardNumber) {
    cardNumber = cardNumber.replaceAll(' ', '');
    
    if (cardNumber.startsWith('4')) return 'Visa';
    if (cardNumber.startsWith(RegExp(r'5[1-5]'))) return 'MasterCard';
    if (cardNumber.startsWith(RegExp(r'3[47]'))) return 'American Express';
    if (cardNumber.startsWith('6011')) return 'Discover';
    
    return null;
  }

  String _getCardImage(String cardType) {
    switch (cardType) {
      case 'Visa':
        return 'assets/visa.png';
      case 'MasterCard':
        return 'assets/mastercard.png';
      case 'American Express':
        return 'assets/amex.png';
      default:
        return 'assets/card.png';
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'تم الدفع بنجاح!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'شكراً لك! تم استلام دفعتك بنجاح وسيتم التواصل معك قريباً لتأكيد التفاصيل.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تفاصيل الدفع:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('المبلغ: ${formatIqd(widget.totalAmount)}'),
                  Text('الطريقة: ${_getPaymentMethodName()}'),
                  Text('التاريخ: ${DateTime.now().toString().substring(0, 16)}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // إغلاق الحوار
              widget.onPaymentSuccess(); // استدعاء callback النجاح
            },
            child: const Text(
              'حسناً',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'خطأ في الدفع',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'حسناً',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPaymentMethodName() {
    switch (_selectedPaymentMethod) {
      case 0:
        return 'بطاقة مصرفية';
      case 1:
        return 'محفظة رقمية';
      case 2:
        return 'نقداً عند التسليم';
      default:
        return 'غير محدد';
    }
  }
}

// Formatters للحقول
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(text[i]);
    }
    
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('/', '');
    
    if (text.length >= 2) {
      return TextEditingValue(
        text: '${text.substring(0, 2)}/${text.substring(2)}',
        selection: TextSelection.collapsed(offset: newValue.text.length),
      );
    }
    
    return newValue;
  }
}
