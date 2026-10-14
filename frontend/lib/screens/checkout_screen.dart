// lib/screens/checkout_screen.dart
import '../constants/app_colors.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../models/address_model.dart';
import '../models/store_discount.dart';
import '../providers/app_state_provider.dart';
import '../services/address_service.dart';
import '../services/session_service.dart';
import '../services/order_service.dart';
import '../services/business_status_service.dart';
import 'order_tracking_screen.dart';
import 'address_selection_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final String? storeId;
  final String? storeName;

  const CheckoutScreen({
    super.key,
    this.storeId,
    this.storeName,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final OrderService _orderService = OrderService();
  
  DetailedAddress? _selectedAddress;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  String _deliveryInstructions = '';
  bool _isLoading = false;

  // Merchant discounts
  List<StoreDiscount> _availableDiscounts = [];
  String? _selectedDiscountId;
  double _discount = 0.0;
  bool _isLoadingDiscounts = false;
  bool _isValidatingDiscount = false;

  // Platform promo code
  final TextEditingController _promoCodeController = TextEditingController();
  String? _appliedPromoCode;

  // Kept separately so a failed switch between discount types
  // restores the previously applied amount instead of wiping it
  double _promoDiscountAmount = 0.0;
  double _merchantDiscountAmount = 0.0;
  
  // User information for checkout
  bool _isGuestUser = false;
  String _guestName = '';
  String _guestPhone = '';
  String _guestEmail = '';
  
  // User login type detection
  bool _isLoggedInWithEmail = false;
  bool _isLoggedInWithPhone = false;
  String _userExistingEmail = '';
  String _userExistingPhone = '';
  
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _guestNameController = TextEditingController();
  final TextEditingController _guestPhoneController = TextEditingController();
  final TextEditingController _guestEmailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // تأخير تهيئة البيانات لتحسين الأداء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeUserData();
      _loadStoreDiscounts();
      _autoApplyPendingPromo();
    });
  }

  /// If the user tapped a promo code on the home-screen floating card,
  /// it is stored as pending — prefill and apply it automatically here.
  Future<void> _autoApplyPendingPromo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('pending_promo_code');
      if (code == null || code.isEmpty || !mounted) return;
      _promoCodeController.text = code;
      await _applyPromoCode();
      await prefs.remove('pending_promo_code');
    } catch (_) {}
  }

  Future<void> _loadStoreDiscounts() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final storeId = widget.storeId ??
        (appState.cartItems.isNotEmpty ? appState.cartItems.first['store_id'] : null);
    if (storeId == null || storeId.toString().isEmpty) return;

    setState(() {
      _isLoadingDiscounts = true;
    });

    final discounts = await _orderService.getStoreDiscounts(storeId.toString());

    if (mounted) {
      setState(() {
        _availableDiscounts = discounts;
        _isLoadingDiscounts = false;
      });
    }
  }

  Future<void> _applyPromoCode() async {
    final code = _promoCodeController.text.trim();
    if (code.isEmpty) {
      _showMessage('أدخل كود الخصم أولاً', isError: true);
      return;
    }

    final appState = Provider.of<AppStateProvider>(context, listen: false);

    setState(() {
      _isValidatingDiscount = true;
    });

    final result = await _orderService.validatePromoCode(
      code: code,
      orderTotal: appState.cartTotal,
      deliveryFee: 10.0,
    );

    if (!mounted) return;

    setState(() {
      _isValidatingDiscount = false;
      if (result['valid'] == true) {
        _appliedPromoCode = code;
        _promoDiscountAmount = (result['discount'] as num?)?.toDouble() ?? 0.0;
        _discount = _promoDiscountAmount;
        // Only one discount per order: clear any selected merchant discount
        _selectedDiscountId = null;
        _merchantDiscountAmount = 0.0;
      } else {
        _appliedPromoCode = null;
        _promoDiscountAmount = 0.0;
        _discount = _merchantDiscountAmount;
      }
    });

    if (result['valid'] == true) {
      _showMessage('تم تطبيق كود الخصم بنجاح');
    } else {
      _showMessage(result['message'] ?? 'كود الخصم غير صالح', isError: true);
    }
  }

  void _clearPromoCode() {
    setState(() {
      _appliedPromoCode = null;
      _promoCodeController.clear();
      _promoDiscountAmount = 0.0;
      _discount = _merchantDiscountAmount;
    });
  }

  Future<void> _selectDiscount(StoreDiscount? discount) async {
    if (discount == null) {
      setState(() {
        _selectedDiscountId = null;
        _merchantDiscountAmount = 0.0;
        _discount = _promoDiscountAmount;
      });
      return;
    }

    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final storeId = widget.storeId ??
        (appState.cartItems.isNotEmpty ? appState.cartItems.first['store_id'] : null);
    if (storeId == null) return;

    setState(() {
      _isValidatingDiscount = true;
    });

    final result = await _orderService.validateDiscount(
      storeId: storeId.toString(),
      discountId: discount.discountId,
      orderTotal: appState.cartTotal,
      deliveryFee: 10.0,
      items: appState.cartItems,
    );

    if (!mounted) return;

    setState(() {
      _isValidatingDiscount = false;
      if (result['valid'] == true) {
        _selectedDiscountId = discount.discountId;
        _merchantDiscountAmount = (result['discount'] as num?)?.toDouble() ?? 0.0;
        _discount = _merchantDiscountAmount;
        // Only one discount per order: clear any applied promo code
        _appliedPromoCode = null;
        _promoDiscountAmount = 0.0;
        _promoCodeController.clear();
      } else {
        // Keep the previously applied promo code and its amount —
        // only the failed merchant discount is rejected
        _selectedDiscountId = null;
        _merchantDiscountAmount = 0.0;
        _discount = _promoDiscountAmount;
      }
    });

    if (result['valid'] == true) {
      _showMessage('تم تطبيق الخصم بنجاح');
    } else {
      _showMessage(result['message'] ?? 'الخصم غير صالح', isError: true);
    }
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _guestEmailController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  Future<void> _initializeUserData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Check if user is logged in
      final sessionService = SessionService.instance;
      
      if (sessionService.isLoggedIn && sessionService.currentUser != null) {
        // Logged in user - determine login method and load their info
        _isGuestUser = false;
        final currentUser = sessionService.currentUser!;
        
        // Detect login method based on user data
        final userEmail = currentUser['email'] ?? currentUser['userEmail'] ?? '';
        final userPhone = currentUser['phone'] ?? currentUser['userPhone'] ?? '';
        
        if (userEmail.isNotEmpty && userPhone.isNotEmpty) {
          // User has both - need to determine primary login method
          // For now, assume email is primary if it exists
          _isLoggedInWithEmail = true;
          _userExistingEmail = userEmail;
          _guestEmailController.text = userEmail;
        } else if (userEmail.isNotEmpty) {
          // Logged in with email
          _isLoggedInWithEmail = true;
          _userExistingEmail = userEmail;
          _guestEmailController.text = userEmail;
        } else if (userPhone.isNotEmpty) {
          // Logged in with phone
          _isLoggedInWithPhone = true;
          _userExistingPhone = userPhone;
          _guestPhoneController.text = userPhone;
        }
        
        // Set user name if available
        final userName = currentUser['name'] ?? currentUser['userName'] ?? '';
        if (userName.isNotEmpty) {
          _guestNameController.text = userName;
          _guestName = userName;
        }
        
        // Load user address asynchronously without blocking UI
        _loadUserAddress();
      } else {
        // Guest user - need to collect information manually
        _isGuestUser = true;
      }
    } catch (e) {
      debugPrint('خطأ في تهيئة بيانات المستخدم: $e');
      _isGuestUser = true;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserAddress() async {
    try {
      final addressService = Provider.of<EnhancedAddressService>(context, listen: false);
      
      // تحميل العناوين بشكل غير متزامن لعدم حجب واجهة المستخدم
      await addressService.fetchAddresses();
      
      if (mounted && addressService.defaultAddress != null) {
        setState(() {
          _selectedAddress = addressService.defaultAddress;
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل العنوان: $e');
      // If no saved addresses, the user will need to add one
      // لا نحتاج لعرض خطأ للمستخدم هنا، فقط سيضطر لإضافة عنوان جديد
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'إتمام الطلب',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? _buildLoadingWidget()
          : Consumer<AppStateProvider>(
              builder: (context, appState, child) {
                if (appState.cartItems.isEmpty) {
                  return const Center(
                    child: Text('السلة فارغة'),
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(), // تحسين الأداء
                        padding: const EdgeInsets.all(16),
                        child: Form( // إضافة Form widget
                          key: _formKey,
                          child: RepaintBoundary( // تجنب إعادة رسم غير ضرورية
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                              // قسم معلومات الطلب - مع تحسين الأداء
                              RepaintBoundary(
                                child: _buildOrderSummary(appState),
                              ),
                              const SizedBox(height: 16),
                              
                              // قسم معلومات المستخدم - مع تحسين الأداء
                              RepaintBoundary(
                                child: _isGuestUser 
                                    ? _buildGuestInfoSection()
                                    : _buildLoggedInUserInfoSection(),
                              ),
                              const SizedBox(height: 16),
                              
                              // قسم العنوان
                              RepaintBoundary(
                                child: _buildAddressSection(),
                              ),
                              const SizedBox(height: 16),
                              
                              // قسم طريقة الدفع
                              RepaintBoundary(
                                child: _buildPaymentSection(),
                              ),
                              const SizedBox(height: 16),

                              // قسم العروض والخصومات
                              RepaintBoundary(
                                child: _buildDiscountsSection(),
                              ),
                              const SizedBox(height: 16),
                              
                              // قسم تعليمات التوصيل
                              RepaintBoundary(
                                child: _buildInstructionsSection(),
                              ),
                              const SizedBox(height: 16),
                              
                              // ملخص السعر
                              RepaintBoundary(
                                child: _buildPriceSummary(appState),
                              ),
                              const SizedBox(height: 100), // مساحة للزر السفلي
                            ],
                          ),
                        ),
                      ),
                      ),
                    ),
                    
                    // زر تأكيد الطلب
                    _buildConfirmButton(appState),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.primary,
          ),
          SizedBox(height: 16),
          Text(
            'جاري التحميل...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(AppStateProvider appState) {
    final itemCount = appState.cartItems.length;
    final totalQuantity = appState.cartItems.fold<int>(
      0, 
      (sum, item) => sum + (item['quantity'] as int? ?? 1),
    );

    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shopping_bag,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.storeName ?? 'المطعم',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '$itemCount أطباق ($totalQuantity قطعة)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'عنوان التوصيل',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              if (_selectedAddress != null)
                TextButton(
                  onPressed: _selectAddress,
                  child: const Text(
                    'تغيير',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Show selected address if available
          if (_selectedAddress != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _selectedAddress!.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (_selectedAddress!.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'افتراضي',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // عرض العنوان الكامل للضيوف أو الأجزاء المنفصلة للمستخدمين المسجلين
                    _selectedAddress!.fullAddress.isNotEmpty && 
                    (_selectedAddress!.province.isEmpty || _selectedAddress!.district.isEmpty || _selectedAddress!.neighborhood.isEmpty)
                      ? _selectedAddress!.fullAddress
                      : '${_selectedAddress!.province} - ${_selectedAddress!.district} - ${_selectedAddress!.neighborhood}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (_selectedAddress!.detailedAddress?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      _selectedAddress!.detailedAddress ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  if (_selectedAddress!.landmark.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.place,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'قرب ${_selectedAddress!.landmark}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            )
          else
            // No address selected - show appropriate action
            _buildNoAddressWidget(),
        ],
      ),
    );
  }

  Widget _buildNoAddressWidget() {
    if (_isGuestUser) {
      // Guest user - needs to add address manually
      return GestureDetector(
        onTap: _addNewAddress,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.add_location_alt,
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(height: 8),
              const Text(
                'أضف عنوان التوصيل',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'يرجى إضافة عنوانك لإتمام الطلب',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Logged in user with no saved addresses
      return GestureDetector(
        onTap: _selectAddress,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.add_location_alt,
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(height: 8),
              const Text(
                'اختر أو أضف عنوان',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'اختر من عناوينك المحفوظة أو أضف عنوان جديد',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildPaymentSection() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
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
                'طريقة الدفع',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: PaymentMethod.values.map((method) {
              return RadioListTile<PaymentMethod>(
                value: method,
                groupValue: _selectedPaymentMethod,
                onChanged: method.isEnabled ? (value) {
                  setState(() {
                    _selectedPaymentMethod = value!;
                  });
                } : null,
                title: Row(
                  children: [
                    Text(
                      method.arabicName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: method.isEnabled ? Colors.black87 : Colors.grey,
                      ),
                    ),
                    if (!method.isEnabled) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          'قريباً',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountsSection() {
    if (_isLoadingDiscounts) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_offer,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'العروض والخصومات',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (_isValidatingDiscount) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Promo code entry (platform codes from the central platform)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoCodeController,
                  enabled: _appliedPromoCode == null && !_isValidatingDiscount,
                  decoration: InputDecoration(
                    hintText: 'أدخل كود الخصم',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isValidatingDiscount
                    ? null
                    : (_appliedPromoCode != null ? _clearPromoCode : _applyPromoCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(_appliedPromoCode != null ? 'إزالة' : 'تطبيق'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._availableDiscounts.map((discount) {
            return RadioListTile<String>(
              value: discount.discountId,
              groupValue: _selectedDiscountId,
              onChanged: _isValidatingDiscount
                  ? null
                  : (_) => _selectDiscount(discount),
              title: Text(
                discount.title.isNotEmpty ? discount.title : discount.displayValue,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              subtitle: Text(
                discount.description.isNotEmpty
                    ? discount.description
                    : discount.displayValue,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            );
          }),
          if (_selectedDiscountId != null) ...[
            TextButton(
              onPressed: _isValidatingDiscount ? null : () => _selectDiscount(null),
              child: const Text(
                'إزالة الخصم',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ],
          if (_discount > 0) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'تم تطبيق خصم ${_discount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
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

  Widget _buildInstructionsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.note_add,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'تعليمات التوصيل',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructionsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'أي تعليمات خاصة للسائق؟ (اختياري)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (value) {
              _deliveryInstructions = value;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSummary(AppStateProvider appState) {
    final subtotal = appState.cartTotal;
    const deliveryFee = 10.0;
    final discount = _discount;
    final total = subtotal + deliveryFee - discount;

    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'ملخص الفاتورة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المجموع الفرعي'),
              Text('${subtotal.toStringAsFixed(2)} ر.س'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('رسوم التوصيل'),
              Text('${deliveryFee.toStringAsFixed(2)} ر.س'),
            ],
          ),
          if (discount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الخصم',
                  style: TextStyle(color: Colors.green),
                ),
                Text(
                  '-${discount.toStringAsFixed(2)} ر.س',
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ),
          ],
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'المجموع الكلي',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${total.toStringAsFixed(2)} ر.س',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton(AppStateProvider appState) {
    final subtotal = appState.cartTotal;
    const deliveryFee = 10.0;
    final discount = _discount;
    final total = subtotal + deliveryFee - discount;
    final bool canConfirm = _selectedAddress != null && !_isLoading;

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
            onPressed: canConfirm ? () => _confirmOrder(appState) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canConfirm 
                  ? AppColors.primary 
                  : Colors.grey[400],
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: canConfirm ? 2 : 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'تأكيد الطلب • ${total.toStringAsFixed(2)} ر.س',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // Guest user information section
  Widget _buildGuestInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'معلوماتك الشخصية',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Name field
          TextFormField(
            controller: _guestNameController,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل *',
              hintText: 'ادخل اسمك الكامل',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              _guestName = value; // إزالة setState لتحسين الأداء
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'يرجى إدخال الاسم الكامل';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          
          // Phone field
          TextFormField(
            controller: _guestPhoneController,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'رقم الهاتف *',
              hintText: '+964XXXXXXXXX',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              _guestPhone = value; // إزالة setState لتحسين الأداء
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'يرجى إدخال رقم الهاتف';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          
          // Email field (optional)
          TextFormField(
            controller: _guestEmailController,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'البريد الإلكتروني (اختياري)',
              hintText: 'example@email.com',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              _guestEmail = value; // إزالة setState لتحسين الأداء
            },
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                  return 'البريد الإلكتروني غير صحيح';
                }
              }
              return null;
            },
          ),
          
          const SizedBox(height: 12),
          
          // Login suggestion
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'لتجربة أفضل',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'سجل دخولك لحفظ معلوماتك وعناوينك',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to login screen
                    if (!mounted) return;
                    Navigator.pushNamed(context, '/login');
                  },
                  child: const Text(
                    'تسجيل دخول',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Logged in user information section
  Widget _buildLoggedInUserInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.verified_user,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'معلومات الاتصال',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'مسجل دخول',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Name field (always shown for logged in users)
          TextField(
            controller: _guestNameController,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: Colors.grey.withValues(alpha: 0.05),
            ),
            readOnly: true,
            onChanged: (value) {
              setState(() {
                _guestName = value;
              });
            },
          ),
          const SizedBox(height: 12),
          
          // Show appropriate fields based on login method
          if (_isLoggedInWithEmail) ...[
            // User logged in with email - show email (readonly) and phone (required)
            TextField(
              controller: _guestEmailController,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'البريد الإلكتروني',
                prefixIcon: const Icon(Icons.email_outlined),
                suffixIcon: const Icon(Icons.verified, color: Colors.green, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 12),
            
            // Phone field (required)
            TextField(
              controller: _guestPhoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف *',
                hintText: '+964XXXXXXXXX',
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _guestPhone = value;
                });
              },
            ),
          ] else if (_isLoggedInWithPhone) ...[
            // User logged in with phone - show phone (readonly) and email (optional)
            TextField(
              controller: _guestPhoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف',
                prefixIcon: const Icon(Icons.phone_outlined),
                suffixIcon: const Icon(Icons.verified, color: Colors.green, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 12),
            
            // Email field (optional)
            TextField(
              controller: _guestEmailController,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'البريد الإلكتروني (اختياري)',
                hintText: 'example@email.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _guestEmail = value;
                });
              },
            ),
          ],
          
          const SizedBox(height: 12),
          
          // Info message
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تم التحقق من هويتك',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        _isLoggedInWithEmail 
                            ? 'تسجيل الدخول بالبريد الإلكتروني - يرجى إضافة رقم الهاتف'
                            : 'تسجيل الدخول برقم الهاتف - يمكنك إضافة البريد الإلكتروني (اختياري)',
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
        ],
      ),
    );
  }  void _selectAddress() async {
    if (_isGuestUser) {
      // For guest users, go directly to add new address
      _addNewAddress();
      return;
    }

    final selectedAddress = await Navigator.push<DetailedAddress>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressSelectionScreen(
          currentAddress: _selectedAddress,
        ),
      ),
    );

    if (selectedAddress != null) {
      setState(() {
        _selectedAddress = selectedAddress;
      });
    }
  }

  void _addNewAddress() {
    // Navigate to address form screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيتم فتح نموذج إضافة عنوان جديد'),
        backgroundColor: AppColors.primary,
      ),
    );
    
    // TODO: Navigate to address form screen
    // For now, create a simple address form dialog
    _showAddAddressDialog();
  }  void _showAddAddressDialog() {
    final addressController = TextEditingController();
    final landmarkController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('أضف عنوان التوصيل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: addressController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'العنوان الكامل *',
                    hintText: 'اكتب عنوانك كما تريد: مثل شارع فلسطين، الكرخ، بغداد أو أي طريقة تفضلها',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: landmarkController,
                  decoration: const InputDecoration(
                    labelText: 'أقرب نقطة دليلية (اختياري)',
                    hintText: 'مثل: قرب مطعم الصادق، بجانب الصيدلية، أمام المدرسة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.place),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ملاحظة: يمكنك كتابة العنوان بأي طريقة تريدها، لا حاجة لتقسيمه إلى أجزاء',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final fullAddress = addressController.text.trim();
                final landmark = landmarkController.text.trim();
                
                if (fullAddress.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('يرجى إدخال العنوان الكامل'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // إنشاء عنوان مؤقت للضيف بصيغة مبسطة
                final guestAddress = DetailedAddress(
                  id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
                  userId: 'guest',
                  name: 'عنوان الضيف',
                  province: '', // لا نحتاج تقسيم العنوان
                  district: '',
                  neighborhood: '',
                  landmark: landmark.isNotEmpty ? landmark : '',
                  fullAddress: fullAddress, // نحفظ العنوان كما أدخله المستخدم
                  addressType: AddressType.other,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                
                setState(() {
                  _selectedAddress = guestAddress;
                });
                
                Navigator.of(context).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حفظ العنوان بنجاح'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }



  Future<void> _confirmOrder(AppStateProvider appState) async {
    // التحقق من صحة النموذج أولاً
    if (!_formKey.currentState!.validate()) {
      _showMessage('يرجى تعبئة جميع الحقول المطلوبة بشكل صحيح', isError: true);
      return;
    }
    
    // فحص حالة المطعم أولاً
    if (widget.storeId != null) {
      final businessStatusData = await BusinessStatusService.getBusinessStatus(widget.storeId!);
      
      if (businessStatusData != null) {
        final canAcceptOrders = businessStatusData['isOpen'] as bool? ?? false;
        final statusMessage = businessStatusData['message'] as String? ?? '';
        
        if (!canAcceptOrders) {
          _showMessage(
            statusMessage.isNotEmpty 
              ? statusMessage 
              : 'المطعم غير متاح حالياً لاستقبال الطلبات',
            isError: true
          );
          return;
        }
      }
    }

    // التحقق من العنوان
    if (_selectedAddress == null) {
      _showMessage('يرجى اختيار عنوان التوصيل', isError: true);
      return;
    }

    // التحقق البسيط من العنوان فقط
    if (_selectedAddress!.fullAddress.trim().isEmpty || 
        _selectedAddress!.fullAddress == 'العنوان غير مكتمل' ||
        _selectedAddress!.fullAddress == 'عنوان غير محدد') {
      _showMessage('يرجى إضافة أو اختيار عنوان صحيح للتوصيل', isError: true);
      return;
    }

    // إذا وصلنا هنا، العنوان صحيح ومكتمل
    _createOrderWithAddress(appState);
  }

  Future<void> _createOrderWithAddress(AppStateProvider appState) async {
    // التحقق من معلومات المستخدم
    if (_isGuestUser) {
      // التحقق من معلومات الضيف
      if (_guestName.trim().isEmpty) {
        _showMessage('يرجى إدخال اسمك الكامل', isError: true);
        return;
      }
      if (_guestPhone.trim().isEmpty) {
        _showMessage('يرجى إدخال رقم هاتفك', isError: true);
        return;
      }
    } else {
      // التحقق من معلومات المستخدم المسجل
      if (_isLoggedInWithEmail && _guestPhone.trim().isEmpty) {
        _showMessage('يرجى إدخال رقم هاتفك (مطلوب)', isError: true);
        return;
      }
      // للمستخدمين المسجلين برقم الهاتف، البريد الإلكتروني اختياري
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // تحضير بيانات المستخدم
      String? userId;
      String? customerName;
      String? customerPhone;
      String? customerEmail;

      if (_isGuestUser) {
        // مستخدم ضيف - استخدام البيانات المدخلة يدوياً
        userId = null; // null للضيوف
        customerName = _guestName.trim();
        customerPhone = _guestPhone.trim();
        customerEmail = _guestEmail.trim().isNotEmpty ? _guestEmail.trim() : null;
      } else {
        // مستخدم مسجل - جمع البيانات بناءً على طريقة تسجيل الدخول
        final sessionService = SessionService.instance;
        final currentUser = sessionService.currentUser;
        
        userId = sessionService.currentUserId;
        customerName = _guestName.trim().isNotEmpty ? _guestName.trim() : 
                      (currentUser?['name'] ?? currentUser?['full_name'] ?? 'مستخدم');
        
        if (_isLoggedInWithEmail) {
          // مسجل بالإيميل - استخدام الإيميل المحفوظ ورقم الهاتف المدخل
          customerEmail = _userExistingEmail;
          customerPhone = _guestPhone.trim();
        } else if (_isLoggedInWithPhone) {
          // مسجل برقم الهاتف - استخدام رقم الهاتف المحفوظ والإيميل المدخل (إن وجد)
          customerPhone = _userExistingPhone;
          customerEmail = _guestEmail.trim().isNotEmpty ? _guestEmail.trim() : null;
        } else {
          // حالة افتراضية
          customerPhone = _guestPhone.trim().isNotEmpty ? _guestPhone.trim() : 
                         (currentUser?['phone'] ?? _selectedAddress!.phoneNumber);
          customerEmail = _guestEmail.trim().isNotEmpty ? _guestEmail.trim() : 
                         currentUser?['email'];
        }
      }

      // التحقق من البيانات المطلوبة قبل الإرسال
      if (customerName == null || customerName.trim().isEmpty) {
        _showMessage('خطأ: اسم العميل مطلوب', isError: true);
        return;
      }
      if (customerPhone == null || customerPhone.trim().isEmpty) {
        _showMessage('خطأ: رقم هاتف العميل مطلوب', isError: true);
        return;
      }

      // التحقق من صحة البيانات
      final storeId = widget.storeId ?? (appState.cartItems.isNotEmpty ? appState.cartItems.first['store_id'] : null);
      final storeName = widget.storeName ?? (appState.cartItems.isNotEmpty ? appState.cartItems.first['store_name'] : null);
      
      // الحصول على عنوان المطعم من بيانات السلة
      String storeAddress = 'العنوان غير محدد';
      if (appState.cartItems.isNotEmpty) {
        final firstItem = appState.cartItems.first;
        storeAddress = firstItem['store_address'] as String? ?? 'العنوان غير محدد';
        
        // طباعة عنوان المطعم للتشخيص
        print('🛒 CheckoutScreen - بيانات السلة:');
        print('  عدد الأصناف: ${appState.cartItems.length}');
        print('  عنوان المطعم من السلة: "$storeAddress"');
      }
      
      if (storeId == null || storeId.isEmpty) {
        _showMessage('خطأ: معرف المطعم غير موجود', isError: true);
        return;
      }
      
      if (appState.cartItems.isEmpty) {
        _showMessage('خطأ: السلة فارغة', isError: true);
        return;
      }

      print('CheckoutScreen: Creating order with data:');
      print('- Store ID: $storeId');
      print('- Store Name: $storeName');
      print('- Customer Name: $customerName');
      print('- Customer Phone: $customerPhone');
      print('- Customer Email: $customerEmail');
      print('- User ID: $userId');
      print('- Cart Items Count: ${appState.cartItems.length}');

      // الحصول على صورة المطعم من بيانات السلة
      String? storeImage;
      if (appState.cartItems.isNotEmpty) {
        final firstItem = appState.cartItems.first;
        storeImage = firstItem['store_image'] as String?;
        print('🏪 CheckoutScreen - تفاصيل صورة المطعم:');
        print('  - storeImage من السلة: "$storeImage"');
        print('  - storeImage length: ${storeImage?.length ?? 0}');
        print('  - storeImage isEmpty: ${storeImage?.isEmpty ?? true}');
        print('  - firstItem keys: ${firstItem.keys.toList()}');
        if (firstItem.containsKey('store_image')) {
          print('  - store_image value type: ${firstItem['store_image'].runtimeType}');
        }
      }

      final result = await _orderService.createOrder(
        storeId: storeId,
        storeName: storeName ?? 'المطعم',
        storeAddress: storeAddress, // عنوان المطعم للسائقين
        storeImage: storeImage, // صورة المطعم للسائقين
        cartItems: appState.cartItems,
        deliveryAddress: _selectedAddress!,
        paymentMethod: _selectedPaymentMethod,
        deliveryInstructions: _deliveryInstructions.isEmpty ? null : _deliveryInstructions,
        promoCode: _appliedPromoCode,
        discountId: _selectedDiscountId,
        discount: _discount,
        // إضافة معلومات المستخدم الحقيقية
        userId: userId,
        customerName: customerName,
        customerPhone: customerPhone,
        customerEmail: customerEmail,
      );

      print('CheckoutScreen: Order creation result: $result');

      if (result['success']) {
        final order = result['order'] as OrderModel;
        
        // إضافة الطلب للقائمة المحلية في OrderService
        _orderService.addOrderToList(order);
        
        // مسح السلة
        appState.clearCart();
        
        // الانتقال لشاشة تتبع الطلب
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OrderTrackingScreen(
              orderId: order.id,
              orderNumber: order.orderNumber,
            ),
          ),
        );
      } else {
        _showMessage(result['message'] ?? 'فشل في إنشاء الطلب', isError: true);
      }
    } on TimeoutException catch (_) {
      _showMessage('انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى', isError: true);
    } on FormatException catch (_) {
      _showMessage('خطأ في تنسيق البيانات - يرجى المحاولة مرة أخرى', isError: true);
    } catch (e) {
      String errorMessage;
      final eStr = e.toString();
      if (eStr.isEmpty || eStr == '{}' || eStr == '{().toString()}' || eStr == 'null') {
        errorMessage = 'خطأ في إنشاء الطلب - يرجى المحاولة مرة أخرى';
      } else {
        errorMessage = 'خطأ في إنشاء الطلب: $eStr';
      }
      _showMessage(errorMessage, isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }





}
