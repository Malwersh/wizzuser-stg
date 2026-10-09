import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class UserRewardsPage extends StatefulWidget {
  const UserRewardsPage({super.key});

  @override
  State<UserRewardsPage> createState() => _UserRewardsPageState();
}

class _UserRewardsPageState extends State<UserRewardsPage>
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _pointsAnimationController;
  late AnimationController _progressAnimationController;
  late AnimationController _tabAnimationController;
  late AnimationController _buttonAnimationController;
  late AnimationController _modalAnimationController;
  late AnimationController _cardStaggerAnimationController;
  
  // Animations
  late Animation<int> _pointsAnimation;
  late Animation<double> _progressAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _buttonAnimation;
  late Animation<double> _modalSlideAnimation;
  late Animation<double> _modalFadeAnimation;
  late Animation<double> _cardStaggerAnimation;
  
  // State Variables
  int _currentPoints = 350; // النقاط الحالية (قابلة للتغيير عند الاستبدال)
  final int _targetPoints = 500; // الهدف التالي
  int _selectedTab = 0; // 0: الكل, 1: المكتسبة, 2: المنفقة
  int? _selectedRedemptionOption; // الخيار المحدد في Modal

  // ألوان التطبيق المحسنة - بسيطة ونظيفة
  static const Color _primaryColor = AppColors.primary; // اللون الأساسي للأيقونات والأزرار
  static const Color _accentColor = AppColors.secondary; // اللون الثانوي للتحميل
  static const Color _successColor = AppColors.success;
  static const Color _dangerColor = AppColors.error;
  static const Color _redeemButtonColor = AppColors.primary; // استخدام اللون الأساسي
  static const Color _textPrimary = AppColors.textPrimary; // نص أسود نقي
  static const Color _textSecondary = AppColors.textSecondary; // نص رمادي
  static const Color _textMuted = AppColors.textTertiary; // نص رمادي فاتح
  static const Color _dividerColor = AppColors.divider; // فاصل رمادي فاتح

  // خيارات الاستبدال
  final List<Map<String, dynamic>> _redemptionOptions = [
    {
      'id': 1,
      'title': '50 نقطة → كوبون 3 ر.س',
      'requiredPoints': 50,
      'reward': 'كوبون خصم 3 ر.س',
      'description': 'صالح لمدة 30 يوماً',
      'details': 'يمكن استخدامه على أي طلب بقيمة 15 ر.س أو أكثر',
      'icon': Icons.discount,
      'color': Colors.green,
    },
    {
      'id': 2,
      'title': '100 نقطة → كوبون 7 ر.س',
      'requiredPoints': 100,
      'reward': 'كوبون خصم 7 ر.س',
      'description': 'صالح لمدة 30 يوماً',
      'details': 'يمكن استخدامه على أي طلب بقيمة 25 ر.س أو أكثر',
      'icon': Icons.local_offer,
      'color': Colors.blue,
    },
    {
      'id': 3,
      'title': '150 نقطة → توصيل مجاني',
      'requiredPoints': 150,
      'reward': 'توصيل مجاني',
      'description': 'صالح لمدة 15 يوماً',
      'details': 'مرة واحدة فقط على أي طلب',
      'icon': Icons.delivery_dining,
      'color': AppColors.primary,
    },
    {
      'id': 4,
      'title': '250 نقطة → كوبون 15 ر.س',
      'requiredPoints': 250,
      'reward': 'كوبون خصم 15 ر.س',
      'description': 'صالح لمدة 45 يوماً',
      'details': 'يمكن استخدامه على أي طلب بقيمة 50 ر.س أو أكثر',
      'icon': Icons.card_giftcard,
      'color': Colors.purple,
    },
    {
      'id': 5,
      'title': '400 نقطة → وجبة مجانية',
      'requiredPoints': 400,
      'reward': 'وجبة مجانية',
      'description': 'صالح لمدة 60 يوماً',
      'details': 'وجبة رئيسية من مطعم مختار بقيمة تصل إلى 25 ر.س',
      'icon': Icons.restaurant,
      'color': Colors.red,
    },
  ];

  // بيانات تجريبية لمعاملات النقاط
  final List<Map<String, dynamic>> _allTransactions = [
    {
      'type': 'earned',
      'amount': 120,
      'description': 'عن الطلب #2345',
      'date': '2025-06-10',
      'time': '14:30',
    },
    {
      'type': 'spent',
      'amount': 100,
      'description': 'استبدال قسيمة خصم',
      'date': '2025-06-09',
      'time': '19:45',
    },
    {
      'type': 'earned',
      'amount': 75,
      'description': 'عن الطلب #2344',
      'date': '2025-06-08',
      'time': '12:15',
    },
    {
      'type': 'earned',
      'amount': 200,
      'description': 'مكافأة التسجيل',
      'date': '2025-06-07',
      'time': '10:00',
    },
    {
      'type': 'spent',
      'amount': 150,
      'description': 'استبدال توصيل مجاني',
      'date': '2025-06-06',
      'time': '16:20',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startAnimations();
  }

  void _initializeAnimations() {
    // Animation Controller للنقاط (1000ms مع bounceOut)
    _pointsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Animation Controller للشريط التقدمي (800ms مع easeInOutCubic)
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Animation Controller للتبويبات (200ms fade)
    _tabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Animation Controller للأزرار (100ms opacity)
    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    // Animation Controller للـ Modal (300ms)
    _modalAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Animation Controller للبطاقات المتتابعة (300ms)
    _cardStaggerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500), // وقت أطول للتأثير المتتابع
      vsync: this,
    );

    // الرسوم المتحركة
    _pointsAnimation = IntTween(
      begin: 0,
      end: _currentPoints,
    ).animate(CurvedAnimation(
      parent: _pointsAnimationController,
      curve: Curves.bounceOut,
    ));

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: _currentPoints / _targetPoints,
    ).animate(CurvedAnimation(
      parent: _progressAnimationController,
      curve: Curves.easeInOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tabAnimationController,
      curve: Curves.easeInOut,
    ));

    _buttonAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _buttonAnimationController,
      curve: Curves.easeInOut,
    ));

    // رسوم متحركة للـ Modal
    _modalSlideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _modalAnimationController,
      curve: Curves.easeOutCubic,
    ));

    _modalFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _modalAnimationController,
      curve: Curves.easeInOut,
    ));

    // رسوم متحركة للبطاقات المتتابعة
    _cardStaggerAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _cardStaggerAnimationController,
      curve: Curves.easeOutBack,
    ));
  }

  void _startAnimations() {
    // تشغيل جميع الرسوم المتحركة عند بداية الشاشة
    _pointsAnimationController.forward();
    _progressAnimationController.forward();
    _tabAnimationController.forward();
  }

  @override
  void dispose() {
    _pointsAnimationController.dispose();
    _progressAnimationController.dispose();
    _tabAnimationController.dispose();
    _buttonAnimationController.dispose();
    _modalAnimationController.dispose();
    _cardStaggerAnimationController.dispose();
    super.dispose();
  }

  // فلترة المعاملات حسب التبويب المحدد
  List<Map<String, dynamic>> get _filteredTransactions {
    switch (_selectedTab) {
      case 1: // المكتسبة
        return _allTransactions.where((t) => t['type'] == 'earned').toList();
      case 2: // المنفقة
        return _allTransactions.where((t) => t['type'] == 'spent').toList();
      default: // الكل
        return _allTransactions;
    }
  }

  // دالة تبديل التبويبات مع الرسوم المتحركة
  void _switchTab(int index) {
    setState(() {
      _selectedTab = index;
    });
    _tabAnimationController.reset();
    _tabAnimationController.forward();
  }

  // دالة الاستبدال مع رسوم متحركة ونظام Modal
  void _redeemPoints() async {
    // التحقق من كفاية النقاط
    final minRequiredPoints = _redemptionOptions
        .map((option) => option['requiredPoints'] as int)
        .reduce((a, b) => a < b ? a : b);
    
    if (_currentPoints < minRequiredPoints) {
      _showInsufficientPointsToast();
      return;
    }

    // رسوم متحركة للضغط على الزر
    await _buttonAnimationController.forward();
    await _buttonAnimationController.reverse();
    
    // عرض Modal الاستبدال
    _showRedemptionModal();
  }

  // دالة عرض Toast لعدم كفاية النقاط
  void _showInsufficientPointsToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'رصيدك الحالي ($_currentPoints نقطة) غير كافٍ للاستبدال.',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: _dangerColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // دالة عرض Modal الاستبدال
  void _showRedemptionModal() {
    _selectedRedemptionOption = null;
    _modalAnimationController.reset();
    _cardStaggerAnimationController.reset();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildRedemptionModal(),
    );
    
    _modalAnimationController.forward();
    _cardStaggerAnimationController.forward();
  }

  // بناء Modal الاستبدال
  Widget _buildRedemptionModal() {
    return AnimatedBuilder(
      animation: _modalAnimationController,
      builder: (context, child) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          transform: Matrix4.translationValues(
            0, 
            MediaQuery.of(context).size.height * _modalSlideAnimation.value, 
            0
          ),
          child: Stack(
            children: [
              // Background overlay مع تلاشي
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.5 * _modalFadeAnimation.value),
                  ),
                ),
              ),
              
              // المحتوى الرئيسي
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle bar
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      
                      // عنوان Modal
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(
                              Icons.stars_rounded,
                              color: _primaryColor,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'استبدال النقاط',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '$_currentPoints نقطة',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // خط فاصل
                      const Divider(color: _dividerColor, height: 1),
                      
                      // قائمة خيارات الاستبدال
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _redemptionOptions.length,
                          itemBuilder: (context, index) {
                            return _buildRedemptionOptionCard(index);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // بناء بطاقة خيار الاستبدال
  Widget _buildRedemptionOptionCard(int index) {
    final option = _redemptionOptions[index];
    final isAvailable = _currentPoints >= (option['requiredPoints'] as int);
    final isSelected = _selectedRedemptionOption == option['id'];
    
    return AnimatedBuilder(
      animation: _cardStaggerAnimation,
      builder: (context, child) {
        final cardDelay = index * 0.1;
        final cardProgress = (_cardStaggerAnimation.value - cardDelay).clamp(0.0, 1.0);
        
        return Transform.translate(
          offset: Offset(0, 50 * (1 - cardProgress)),
          child: Opacity(
            opacity: cardProgress,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: isAvailable ? () => _selectRedemptionOption(option) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected 
                          ? _primaryColor 
                          : isAvailable 
                              ? _dividerColor 
                              : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected 
                            ? _primaryColor.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.1),
                        blurRadius: isSelected ? 8 : 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // أيقونة الخيار
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isAvailable 
                                  ? (option['color'] as Color).withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              option['icon'] as IconData,
                              color: isAvailable 
                                  ? option['color'] as Color
                                  : Colors.grey,
                              size: 24,
                            ),
                          ),
                          
                          const SizedBox(width: 12),
                          
                          // تفاصيل الخيار
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option['title'] as String,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isAvailable ? _textPrimary : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  option['description'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isAvailable ? _textMuted : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // زر الاختيار
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isAvailable 
                                  ? _successColor.withValues(alpha: isSelected ? 1.0 : 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              isSelected ? Icons.check : Icons.add,
                              color: isAvailable 
                                  ? (isSelected ? Colors.white : _successColor)
                                  : Colors.grey,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      
                      if (isAvailable) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Text(
                            option['details'] as String,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ],
                      
                      if (!isAvailable) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'تحتاج ${(option['requiredPoints'] as int) - _currentPoints} نقطة إضافية',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // دالة اختيار خيار الاستبدال
  void _selectRedemptionOption(Map<String, dynamic> option) {
    setState(() {
      _selectedRedemptionOption = option['id'] as int;
    });
    
    // عرض dialog التأكيد
    _showConfirmationDialog(option);
  }

  // دالة عرض dialog التأكيد
  void _showConfirmationDialog(Map<String, dynamic> option) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'تأكيد الاستبدال',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل تريد استبدال ${option['requiredPoints']} نقطة بـ ${option['reward']}؟',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'إلغاء',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // إغلاق dialog
              Navigator.pop(context); // إغلاق modal
              _executeRedemption(option);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'تأكيد',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // تنفيذ عملية الاستبدال
  void _executeRedemption(Map<String, dynamic> option) async {
    final requiredPoints = option['requiredPoints'] as int;
    
    // محاكاة API call
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _currentPoints -= requiredPoints;
      
      // إضافة معاملة جديدة للتاريخ
      _allTransactions.insert(0, {
        'type': 'spent',
        'amount': requiredPoints,
        'description': 'استبدال: ${option['reward']}',
        'date': '2025-06-10',
        'time': '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      });
      
      // إعادة تحديث الرسوم المتحركة
      _pointsAnimation = IntTween(
        begin: 0,
        end: _currentPoints,
      ).animate(CurvedAnimation(
        parent: _pointsAnimationController,
        curve: Curves.bounceOut,
      ));
      
      _progressAnimation = Tween<double>(
        begin: 0.0,
        end: _currentPoints / _targetPoints,
      ).animate(CurvedAnimation(
        parent: _progressAnimationController,
        curve: Curves.easeInOutCubic,
      ));
    });
    
    // إعادة تشغيل الرسوم المتحركة
    _pointsAnimationController.reset();
    _progressAnimationController.reset();
    _pointsAnimationController.forward();
    _progressAnimationController.forward();
    
    // عرض Toast نجاح العملية
    _showSuccessToast(option);
  }

  // دالة عرض Toast نجاح العملية
  void _showSuccessToast(Map<String, dynamic> option) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '✅ تم استبدال ${option['requiredPoints']} نقطة وإضافة ${option['reward']} إلى "قسائمي".',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'عرض القسائم',
          textColor: Colors.white,
          onPressed: () {
            // التنقل إلى شاشة القسائم
            Navigator.pushNamed(context, '/coupons');
          },
        ),
      ),
    );
  }

  // دالة عرض حوار المساعدة
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.help_outline,
              color: _primaryColor,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'كيف تعمل المكافآت؟',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• احصل على نقاط مع كل طلب تقوم به',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 8),
            Text(
              '• استبدل النقاط بكوبونات خصم أو عروض مميزة',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 8),
            Text(
              '• كلما زادت طلباتك، زادت نقاطك والمكافآت',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 8),
            Text(
              '• تحقق من تاريخ انتهاء الكوبونات قبل الاستخدام',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'فهمت',
              style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.white,
      body: Container(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // AppBar مخصص يغطي كامل المنطقة العلوية ويطفو تحت شريط الحالة
                _buildCustomAppBar(),
                
                // محتوى الشاشة
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // قسم النقاط والتقدم
                        _buildPointsSection(),
                        
                        const SizedBox(height: 24),
                        
                        // قسم التبويبات
                        _buildTabSection(),
                        
                        const SizedBox(height: 16),
                        
                        // قائمة المعاملات
                        _buildTransactionsList(),
                        
                        const SizedBox(height: 100), // مساحة إضافية للزر العائم
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // زر الاستبدال العائم
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: _buildFloatingRedeemButton(),
            ),
          ],
        ),
      ),
    );
  }

  // AppBar مخصص يغطي كامل المنطقة العلوية ويطفو تحت شريط الحالة
  Widget _buildCustomAppBar() {
    return SliverAppBar(
      expandedHeight: 200 + MediaQuery.of(context).padding.top,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      stretch: true,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_primaryColor, _accentColor],
          ),
        ),
        child: FlexibleSpaceBar(
          centerTitle: true,
          titlePadding: EdgeInsets.only(
            bottom: 16,
            top: MediaQuery.of(context).padding.top,
          ),
          title: const Text(
            'المكافآت',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 3,
                  color: Colors.black26,
                ),
              ],
            ),
          ),
          background: Stack(
            children: [
              // Gradient background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_primaryColor, _accentColor],
                  ),
                ),
              ),
              // Pattern decoration
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.5,
                      colors: [
                        Colors.white.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Star icons background
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                right: 30,
                child: const Icon(
                  Icons.stars_rounded,
                  color: Colors.white12,
                  size: 100,
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 100,
                left: 40,
                child: const Icon(
                  Icons.star_outline,
                  color: Colors.white12,
                  size: 40,
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 80,
                left: 80,
                child: const Icon(
                  Icons.star_half,
                  color: Colors.white12,
                  size: 25,
                ),
              ),
            ],
          ),
        ),
      ),
      leading: Container(
        margin: EdgeInsets.only(
          left: 16,
          top: MediaQuery.of(context).padding.top + 8,
        ),
        child: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 18,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      actions: [
        Container(
          margin: EdgeInsets.only(
            right: 16,
            top: MediaQuery.of(context).padding.top + 8,
          ),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.help_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: _showHelpDialog,
          ),
        ),
      ],
    );
  }

  // قسم النقاط مع الرسوم المتحركة
  Widget _buildPointsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // عرض النقاط مع الرسوم المتحركة
          AnimatedBuilder(
            animation: _pointsAnimation,
            builder: (context, child) {
              return Text(
                '${_pointsAnimation.value}',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              );
            },
          ),
          
          const Text(
            'نقطة متاحة',
            style: TextStyle(
              fontSize: 16,
              color: _textSecondary,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // شريط التقدم مع الرسوم المتحركة
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'التقدم نحو الهدف التالي',
                    style: TextStyle(
                      fontSize: 14,
                      color: _textSecondary,
                    ),
                  ),
                  Text(
                    '$_currentPoints / $_targetPoints',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              AnimatedBuilder(
                animation: _progressAnimation,
                builder: (context, child) {
                  return Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: _dividerColor,
                    ),
                    child: Stack(
                      children: [
                        Container(
                          width: MediaQuery.of(context).size.width * _progressAnimation.value * 0.85,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              colors: [_primaryColor, _accentColor],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryColor.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // قسم التبويبات مع الرسوم المتحركة
  Widget _buildTabSection() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _dividerColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTabButton('الكل', 0),
          _buildTabButton('المكتسبة', 1),
          _buildTabButton('المنفقة', 2),
        ],
      ),
    );
  }

  // زر التبويب مع الرسوم المتحركة
  Widget _buildTabButton(String title, int index) {
    final isSelected = _selectedTab == index;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? _primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : _textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // قائمة المعاملات مع الرسوم المتحركة
  Widget _buildTransactionsList() {
    final transactions = _filteredTransactions;
    
    if (transactions.isEmpty) {
      return _buildEmptyState();
    }
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: transactions.asMap().entries.map((entry) {
          final index = entry.key;
          final transaction = entry.value;
          
          return AnimatedContainer(
            duration: Duration(milliseconds: 200 + (index * 100)),
            margin: const EdgeInsets.only(bottom: 12),
            child: _buildTransactionItem(transaction),
          );
        }).toList(),
      ),
    );
  }

  // عنصر معاملة واحدة
  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final isEarned = transaction['type'] == 'earned';
    final amount = transaction['amount'] as int;
    final description = transaction['description'] as String;
    final date = transaction['date'] as String;
    final time = transaction['time'] as String;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEarned ? _successColor.withValues(alpha: 0.2) : _dangerColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة المعاملة
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (isEarned ? _successColor : _dangerColor).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isEarned ? Icons.add_circle_outline : Icons.remove_circle_outline,
              color: isEarned ? _successColor : _dangerColor,
              size: 24,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // تفاصيل المعاملة
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$date - $time',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          
          // مبلغ النقاط
          Text(
            '${isEarned ? '+' : '-'}$amount',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isEarned ? _successColor : _dangerColor,
            ),
          ),
        ],
      ),
    );
  }

  // حالة فارغة
  Widget _buildEmptyState() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.all(40),
        child: const Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: _textMuted,
            ),
            SizedBox(height: 16),
            Text(
              'لا توجد معاملات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textSecondary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'ابدأ بتقديم طلبات لكسب النقاط',
              style: TextStyle(
                fontSize: 14,
                color: _textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // زر الاستبدال العائم
  Widget _buildFloatingRedeemButton() {
    return AnimatedBuilder(
      animation: _buttonAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _buttonAnimation.value,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_redeemButtonColor, _accentColor],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _redeemButtonColor.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _redeemPoints,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'استبدال النقاط',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
