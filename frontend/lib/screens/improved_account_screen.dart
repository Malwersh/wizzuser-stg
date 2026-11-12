import 'dart:ui' as ui;
import '../widgets/account_overview.dart';
import 'orders_screen.dart';
import 'wallet_transfer_screen.dart';
import 'customer_legal_screen.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;
import '../providers/app_state_provider.dart';
import '../services/user_profile_service.dart';
import '../services/session_service.dart';
import '../services/logout_service.dart';
import 'login_screen.dart';
import 'register_screen_tabs.dart';
import 'addresses_screen.dart';
import 'verified_phone_screen.dart';
import 'notification_settings_screen.dart';
import 'language_settings_screen.dart';
import 'country_settings_screen.dart';
import 'delete_account_screen.dart';
import 'personal_info_screen.dart';
import 'support_chat_screen.dart';
import 'account_more_screen.dart';

class ImprovedAccountScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final WidgetBuilder? favoritesBuilder;

  const ImprovedAccountScreen({super.key, this.onBack, this.favoritesBuilder});

  @override
  State<ImprovedAccountScreen> createState() => _ImprovedAccountScreenState();
}

class _ImprovedAccountScreenState extends State<ImprovedAccountScreen> {
  Map<String, dynamic>? userProfile;
  bool isLoadingProfile = false;
  String? profileError;
  String? _profileOwner;
  int _profileGeneration = 0;
  bool _hasLoadedOnce = false; // 🔧 إضافة فلاج لتجنب التحميل المتكرر
  bool _isDisposed =
      false; // 🔧 إضافة فلاج للتأكد من عدم استدعاء setState بعد dispose
  bool _isLoggingOut = false; // 🔧 فلاج لمنع تكرار محاولات تسجيل الخروج

  @override
  void initState() {
    super.initState();
    developer.log('🔧 ImprovedAccountScreen initState() called');
    _profileOwner = SessionService.instance.currentUserId;
    SessionService.instance.addListener(_onSessionChanged);
    _initializeAndLoadProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 🔧 إصلاح: إزالة _loadUserProfile من هنا لتجنب الحلقة غير المنتهية
    // البيانات يتم تحميلها بالفعل في initState و _initializeAndLoadProfile
  }

  @override
  void dispose() {
    SessionService.instance.removeListener(_onSessionChanged);
    _profileGeneration++;
    _isDisposed = true; // 🔧 منع أي setState بعد dispose
    super.dispose();
  }

  Future<void> _initializeAndLoadProfile() async {
    // 🔧 إصلاح: تبسيط منطق التهيئة لتجنب الحلقة اللانهائية
    // تحميل البروفايل مباشرة بدون تعقيدات
    await _loadUserProfile();
  }

  void _onSessionChanged() {
    final owner = SessionService.instance.currentUserId;
    if (owner == _profileOwner || !mounted) return;
    _profileOwner = owner;
    _profileGeneration++;
    setState(() {
      userProfile = null;
      _hasLoadedOnce = false;
      profileError = null;
    });
    _loadUserProfile();
  }

