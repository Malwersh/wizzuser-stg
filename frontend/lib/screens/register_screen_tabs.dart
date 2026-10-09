// lib/screens/register_screen_tabs.dart - Enhanced Version with Email and Phone Tabs
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../constants/app_colors.dart';
import 'login_screen.dart';
import 'email_verification_screen.dart';
import 'phone_verification_screen.dart';
import '../services/auth_service.dart';
import '../widgets/iraqi_phone_input.dart';
import '../utils/validation_helper.dart';

class RegisterScreenTabs extends StatefulWidget {
  const RegisterScreenTabs({super.key});

  @override
  State<RegisterScreenTabs> createState() => _RegisterScreenTabsState();
}

class _RegisterScreenTabsState extends State<RegisterScreenTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Form keys for each tab
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  
  // Common controllers
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _birthDateController = TextEditingController();
  
  // Email tab controllers
  final _emailController = TextEditingController();
  
  // Phone tab controllers
  final _phoneController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // Required consents
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  
  // Optional fields
  bool _marketingConsent = false;
  String _selectedGender = 'male'; // 'male' or 'female'
  DateTime? _selectedBirthDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _birthDateController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Email registration function
  Future<void> _handleEmailRegister() async {
    if (!_emailFormKey.currentState!.validate()) return;
    
    if (!_termsAccepted || !_privacyAccepted) {
      _showMessage("يجب الموافقة على الشروط والأحكام وسياسة الخصوصية");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.registerWithEmail(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        termsAccepted: _termsAccepted,
        privacyAccepted: _privacyAccepted,
        marketingConsent: _marketingConsent,
        birthDate: _selectedBirthDate,
        gender: _selectedGender,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        final tempUserId = result['tempUserId'];
        _showMessage("تم إنشاء الحساب بنجاح! يرجى التحقق من البريد الإلكتروني");
        _navigateToEmailVerification(tempUserId, false);
      } else if (result['requiresVerification'] == true) {
        // حساب غير مؤكد موجود
        final tempUserId = result['tempUserId'];
        _showVerificationDialog(
          message: "يوجد حساب غير مؤكد بهذا الإيميل.",
          tempUserId: tempUserId,
          verificationType: 'email',
        );
      } else {
        String errorMessage = result['error'] ?? 'حدث خطأ أثناء إنشاء الحساب';
        _showMessage(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('حدث خطأ في الاتصال: ${e.toString()}');
      }
    }
  }

  // Phone registration function
  Future<void> _handlePhoneRegister() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    
    if (!_termsAccepted || !_privacyAccepted) {
      _showMessage("يجب الموافقة على الشروط والأحكام وسياسة الخصوصية");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Convert phone input to full format using ValidationHelper
      String phoneInput = _phoneController.text.trim();
      String formattedPhone = ValidationHelper.isValidIraqiPhoneInput(phoneInput) 
          ? ValidationHelper.convertToFullPhoneNumber(phoneInput)
          : phoneInput;

      final result = await AuthService.registerWithPhone(
        name: _nameController.text.trim(),
        phone: formattedPhone,
        password: _passwordController.text,
        countryCode: '+964', // Always use Iraq country code for Iraqi phone input
        termsAccepted: _termsAccepted,
        privacyAccepted: _privacyAccepted,
        marketingConsent: _marketingConsent,
        birthDate: _selectedBirthDate,
        gender: _selectedGender,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        final tempUserId = result['tempUserId'];
        _showMessage("تم إنشاء الحساب بنجاح! يرجى التحقق من رقم الهاتف");
        _navigateToPhoneVerification(tempUserId, false);
      } else if (result['requiresVerification'] == true) {
        // حساب غير مؤكد موجود
        developer.log('🔍 DEBUG: Phone registration - requiresVerification detected!');
        developer.log('🔍 DEBUG: Full result: $result');
        final tempUserId = result['tempUserId'];
        developer.log('🔍 DEBUG: tempUserId: $tempUserId');
        _showVerificationDialog(
          message: "يوجد حساب غير مؤكد بهذا الرقم.",
          tempUserId: tempUserId,
          verificationType: 'phone',
        );
      } else {
        developer.log('🔍 DEBUG: Phone registration - other case');
        developer.log('🔍 DEBUG: Full result: $result');
        _showMessage(result['error'] ?? 'حدث خطأ أثناء إنشاء الحساب');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('حدث خطأ في الاتصال: ${e.toString()}');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: message.contains('خطأ') ? AppColors.primaryDark : AppColors.primary,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Date picker for birth date
  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
      locale: const Locale('ar', 'SA'),
    );
    
    if (picked != null) {
      setState(() {
        _selectedBirthDate = picked;
        _birthDateController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  // Navigation helpers
  void _navigateToEmailVerification(String tempUserId, bool isReVerification) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
          phoneNumber: '',
          userId: tempUserId,
        ),
      ),
    );
  }

  void _navigateToPhoneVerification(String tempUserId, bool isReVerification) {
    developer.log('🔍 DEBUG: _navigateToPhoneVerification called');
    developer.log('🔍 DEBUG: tempUserId: $tempUserId, isReVerification: $isReVerification');
    developer.log('🔍 DEBUG: phone: ${_phoneController.text.trim()}');
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PhoneVerificationScreen(
          tempUserId: tempUserId,
          phoneNumber: _phoneController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
          email: _emailController.text.trim(),
        ),
      ),
    );
  }

  // Show verification dialog for existing unverified accounts
  void _showVerificationDialog({
    required String message,
    required String tempUserId,
    required String verificationType,
  }) {
    developer.log('🔍 DEBUG: _showVerificationDialog called');
    developer.log('🔍 DEBUG: message: $message');
    developer.log('🔍 DEBUG: tempUserId: $tempUserId');
    developer.log('🔍 DEBUG: verificationType: $verificationType');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.secondary,
                size: 28,
              ),
              const SizedBox(width: 10),
              const Text(
                'حساب غير مؤكد',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                verificationType == 'email'
                    ? 'يرجى إدخال رمز التحقق المرسل إلى بريدك الإلكتروني لتأكيد الحساب.'
                    : 'سيتم إرسال رمز تحقق جديد إلى رقم هاتفك. يرجى إدخاله لتأكيد الحساب.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Stay on current screen
              },
              child: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                developer.log('🔍 DEBUG: "متابعة التحقق" button pressed');
                developer.log('🔍 DEBUG: verificationType: $verificationType');
                Navigator.of(context).pop();
                // Navigate to verification screen
                if (verificationType == 'email') {
                  developer.log('🔍 DEBUG: Calling _navigateToEmailVerification');
                  _navigateToEmailVerification(tempUserId, true);
                } else if (verificationType == 'phone') {
                  developer.log('🔍 DEBUG: Calling _navigateToPhoneVerification');
                  _navigateToPhoneVerification(tempUserId, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
              ),
              child: const Text('متابعة التحقق'),
            ),
          ],
        );
      },
    );
  }

  // UI Helper methods
  Widget _buildSectionTitle(String title, bool isRequired) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(color: Colors.red, fontSize: 18),
          ),
        ],
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(prefixIcon, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String labelText,
    required bool obscureText,
    required VoidCallback onVisibilityToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary),
        suffixIcon: IconButton(
          onPressed: onVisibilityToggle,
          icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildPhoneField() {
    return IraqiPhoneInput(
      controller: _phoneController,
      hintText: '7XX XXX XXXX',
    );
  }

  Widget _buildDateField() {
    return _buildTextFormField(
      controller: _birthDateController,
      labelText: 'تاريخ الميلاد (اختياري)',
      prefixIcon: Icons.calendar_month,
      readOnly: true,
      onTap: _selectBirthDate,
    );
  }

  Widget _buildGenderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الجنس (اختياري)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: const Text('ذكر'),
                value: 'male',
                groupValue: _selectedGender,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedGender = value);
                  }
                },
                activeColor: Theme.of(context).primaryColor,
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: const Text('أنثى'),
                value: 'female',
                groupValue: _selectedGender,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedGender = value);
                  }
                },
                activeColor: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConsentCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String text,
    required bool isRequired,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).primaryColor,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: isRequired && !value ? Colors.red : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Common fields for both tabs
  Widget _buildCommonFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name field (Required)
        _buildTextFormField(
          controller: _nameController,
          labelText: 'الاسم الكامل *',
          prefixIcon: Icons.person_outline,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'الاسم الكامل مطلوب';
            }
            if (value.trim().length < 2) {
              return 'يجب أن يكون الاسم حرفين على الأقل';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 20),
        
        // Password field (Required)
        _buildPasswordField(
          controller: _passwordController,
          labelText: 'كلمة المرور *',
          obscureText: _obscurePassword,
          onVisibilityToggle: () => setState(() => _obscurePassword = !_obscurePassword),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'كلمة المرور مطلوبة';
            }
            if (value.length < 8) {
              return 'يجب أن تكون كلمة المرور 8 أحرف على الأقل';
            }
            if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(value)) {
              return 'يجب أن تحتوي على أحرف كبيرة وصغيرة وأرقام';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 20),
        
        // Confirm password field (Required)
        _buildPasswordField(
          controller: _confirmPasswordController,
          labelText: 'تأكيد كلمة المرور *',
          obscureText: _obscureConfirmPassword,
          onVisibilityToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          validator: (value) {
            if (value != _passwordController.text) {
              return 'كلمة المرور غير متطابقة';
            }
            return null;
          },
        ),
      ],
    );
  }

  // Optional fields section
  Widget _buildOptionalFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        
        // Optional fields section
        _buildSectionTitle('المعلومات الإضافية (اختيارية)', false),
        const SizedBox(height: 16),
        
        // Birth date field (Optional)
        _buildDateField(),
        
        const SizedBox(height: 20),
        
        // Gender field (Optional)
        _buildGenderField(),
      ],
    );
  }

  // Consent fields section
  Widget _buildConsentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        
        // Consents section
        _buildSectionTitle('الموافقات', true),
        const SizedBox(height: 16),
        
        // Required consents
        _buildConsentCheckbox(
          value: _termsAccepted,
          onChanged: (value) => setState(() => _termsAccepted = value ?? false),
          text: 'أوافق على الشروط والأحكام *',
          isRequired: true,
        ),
        
        _buildConsentCheckbox(
          value: _privacyAccepted,
          onChanged: (value) => setState(() => _privacyAccepted = value ?? false),
          text: 'أوافق على سياسة الخصوصية *',
          isRequired: true,
        ),
        
        // Optional consent
        _buildConsentCheckbox(
          value: _marketingConsent,
          onChanged: (value) => setState(() => _marketingConsent = value ?? false),
          text: 'أوافق على تلقي العروض والإشعارات التسويقية',
          isRequired: false,
        ),
      ],
    );
  }

  // Email registration tab
  Widget _buildEmailTab() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          
          const Icon(
            Icons.email_outlined,
            size: 64,
            color: AppColors.secondary,
          ),
          
          const SizedBox(height: 16),
          
          const Text(
            'التسجيل بالبريد الإلكتروني',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          
          const SizedBox(height: 8),
          
          const Text(
            'سيتم إرسال رمز التحقق إلى بريدك الإلكتروني',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Email field (Required for this tab)
          _buildTextFormField(
            controller: _emailController,
            labelText: 'البريد الإلكتروني *',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'البريد الإلكتروني مطلوب';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'البريد الإلكتروني غير صحيح';
              }
              return null;
            },
          ),
          
          const SizedBox(height: 20),
          
          // Common fields
          _buildCommonFields(),
          
          // Optional fields
          _buildOptionalFields(),
          
          // Consent fields
          _buildConsentFields(),
          
          const SizedBox(height: 32),
          
          // Email Register button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleEmailRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.email_outlined),
                        SizedBox(width: 8),
                        Text(
                          'إنشاء الحساب بالبريد الإلكتروني',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Phone registration tab
  Widget _buildPhoneTab() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          
          const Icon(
            Icons.phone_outlined,
            size: 64,
            color: AppColors.primary,
          ),
          
          const SizedBox(height: 16),
          
          const Text(
            'التسجيل برقم الهاتف',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          
          const SizedBox(height: 8),
          
          const Text(
            'سيتم إرسال رمز التحقق إلى رقم هاتفك',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Phone field (Required for this tab)
          _buildPhoneField(),
          
          const SizedBox(height: 20),
          
          // Common fields
          _buildCommonFields(),
          
          // Optional fields
          _buildOptionalFields(),
          
          // Consent fields
          _buildConsentFields(),
          
          const SizedBox(height: 32),
          
          // Phone Register button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handlePhoneRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.phone_outlined),
                        SizedBox(width: 8),
                        Text(
                          'إنشاء الحساب برقم الهاتف',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'إنشاء حساب جديد',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(
                icon: Icon(Icons.email_outlined),
                text: 'البريد الإلكتروني',
              ),
              Tab(
                icon: Icon(Icons.phone_outlined),
                text: 'رقم الهاتف',
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Email registration tab
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: _buildEmailTab(),
              ),
              // Phone registration tab
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: _buildPhoneTab(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('لديك حساب بالفعل؟ '),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Text(
                  'تسجيل الدخول',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
