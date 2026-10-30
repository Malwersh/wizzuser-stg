import 'customer_legal_screen.dart';
import '../utils/readable_colors.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;
import '../providers/app_state_provider.dart';
import '../services/user_profile_service.dart';
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

class ImprovedAccountScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ImprovedAccountScreen({super.key, this.onBack});

  @override
  State<ImprovedAccountScreen> createState() => _ImprovedAccountScreenState();
}

class _ImprovedAccountScreenState extends State<ImprovedAccountScreen> {
  Map<String, dynamic>? userProfile;
  bool isLoadingProfile = false;
  String? profileError;
  bool _hasLoadedOnce = false; // 🔧 إضافة فلاج لتجنب التحميل المتكرر
  bool _isDisposed =
      false; // 🔧 إضافة فلاج للتأكد من عدم استدعاء setState بعد dispose
  bool _isLoggingOut = false; // 🔧 فلاج لمنع تكرار محاولات تسجيل الخروج

  @override
  void initState() {
    super.initState();
    developer.log('🔧 ImprovedAccountScreen initState() called');
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
    _isDisposed = true; // 🔧 منع أي setState بعد dispose
    super.dispose();
  }

  Future<void> _initializeAndLoadProfile() async {
    // 🔧 إصلاح: تبسيط منطق التهيئة لتجنب الحلقة اللانهائية
    // تحميل البروفايل مباشرة بدون تعقيدات
    await _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    // 🔧 فحوصات الأمان الأساسية
    if (!mounted || _isDisposed) return;

    // 🔧 منع التحميل المتكرر
    if (_hasLoadedOnce) {
      developer.log('⚠️ تم تجنب التحميل المتكرر', name: 'IMPROVED_ACCOUNT');
      return;
    }

    // 🔧 تحميل البروفايل للمستخدمين المسجلين فقط
    if (appState.isLoggedIn && appState.userData != null) {
      if (mounted && !_isDisposed) {
        setState(() {
          isLoadingProfile = true;
          profileError = null;
        });
      }

      try {
        final userId =
            appState.userData!['userId'] ??
            appState.userData!['user_id'] ??
            appState.userData!['email'];

        if (userId != null) {
          final profile = await UserProfileService.getUserProfile(
            userId.toString(),
          );
          if (mounted && !_isDisposed) {
            setState(() {
              userProfile = profile;
              isLoadingProfile = false;
              _hasLoadedOnce = true;
            });
          }
        } else {
          if (mounted && !_isDisposed) {
            setState(() {
              profileError = 'لم يتم العثور على معرف المستخدم';
              isLoadingProfile = false;
              _hasLoadedOnce = true;
            });
          }
        }
      } catch (e) {
        if (mounted && !_isDisposed) {
          setState(() {
            profileError = 'خطأ في جلب بيانات المستخدم: $e';
            isLoadingProfile = false;
            _hasLoadedOnce = true;
          });
        }
      }
    } else {
      // للضيوف أو غير المسجلين
      if (mounted && !_isDisposed) {
        setState(() {
          userProfile = null;
          isLoadingProfile = false;
          profileError = null;
          _hasLoadedOnce = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
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
            color: Colors.black,
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
    final userData = appState.userData;

    // إصلاح: عرض البيانات من المصادر الصحيحة
    final userName =
        userData?['name'] ??
        userData?['username'] ??
        userData?['userName'] ??
        'مستخدم';
    final userPhone = [
          userData?['phone'],
          userData?['phone_number'],
          userData?['userPhone'],
        ]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => 'رقم الهاتف غير مضاف',
        );

    // 🔧 إصلاح: إزالة الـ developer.log من build methods لتجنب اللوب اللانهائي

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // أيقونة المستخدم
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: Icon(
              isLoggedIn ? Icons.person : Icons.person_outline,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),

          // معلومات المستخدم
          if (isLoggedIn) ...[
            Text(
              userName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF00296B),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                userPhone,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else ...[
            // 🔧 إصلاح: عرض تصميم الضيف دائماً للمستخدمين غير المسجلين
            const Text(
              'مرحباً ضيفنا الكريم',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'أنت تتصفح كضيف - سجل للحصول على تجربة أفضل!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'مستخدم ضيف',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.star, color: Colors.white, size: 20),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'سجّل حساباً واحفظ طلباتك المفضلة\nواحصل على عروض خاصة!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // أزرار تسجيل الدخول وإنشاء الحساب
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToLogin(),
                    icon: const Icon(Icons.login, size: 20),
                    label: const Text('تسجيل الدخول'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: readableForeground(Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToRegister(),
                    icon: const Icon(Icons.person_add, size: 20),
                    label: const Text('إنشاء حساب'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
              icon: Icons.delete_forever,
              title: 'حذف الحساب',
              onTap: () => _navigateToDeleteAccount(),
              isDestructive: true,
            ),
            _buildDivider(),
            _buildMenuItem(
              icon: Icons.logout,
              title: 'تسجيل الخروج',
              onTap: () => _showLogoutDialog(),
              isDestructive: true,
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
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
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

  void _navigateToPersonalInfo() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const PersonalInfoScreen()));
  }

  void _navigateToAddresses() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AddressesScreen()));
  }

  void _navigateToChangePhone() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const VerifiedPhoneScreen()),
    );
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

  void _navigateToDeleteAccount() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const DeleteAccountScreen()),
    );
  }
}