  Future<void> _loadUserProfile({bool force = false}) async {
    if (!mounted || _isDisposed || (_hasLoadedOnce && !force)) return;
    final owner = SessionService.instance.currentUserId;
    final generation = ++_profileGeneration;
    if (owner == null || !SessionService.instance.isLoggedIn) {
      setState(() {
        userProfile = null;
        isLoadingProfile = false;
      });
      return;
    }
    setState(() {
      isLoadingProfile = true;
      profileError = null;
    });
    final profile = await UserProfileService.getUserProfile(owner);
    if (!mounted ||
        _isDisposed ||
        generation != _profileGeneration ||
        owner != SessionService.instance.currentUserId) {
      return;
    }
    setState(() {
      userProfile = profile;
      isLoadingProfile = false;
      _hasLoadedOnce = profile != null;
      profileError = profile == null ? 'تعذر تحديث معلومات الحساب' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading:
            widget.onBack != null
                ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: widget.onBack,
                )
                : null,
        title: const Text(
          'حسابي',
          style: TextStyle(
            color: AppColors.secondaryDark,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          // 🔧 إصلاح: إزالة الـ developer.log من build method لتجنب اللوب اللانهائي
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildUserInfoCard(appState),
                if (profileError != null)
                  TextButton.icon(
                    onPressed:
                        isLoadingProfile
                            ? null
                            : () => _loadUserProfile(force: true),
                    icon: const Icon(
                      Icons.refresh,
                      color: AppColors.secondaryDark,
                    ),
                    label: Text(
                      '$profileError · إعادة المحاولة',
                      style: const TextStyle(color: AppColors.secondaryDark),
                    ),
                  ),
                const SizedBox(height: 20),
                _buildOptionsMenu(appState),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserInfoCard(AppStateProvider appState) {
    final isLoggedIn = appState.isLoggedIn;
    final userData = SessionService.instance.currentUser ?? appState.userData;

    // إصلاح: عرض البيانات من المصادر الصحيحة
    final userName =
        userData?['name'] ??
        userData?['username'] ??
        userData?['userName'] ??
        'مستخدم';
    final userPhone = [
          userProfile?['phone'],
          userData?['phone'],
          userData?['phoneNumber'],
          userData?['phone_number'],
          userData?['userPhone'],
        ]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => 'رقم الهاتف غير مضاف',
        );

    if (isLoggedIn) {
      final name = [userProfile?['name'], userProfile?['fullName'], userName]
          .map((v) => v?.toString().trim() ?? '')
          .firstWhere((v) => v.isNotEmpty, orElse: () => 'حسابي');
      return AccountOverview(
        name: name,
        phone: userPhone,
        photoUrl:
            (userProfile?['photoUrl'] ?? userData?['photoUrl'])?.toString(),
        onFavorites:
            widget.favoritesBuilder == null
                ? null
                : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: widget.favoritesBuilder!),
                ),
        onWallet:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalletTransferScreen()),
            ),
        onOrders:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrdersScreen()),
            ),
      );
    }

    return GuestAccountOverview(
      onLogin: _navigateToLogin,
      onRegister: _navigateToRegister,
    );
  }

  Widget _buildOptionsMenu(AppStateProvider appState) {
    final isLoggedIn = appState.isLoggedIn;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isLoggedIn) ...[
            _buildMenuItem(
              icon: Icons.person,
              title: 'المعلومات الشخصية',
              onTap: () => _navigateToPersonalInfo(),
            ),
            _buildDivider(),
            _buildMenuItem(
              icon: Icons.location_on,
              title: 'العناوين',
              onTap: () => _navigateToAddresses(),
            ),
            _buildDivider(),
            _buildMenuItem(
              icon: Icons.phone,
              title: 'تغيير الهاتف',
              onTap: () => _navigateToChangePhone(),
            ),
            _buildDivider(),
          ],

          _buildMenuItem(
            icon: Icons.notifications,
            title: 'إعدادات الإشعارات',
            onTap: () => _navigateToNotificationSettings(),
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.language,
            title: 'اللغة',
            onTap: () => _navigateToLanguageSettings(),
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.public,
            title: 'الدولة والمنطقة',
            onTap: () => _navigateToCountrySettings(),
          ),

          _buildDivider(),
          _buildMenuItem(
            icon: Icons.policy_outlined,
            title: 'السياسات والشروط',
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CustomerLegalScreen(),
                  ),
                ),
          ),

          if (isLoggedIn) ...[
            _buildDivider(),
            _buildMenuItem(
              icon: Icons.more_horiz,
              title: 'المزيد',
              onTap: _navigateToMore,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? AppColors.primaryDark : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: isDestructive ? AppColors.primaryDark : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_left,
              textDirection: ui.TextDirection.ltr,
              size: 20,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey[200],
      indent: 60,
    );
  }

  void _showLogoutDialog() async {
    // استخدام LogoutService الجديد للتسجيل الآمن
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    try {
      final success = await LogoutService.performSecureLogout(context);

      if (success) {
        // إعادة تعيين الحالة المحلية بأمان
        _hasLoadedOnce = false;
        if (mounted && !_isDisposed) {
          setState(() {
            userProfile = null;
            isLoadingProfile = false;
            profileError = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تسجيل الخروج: $e'),
            backgroundColor: AppColors.primaryDark,
          ),
        );
      }
    } finally {
      // تأكد من إعادة الفلاج فقط إذا مازلنا موجودين في الذاكرة
      if (mounted && !_isDisposed) {
        _isLoggingOut = false;
      }
    }
  }

  void _navigateToLogin() {
    // 🔧 إصلاح نهائي: استخدام push عادي بدلاً من pushAndRemoveUntil لتجنب تعارض التنقل
    // بعد تسجيل الدخول بنجاح، ستتولى شاشة تسجيل الدخول نفسها التنقل الصحيح
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  void _navigateToRegister() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const RegisterScreenTabs()));
  }

  Future<void> _navigateToPersonalInfo() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const PersonalInfoScreen()));
    if (mounted) await _loadUserProfile(force: true);
  }

  void _navigateToAddresses() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AddressesScreen()));
  }

  Future<void> _navigateToChangePhone() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const VerifiedPhoneScreen()),
    );
    if (mounted) await _loadUserProfile(force: true);
  }

  void _navigateToNotificationSettings() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NotificationSettingsScreen(),
      ),
    );
  }

  void _navigateToLanguageSettings() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const LanguageSettingsScreen()),
    );
  }

  void _navigateToCountrySettings() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const CountrySettingsScreen()),
    );
  }

  void _navigateToMore() {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AccountMoreScreen(
        onSupport: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SupportChatScreen())),
        onDeleteAccount: _navigateToDeleteAccount,
        onLogout: _showLogoutDialog,
      ),
    ));
  }

  void _navigateToDeleteAccount() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const DeleteAccountScreen()),
    );
  }
}
