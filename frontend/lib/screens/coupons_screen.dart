import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:flutter/services.dart';
import '../services/user_service.dart';

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  late TabController _tabController;
  final TextEditingController _couponController = TextEditingController();
  bool _isAddingCoupon = false;

  // ألوان التطبيق - اللون الأساسي الموحد
  static const Color _primaryColor = AppColors.primary;
  static const Color _primaryDark = Color(0xFF0099B8);
  static const Color _primaryLight = Color(0xFFE6F9FC);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _userService.addListener(_onUserDataChanged);
    _userService.checkExpiredCoupons();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _couponController.dispose();
    _userService.removeListener(_onUserDataChanged);
    super.dispose();
  }

  void _onUserDataChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.grey[50],
        body: Column(
          children: [
          // Header Section
          _buildHeader(),
          // Content Section with TabBar and TabBarView
          Expanded(
            child: _buildContent(),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _primaryColor,
            _primaryColor.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'قسائم الخصم',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // To balance the back button
                ],
              ),
            ),
            // Add Coupon Section
            _buildAddCouponSection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAddCouponSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'أضف قسيمة خصم',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _couponController,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'أدخل كود القسيمة',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _isAddingCoupon ? null : _addCoupon,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      child: _isAddingCoupon
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _primaryColor,
                              ),
                            )
                          : const Icon(
                              Icons.add,
                              color: _primaryColor,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Tab Bar
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TabBar(
              controller: _tabController,
              labelColor: _primaryColor,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: _primaryColor,
              indicatorWeight: 3,
              isScrollable: false,
              tabAlignment: TabAlignment.fill,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_offer, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'صالحة (${_userService.validCoupons.length})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'مستخدمة (${_userService.usedCoupons.length})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'منتهية (${_userService.expiredCoupons.length})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tab Bar View
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildValidCouponsTab(),
                _buildUsedCouponsTab(),
                _buildExpiredCouponsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidCouponsTab() {
    final validCoupons = _userService.validCoupons;
    
    if (validCoupons.isEmpty) {
      return _buildEmptyState(
        icon: Icons.local_offer_outlined,
        title: 'لا توجد قسائم صالحة',
        subtitle: 'أضف قسيمة خصم جديدة أو اكسب نقاط من شاشة المكافآت',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: validCoupons.length,
      itemBuilder: (context, index) {
        final coupon = validCoupons[index];
        return _buildCouponCard(coupon, 'valid');
      },
    );
  }

  Widget _buildUsedCouponsTab() {
    final usedCoupons = _userService.usedCoupons;
    
    if (usedCoupons.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'لا توجد قسائم مستخدمة',
        subtitle: 'القسائم التي تستخدمها ستظهر هنا',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: usedCoupons.length,
      itemBuilder: (context, index) {
        final coupon = usedCoupons[index];
        return _buildCouponCard(coupon, 'used');
      },
    );
  }

  Widget _buildExpiredCouponsTab() {
    final expiredCoupons = _userService.expiredCoupons;
    
    if (expiredCoupons.isEmpty) {
      return _buildEmptyState(
        icon: Icons.schedule_outlined,
        title: 'لا توجد قسائم منتهية الصلاحية',
        subtitle: 'القسائم المنتهية الصلاحية ستظهر هنا',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: expiredCoupons.length,
      itemBuilder: (context, index) {
        final coupon = expiredCoupons[index];
        return _buildCouponCard(coupon, 'expired');
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon, String status) {
    final isValid = status == 'valid';
    final isUsed = status == 'used';

    Color borderColor;
    Color backgroundColor;
    Color textColor;
    IconData statusIcon;

    if (isValid) {
      borderColor = _primaryColor;
      backgroundColor = _primaryLight;
      textColor = _primaryDark;
      statusIcon = Icons.local_offer;
    } else if (isUsed) {
      borderColor = Colors.blue;
      backgroundColor = Colors.blue.withValues(alpha: 0.1);
      textColor = Colors.blue;
      statusIcon = Icons.check_circle;
    } else {
      borderColor = Colors.grey;
      backgroundColor = Colors.grey.withValues(alpha: 0.1);
      textColor = Colors.grey;
      statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isValid ? () => _showCouponDetails(coupon) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: textColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coupon['title'] ?? 'قسيمة خصم',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          coupon['description'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: textColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      coupon['discount'] ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.code, color: Colors.grey, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        coupon['code'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                        if (isValid)
                      InkWell(
                        onTap: () => _copyCouponCode(coupon['code'] ?? ''),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.copy,
                            color: _primaryColor,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, color: textColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'ينتهي في: ${coupon['expiry']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.8),
                    ),
                  ),
                  const Spacer(),
                  if (coupon['minOrder'] != null && coupon['minOrder'] > 0)
                    Text(
                      'الحد الأدنى: ${coupon['minOrder']} ر.س',
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) {
      _showSnackBar('يرجى إدخال كود القسيمة', isError: true);
      return;
    }

    setState(() {
      _isAddingCoupon = true;
    });

    try {
      final success = await _userService.addCoupon(code);
      if (success) {
        _couponController.clear();
        _showSnackBar('تم إضافة القسيمة بنجاح!');
      } else {
        _showSnackBar('كود القسيمة غير صحيح أو منتهي الصلاحية', isError: true);
      }
    } catch (e) {
      _showSnackBar('حدث خطأ أثناء إضافة القسيمة', isError: true);
    } finally {
      setState(() {
        _isAddingCoupon = false;
      });
    }
  }

  void _copyCouponCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _showSnackBar('تم نسخ كود القسيمة');
  }

  void _showCouponDetails(Map<String, dynamic> coupon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildCouponDetailsSheet(coupon),
    );
  }

  Widget _buildCouponDetailsSheet(Map<String, dynamic> coupon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_offer,
                  color: _primaryDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coupon['title'] ?? 'قسيمة خصم',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      coupon['description'] ?? '',
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
          const SizedBox(height: 24),
          _buildDetailRow('كود القسيمة', coupon['code'] ?? ''),
          _buildDetailRow('قيمة الخصم', coupon['discount'] ?? ''),
          _buildDetailRow('تاريخ الانتهاء', coupon['expiry'] ?? ''),
          if (coupon['minOrder'] != null && coupon['minOrder'] > 0)
            _buildDetailRow('الحد الأدنى للطلب', '${coupon['minOrder']} ر.س'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _copyCouponCode(coupon['code'] ?? '');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'نسخ كود القسيمة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}