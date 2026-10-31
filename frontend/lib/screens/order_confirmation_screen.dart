import '../utils/readable_colors.dart';
import '../utils/currency_format.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'payment_screen.dart';
import '../services/user_service.dart';
import '../services/order_service_v2.dart';
import '../models/order_model.dart';
import '../models/address_model.dart';
import 'card_details_screen.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final String address;
  final String city;
  final String area;
  final String district;
  final String landmark;
  final String storeName;
  final int totalDishes;
  final double subtotal;
  final double delivery;
  final double total;
  final String mapAddress;
  final LatLng userLocation;
  final String? storeId; // إضافة معرف المطعم

  const OrderConfirmationScreen({
    super.key,
    required this.address,
    required this.city,
    required this.area,
    required this.district,
    required this.landmark,
    required this.storeName,
    required this.totalDishes,
    required this.subtotal,
    required this.delivery,
    required this.total,
    required this.mapAddress,
    required this.userLocation,
    this.storeId, // معرف المطعم اختياري
  });

  @override
  State<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  late TextEditingController _phoneController;
  late TextEditingController _couponController;

  // متغيرات العنوان الجديدة
  late TextEditingController _governorateController;
  late TextEditingController _districtController;
  late TextEditingController _neighborhoodController;
  late TextEditingController _landmarkController;

  // متغيرات أخرى
  String _selectedPayment = 'cash';

  // خدمة المستخدم للحصول على النقاط الفعلية
  final UserService _userService = UserService();

  // خدمة الطلبات لإنشاء طلب جديد
  final OrderServiceV2 _orderService = OrderServiceV2();

  double _tip = 0.0;

  // متغيرات البطاقة المصرفية والتحقق
  bool _isCardVerified = false;
  Map<String, String>? _verifiedCardData;

  // نظام الخصومات المتقدم
  bool _isUsingPoints = false;
  bool _isUsingCoupon = false;
  double _pointsDiscount = 0.0;
  double _couponDiscount = 0.0;
  Map<String, dynamic>? _appliedCoupon;
  double _selectedPointsValue = 0.0; // متغير الشريط للنقاط
  late TextEditingController _customTipController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: '+964 770 123 4567');
    _couponController = TextEditingController();
    _customTipController = TextEditingController();

    // تهيئة متحكمات العنوان
    _governorateController = TextEditingController(text: widget.city);
    _districtController = TextEditingController(text: widget.area);
    _neighborhoodController = TextEditingController(text: widget.district);
    _landmarkController = TextEditingController(text: widget.landmark);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _couponController.dispose();
    _customTipController.dispose();
    _governorateController.dispose();
    _districtController.dispose();
    _neighborhoodController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: CustomScrollView(
          slivers: [
            // AppBar مع الخريطة
            _buildMapAppBar(),
            // محتوى الشاشة
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildDeliveryInfo(),
                  _buildAddressSection(),
                  _buildPhoneSection(),
                  _buildPaymentMethods(),
                  _buildCouponsAndPoints(),
                  _buildTipSection(),
                  _buildOrderSummary(),
                  const SizedBox(height: 100), // مساحة للزر
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildCheckoutButton(),
      ),
    );
  }

  // AppBar مع الخريطة - تصميم DoorDash
  Widget _buildMapAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      title: const Text(
        'تأكيد الطلب',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          margin: const EdgeInsets.only(top: 80),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.userLocation,
              zoom: 15,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('user_location'),
                position: widget.userLocation,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueBlue,
                ),
                infoWindow: const InfoWindow(title: 'موقع التسليم'),
              ),
            },
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
            liteModeEnabled: true,
          ),
        ),
      ),
    );
  }

  // معلومات التسليم - تصميم DoorDash
  Widget _buildDeliveryInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.access_time,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مدة التسليم المتوقعة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '25-35 دقيقة',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'سريع',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // قسم العنوان - تصميم DoorDash
  Widget _buildAddressSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'عنوان التسليم',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  _showEditAddressDialog();
                },
                icon: const Icon(
                  Icons.edit,
                  size: 16,
                  color: const Color(0xFF00296B),
                ),
                label: const Text(
                  'تعديل',
                  style: TextStyle(
                    color: const Color(0xFF00296B),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.mapAddress,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_governorateController.text}، ${_districtController.text}، ${_neighborhoodController.text}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    if (_landmarkController.text.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _landmarkController.text,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // قسم رقم الهاتف - تصميم DoorDash
  Widget _buildPhoneSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'رقم الهاتف',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: '+964 770 123 4567',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  // طرق الدفع - تصميم DoorDash
  Widget _buildPaymentMethods() {
    return Container(
      margin: const EdgeInsets.all(16),
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
          // نقداً عند التسليم
          _buildPaymentOption(
            'cash',
            'نقداً عند التسليم',
            Icons.money,
            Colors.green,
          ),
          const SizedBox(height: 8),
          // بطاقة مصرفية
          _buildPaymentOption(
            'card',
            'بطاقة مصرفية',
            Icons.credit_card,
            Colors.blue,
          ),
          const SizedBox(height: 8),
          // المحفظة
          _buildPaymentOption(
            'wallet',
            'المحفظة',
            Icons.account_balance_wallet,
            Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(
    String value,
    String title,
    IconData icon,
    Color color,
  ) {
    return GestureDetector(
      onTap: () async {
        if (value == 'card') {
          // Navigate to CardDetailsScreen and handle card verification
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => CardDetailsScreen(
                    onCardVerified: (cardData) {
                      setState(() {
                        _verifiedCardData = cardData;
                        _isCardVerified = true;
                        _selectedPayment = 'card';
                      });
                      Navigator.of(
                        context,
                      ).pop(); // Return to confirmation screen
                      _showSnackBar(
                        'تم تأكيد البطاقة - يمكنك الآن متابعة الطلب',
                        Colors.green,
                      );
                    },
                  ),
            ),
          );
          return;
        }
        setState(() => _selectedPayment = value);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                _selectedPayment == value
                    ? AppColors.primary
                    : Colors.grey.withValues(alpha: 0.3),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
          color:
              _selectedPayment == value
                  ? AppColors.primary.withValues(alpha: 0.05)
                  : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color:
                          _selectedPayment == value
                              ? AppColors.primary
                              : Colors.black87,
                    ),
                  ),
                  if (value == 'cash') ...[
                    const SizedBox(height: 2),
                    Text(
                      'الدفع عند الاستلام',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                  if (value == 'card' && _isCardVerified) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.verified,
                          color: Colors.green,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'تم التحقق - ${_verifiedCardData?['cardNumber'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (value == 'card' && !_isCardVerified) ...[
                    const SizedBox(height: 2),
                    Text(
                      'انقر للتحقق من بيانات البطاقة',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            // أيقونة الحالة
            if (_selectedPayment == value)
              Icon(
                value == 'card' && _isCardVerified
                    ? Icons.check_circle
                    : Icons.check_circle,
                color:
                    value == 'card' && _isCardVerified
                        ? Colors.green
                        : AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  // قسم القسائم والنقاط
  Widget _buildCouponsAndPoints() {
    final validCoupons = _userService.validCoupons;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_offer,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'القسائم والنقاط',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // القسائم المتاحة - عرض أفقي
          if (validCoupons.isNotEmpty) ...[
            const Text(
              'القسائم المتاحة:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: validCoupons.length,
                itemBuilder: (context, index) {
                  final coupon = validCoupons[index];
                  return _buildCouponCard(coupon);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // حقل إدخال كود القسيمة
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  enabled: !_isUsingPoints,
                  decoration: InputDecoration(
                    hintText:
                        _isUsingPoints
                            ? 'يجب إلغاء النقاط أولاً'
                            : 'أدخل رمز القسيمة',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isUsingPoints ? null : _applyCoupon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('تطبيق'),
              ),
            ],
          ),

          // عرض القسيمة المطبقة
          if (_isUsingCoupon && _appliedCoupon != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_offer,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _appliedCoupon!['code'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          Text(
                            'خصم: ${formatIqd(_couponDiscount)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.red,
                        size: 20,
                      ),
                      onPressed: _cancelCoupon,
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // استخدام النقاط
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  _isUsingPoints
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    _isUsingPoints
                        ? AppColors.primary
                        : Colors.grey.withValues(alpha: 0.3),
                width: _isUsingPoints ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.stars, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'استخدم نقاطك',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'لديك ${_userService.currentPoints} نقطة • كل 100 نقطة = 5 ريال خصم',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isUsingPoints,
                      onChanged:
                          _userService.currentPoints >= 100
                              ? (value) {
                                if (value) {
                                  setState(() {
                                    _isUsingPoints = true;
                                    _selectedPointsValue =
                                        100.0; // بدء بأقل قيمة
                                    _updatePointsDiscount();
                                  });
                                } else {
                                  _cancelPointsDiscount();
                                }
                              }
                              : null,
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),

                // الشريط المنزلق للنقاط
                if (_isUsingPoints) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'عدد النقاط المستخدمة:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_selectedPointsValue.toInt()} نقطة',
                                style: const TextStyle(
                                  color: const Color(0xFF00296B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // الشريط المنزلق
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: AppColors.primary.withValues(
                              alpha: 0.3,
                            ),
                            thumbColor: AppColors.primary,
                            overlayColor: AppColors.primary.withValues(
                              alpha: 0.2,
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 10,
                            ),
                            trackHeight: 6,
                          ),
                          child: Slider(
                            value: _selectedPointsValue,
                            min: 100.0,
                            max: _getMaxUsablePoints().toDouble(),
                            divisions: _getSliderDivisions(),
                            onChanged: (value) {
                              setState(() {
                                _selectedPointsValue = value;
                                _updatePointsDiscount();
                              });
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // معلومات إضافية
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '100',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'الخصم: ${formatIqd(_pointsDiscount)}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${_getMaxUsablePoints()}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // معلومات الحالة
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تم استخدام ${_getUsedPoints()} نقطة',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                'خصم: ${formatIqd(_pointsDiscount)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _cancelPointsDiscount,
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // قسم الإكرامية
  Widget _buildTipSection() {
    return Container(
      margin: const EdgeInsets.all(16),
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
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.thumb_up,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'إكرامية السائق',
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
            children: [
              _buildTipOption(0, 'بدون'),
              const SizedBox(width: 8),
              _buildTipOption(2, '2 د.ع'),
              const SizedBox(width: 8),
              _buildTipOption(5, '5 د.ع'),
              const SizedBox(width: 8),
              _buildTipOption(10, '10 د.ع'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipOption(double amount, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tip = amount),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  _tip == amount
                      ? Colors.green
                      : Colors.grey.withValues(alpha: 0.3),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
            color:
                _tip == amount
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.transparent,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _tip == amount ? Colors.green : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  // ملخص الطلب
  Widget _buildOrderSummary() {
    final double totalDiscount = _pointsDiscount + _couponDiscount;
    final double finalTotal = widget.total - totalDiscount + _tip;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  Icons.receipt,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'ملخص الطلب',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSummaryRow(
            'عدد الأطباق (${widget.totalDishes})',
            '${formatIqd(widget.subtotal)}',
          ),
          _buildSummaryRow('رسوم التوصيل', '${formatIqd(widget.delivery)}'),

          // عرض الخصومات منفصلة
          if (_pointsDiscount > 0)
            _buildSummaryRow(
              'خصم النقاط (${_getUsedPoints()} نقطة)',
              '-${formatIqd(_pointsDiscount)}',
              color: Colors.green,
            ),
          if (_couponDiscount > 0)
            _buildSummaryRow(
              'خصم القسيمة (${_appliedCoupon?['code']})',
              '-${formatIqd(_couponDiscount)}',
              color: Colors.green,
            ),

          if (_tip > 0)
            _buildSummaryRow(
              'إكرامية السائق',
              '+${formatIqd(_tip)}',
              color: AppColors.primary,
            ),

          // إظهار إجمالي التوفير إذا كان هناك خصومات
          if (totalDiscount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.savings, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'إجمالي التوفير: ${formatIqd(totalDiscount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 24),
          _buildSummaryRow(
            'المجموع النهائي',
            '${formatIqd(finalTotal)}',
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    Color? color,
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isTotal ? AppColors.primary : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // زر الدفع
  Widget _buildCheckoutButton() {
    final double totalDiscount = _pointsDiscount + _couponDiscount;
    final double finalTotal = widget.total - totalDiscount + _tip;

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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: () {
              if (_phoneController.text.isEmpty) {
                _showSnackBar('يرجى إدخال رقم الهاتف', AppColors.primary);
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => PaymentScreen(
                        totalAmount: finalTotal,
                        orderSummary: _buildOrderSummaryText(),
                        onPaymentSuccess: () => _showOrderSuccessDialog(),
                      ),
                ),
              );
            },
            child: Text(
              'تأكيد الطلب • ${formatIqd(finalTotal)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  // وظائف مساعدة
  void _showEditAddressDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle indicator
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'تعديل عنوان التسليم',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Content
                const Expanded(
                  child: Center(child: Text('تعديل العنوان - قيد التطوير')),
                ),
              ],
            ),
          ),
    );
  }

  // دالة عرض رسائل SnackBar
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // دالة تطبيق القسيمة
  void _applyCoupon() {
    final couponCode = _couponController.text.trim();
    if (couponCode.isEmpty) {
      _showSnackBar('يرجى إدخال رمز القسيمة', AppColors.primary);
      return;
    }

    if (_isUsingPoints) {
      _showSnackBar(
        'يجب إلغاء النقاط أولاً لاستخدام القسيمة',
        AppColors.primary,
      );
      return;
    }

    // البحث عن القسيمة في القائمة المتاحة
    final coupon = _userService.validCoupons.firstWhere(
      (c) => c['code'].toString().toLowerCase() == couponCode.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );

    if (coupon.isNotEmpty) {
      final calculatedDiscount = _calculateCouponDiscount(coupon);
      if (calculatedDiscount > 0) {
        setState(() {
          _isUsingCoupon = true;
          _appliedCoupon = coupon;
          _couponDiscount = calculatedDiscount;

          // إلغاء النقاط إذا كانت مفعلة
          _isUsingPoints = false;
          _pointsDiscount = 0.0;
        });
        _showSnackBar('تم تطبيق القسيمة بنجاح!', Colors.green);
      }
    } else {
      // التحقق من قسائم الاختبار
      final testCoupons = {
        'SAVE10': {
          'discountType': 'fixed',
          'discountValue': 10,
          'minOrder': 25,
          'title': 'خصم 10 ريال',
        },
        'SAVE20': {
          'discountType': 'fixed',
          'discountValue': 20,
          'minOrder': 50,
          'title': 'خصم 20 ريال',
        },
        'PERCENT15': {
          'discountType': 'percentage',
          'discountValue': 15,
          'minOrder': 30,
          'title': 'خصم 15%',
        },
      };

      if (testCoupons.containsKey(couponCode.toUpperCase())) {
        final testCoupon = testCoupons[couponCode.toUpperCase()]!;
        testCoupon['code'] = couponCode.toUpperCase();
        testCoupon['id'] = 'test_${couponCode.toLowerCase()}';

        final calculatedDiscount = _calculateCouponDiscount(testCoupon);
        if (calculatedDiscount > 0) {
          setState(() {
            _isUsingCoupon = true;
            _appliedCoupon = testCoupon;
            _couponDiscount = calculatedDiscount;

            // إلغاء النقاط إذا كانت مفعلة
            _isUsingPoints = false;
            _pointsDiscount = 0.0;
          });
          _showSnackBar('تم تطبيق قسيمة الاختبار بنجاح!', Colors.green);
        }
      } else {
        _showSnackBar('رمز القسيمة غير صحيح', Colors.red);
      }
    }
  }

  // دالة بناء ملخص الطلب كنص
  String _buildOrderSummaryText() {
    final double totalDiscount = _pointsDiscount + _couponDiscount;
    final double finalTotal = widget.total - totalDiscount + _tip;

    String summary =
        'ملخص الطلب:\n'
        'عدد الأطباق: ${widget.totalDishes}\n'
        'السعر الأساسي: ${formatIqd(widget.subtotal)}\n'
        'رسوم التوصيل: ${formatIqd(widget.delivery)}\n';

    if (_pointsDiscount > 0) {
      summary +=
          'خصم النقاط (${_getUsedPoints()} نقطة): -${formatIqd(_pointsDiscount)}\n';
    }

    if (_couponDiscount > 0) {
      summary +=
          'خصم القسيمة (${_appliedCoupon?['code']}): -${formatIqd(_couponDiscount)}\n';
    }

    if (_tip > 0) {
      summary += 'الإكرامية: +${formatIqd(_tip)}\n';
    }

    if (totalDiscount > 0) {
      summary += 'إجمالي التوفير: ${formatIqd(totalDiscount)}\n';
    }

    summary +=
        'المجموع النهائي: ${formatIqd(finalTotal)}\n'
        'طريقة الدفع: ${_getPaymentMethodName()}\n'
        'العنوان: ${widget.mapAddress}\n'
        'الهاتف: ${_phoneController.text}\n'
        'ملاحظات: لا توجد';

    return summary;
  }

  // دالة الحصول على اسم طريقة الدفع
  String _getPaymentMethodName() {
    switch (_selectedPayment) {
      case 'cash':
        return 'نقداً عند التسليم';
      case 'card':
        return _isCardVerified ? 'بطاقة مصرفية (تم التحقق)' : 'بطاقة مصرفية';
      case 'wallet':
        return 'المحفظة';
      default:
        return 'نقداً عند التسليم';
    }
  }

  // دالة إظهار نافذة نجاح الطلب
  void _showOrderSuccessDialog() async {
    // إنشاء الطلب الجديد أولاً
    await _createNewOrder();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text(
                  'تم تأكيد الطلب!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'شكراً لك! تم استلام طلبك بنجاح.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 12),
                Text(
                  '• سيتم التواصل معك قريباً لتأكيد التفاصيل',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  '• يمكنك متابعة حالة الطلب من قسم "طلباتي"',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // إغلاق النافذة
                  Navigator.of(context).pop(); // العودة للشاشة السابقة
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: readableForeground(Colors.green),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'حسناً',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  // دالة إنشاء طلب جديد في النظام
  Future<void> _createNewOrder() async {
    try {
      // إنشاء عنوان للطلب باستخدام DetailedAddress
      final deliveryAddress = DetailedAddress(
        id: 'temp_address_${DateTime.now().millisecondsSinceEpoch}',
        userId: 'current_user',
        name: 'العميل الحالي',
        province: _governorateController.text,
        district: _districtController.text,
        neighborhood: _neighborhoodController.text,
        landmark:
            _landmarkController.text.isNotEmpty
                ? _landmarkController.text
                : 'بدون معلم',
        fullAddress: widget.mapAddress,
        latitude: widget.userLocation.latitude,
        longitude: widget.userLocation.longitude,
        phoneNumber: _phoneController.text,
        addressType: 'home',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // إنشاء عناصر السلة بالتنسيق المطلوب
      final cartItems = _createMockCartItems();

      // إنشاء الطلب الجديد
      final result = await _orderService.createOrder(
        storeId:
            widget.storeId ??
            'store_001', // استخدام معرف المطعم الممرر أو القيمة الافتراضية
        storeName: widget.storeName,
        cartItems: cartItems,
        deliveryAddress: deliveryAddress,
        paymentMethod:
            _selectedPayment == 'cash'
                ? PaymentMethod.cash
                : PaymentMethod.card,
        deliveryFee: widget.delivery,
        taxRate: 0.05, // ضريبة 5%
        discount: _pointsDiscount + _couponDiscount,
        deliveryInstructions: 'طلب من التطبيق',
        userId: 'current_user',
        customerName: 'العميل الحالي',
        customerPhone: _phoneController.text,
      );

      if (result['success'] == true) {
        // يمكن إضافة منطق إضافي هنا مثل إرسال إشعار أو تحديث واجهة المستخدم
      } else {
        print('❌ فشل في إنشاء الطلب: ${result['message']}');
      }
    } catch (e) {
      print('❌ خطأ في إنشاء الطلب: $e');
    }
  }

  // دالة إنشاء عناصر السلة التجريبية بالتنسيق المطلوب
  List<Map<String, dynamic>> _createMockCartItems() {
    return [
      {
        'id': 'item_${DateTime.now().millisecondsSinceEpoch}',
        'name': 'طبق مختار من ${widget.storeName}',
        'price': widget.subtotal / widget.totalDishes,
        'quantity': widget.totalDishes,
        'store_id':
            widget.storeId ?? 'store_001', // استخدام معرف المطعم الحقيقي
        'store_name': widget.storeName,
        'description': 'طبق لذيذ من المطعم',
        'image': '',
      },
    ];
  }

  // الدوال المساعدة المفقودة
  Widget _buildCouponCard(Map<String, dynamic> coupon) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            coupon['code'] ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 4),
          Text(coupon['title'] ?? '', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              _couponController.text = coupon['code'] ?? '';
              _applyCoupon();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: AppColors.secondary,
              minimumSize: const Size(double.infinity, 32),
            ),
            child: const Text('تطبيق', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _cancelCoupon() {
    setState(() {
      _isUsingCoupon = false;
      _appliedCoupon = null;
      _couponDiscount = 0.0;
      _couponController.clear();
    });
  }

  void _updatePointsDiscount() {
    setState(() {
      _pointsDiscount =
          (_selectedPointsValue / 100) * 5; // كل 100 نقطة = 5 ريال
    });
  }

  void _cancelPointsDiscount() {
    setState(() {
      _isUsingPoints = false;
      _selectedPointsValue = 100.0;
      _pointsDiscount = 0.0;
    });
  }

  int _getMaxUsablePoints() {
    // الحد الأقصى للنقاط التي يمكن استخدامها (لا يتجاوز المبلغ الإجمالي)
    final maxPointsForTotal =
        (widget.total * 100 / 5).floor(); // حساب النقاط المطلوبة للمبلغ كاملاً
    return [
      _userService.currentPoints,
      maxPointsForTotal,
      1000,
    ].reduce((a, b) => a < b ? a : b);
  }

  int _getSliderDivisions() {
    final maxPoints = _getMaxUsablePoints();
    return ((maxPoints - 100) / 100).floor();
  }

  int _getUsedPoints() {
    return _selectedPointsValue.toInt();
  }

  double _calculateCouponDiscount(Map<String, dynamic> coupon) {
    final minOrder = coupon['minOrder']?.toDouble() ?? 0.0;
    if (widget.subtotal < minOrder) {
      _showSnackBar(
        'الحد الأدنى للطلب ${formatIqd(minOrder)}',
        AppColors.primary,
      );
      return 0.0;
    }

    if (coupon['discountType'] == 'fixed') {
      return coupon['discountValue']?.toDouble() ?? 0.0;
    } else if (coupon['discountType'] == 'percentage') {
      final percentage = coupon['discountValue']?.toDouble() ?? 0.0;
      return (widget.subtotal * percentage / 100).roundToDouble();
    }

    return 0.0;
  }
}
