import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/session_service.dart';
import '../services/auth_service.dart';
import '../widgets/iraqi_phone_input.dart';
import 'email_verification_screen.dart';
import 'verified_phone_screen.dart';
// import 'package:foodapp_user/services/user_profile_service.dart'; // مُعطل مؤقتاً

class ChangeEmailPhoneScreen extends StatefulWidget {
  const ChangeEmailPhoneScreen({super.key});

  @override
  State<ChangeEmailPhoneScreen> createState() => _ChangeEmailPhoneScreenState();
}

class _ChangeEmailPhoneScreenState extends State<ChangeEmailPhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _isEmailSelected = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentData() async {
    try {
      final sessionData = SessionService.instance.currentUser;
      final userEmail =
          sessionData?['userEmail'] ?? sessionData?['email'] ?? '';

      // التحقق من وجود تغيير بريد مؤقت غير مكتمل
      final prefs = await SharedPreferences.getInstance();
      final pendingOldEmail = prefs.getString('pending_email_change_old');
      final pendingNewEmail = prefs.getString('pending_email_change_new');
      final pendingTimestamp = prefs.getInt('pending_email_change_timestamp');

      if (pendingOldEmail != null &&
          pendingNewEmail != null &&
          pendingTimestamp != null) {
        // التحقق من عمر التغيير المؤقت (24 ساعة)
        final changeTime = DateTime.fromMillisecondsSinceEpoch(
          pendingTimestamp,
        );
        final timeSinceChange = DateTime.now().difference(changeTime);

        if (timeSinceChange.inHours > 24) {
          // إذا مر أكثر من 24 ساعة، اعتبر التغيير غير صالح
          await prefs.remove('pending_email_change_old');
          await prefs.remove('pending_email_change_new');
          await prefs.remove('pending_email_change_timestamp');
        } else {
          // عرض تحذير للمستخدم بأن لديه تغيير بريد لم يكتمل
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ لديك تغيير بريد غير مكتمل\n'
                  'من: $pendingOldEmail\n'
                  'إلى: $pendingNewEmail\n'
                  'يرجى التحقق من البريد الجديد لإكمال التغيير',
                ),
                backgroundColor: AppColors.secondary,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'إلغاء التغيير',
                  textColor: Colors.white,
                  onPressed: () async {
                    // إلغاء التغيير المؤقت واستعادة البريد القديم
                    await _cancelPendingEmailChange();
                  },
                ),
              ),
            );
          }
        }
      }

      setState(() {
        _emailController.text = userEmail;
        // TODO: تحميل رقم الهاتف من الخادم
        _phoneController.text =
            sessionData?['phone'] ?? sessionData?['phoneNumber'] ?? '';
      });

      // إظهار رسالة توضيحية للمستخدم
      if (mounted && userEmail.isNotEmpty && pendingOldEmail == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '💡 البريد الحالي: $userEmail\nيمكنك تغييره إلى بريد جديد',
            ),
            backgroundColor: AppColors.secondary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Handle error
    }
  }

  /// إلغاء تغيير البريد المؤقت واستعادة البريد القديم
  Future<void> _cancelPendingEmailChange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingOldEmail = prefs.getString('pending_email_change_old');

      if (pendingOldEmail != null) {
        // استعادة البريد القديم في الجلسة - TODO: implement updateUserInfo in SessionService
        // await SessionService.updateUserInfo(userEmail: pendingOldEmail);

        // مسح معلومات التغيير المؤقت
        await prefs.remove('pending_email_change_old');
        await prefs.remove('pending_email_change_new');
        await prefs.remove('pending_email_change_timestamp');

        // تحديث الواجهة
        setState(() {
          _emailController.text = pendingOldEmail;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ تم إلغاء تغيير البريد واستعادة البريد القديم: $pendingOldEmail',
              ),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // Ignore date parsing errors
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final sessionData = SessionService.instance.currentUser;
      final userId = sessionData?['userId'] ?? sessionData?['user_id'] ?? '';

      if (userId.isEmpty) {
        throw Exception('معرف المستخدم غير موجود');
      }

      if (_isEmailSelected) {
        // تغيير البريد الإلكتروني - استخدام نفس الآلية المجربة من شاشة التحقق
        final newEmail = _emailController.text.trim();
        final oldEmail =
            sessionData?['userEmail'] ?? sessionData?['email'] ?? '';
        // حفظ البريد القديم في SharedPreferences كـ backup في حالة عدم التأكيد
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_email_change_old', oldEmail);
        await prefs.setString('pending_email_change_new', newEmail);
        await prefs.setInt(
          'pending_email_change_timestamp',
          DateTime.now().millisecondsSinceEpoch,
        );

        // 🔒 استخدام الـ API الآمن الجديد أولاً (لا يحدث البريد في قاعدة البيانات)
        Map<String, dynamic> result;

        try {
          result = await AuthService.sendVerificationCodeToNewEmail(
            userId: userId,
            newEmail: newEmail,
          );
        } catch (e) {
          try {
            result = await AuthService.updateEmailAndResendCode(
              userId: userId,
              newEmail: newEmail,
            );
          } catch (fallbackError) {
            // إزالة معلومات تغيير البريد المؤقتة في حالة الفشل
            await prefs.remove('pending_email_change_old');
            await prefs.remove('pending_email_change_new');
            await prefs.remove('pending_email_change_timestamp');

            result = {
              'success': false,
              'error':
                  'فشل في الاتصال مع الخادم. يرجى التحقق من الإنترنت والمحاولة مرة أخرى.',
            };
          }
        }

        if (mounted) {
          if (result['success'] == true) {
            // إظهار رسالة نجاح
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ تم إرسال رمز التحقق إلى البريد الجديد: $newEmail',
                ),
                backgroundColor: AppColors.primary,
                duration: const Duration(seconds: 3),
              ),
            );

            // الانتقال لشاشة التحقق مع البريد الجديد
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (_) => EmailVerificationScreen(
                      email: newEmail,
                      password: '', // كلمة مرور فارغة للتحقق فقط
                      fullName:
                          sessionData?['userName'] ??
                          sessionData?['name'] ??
                          'المستخدم',
                      phoneNumber:
                          sessionData?['phoneNumber'] ??
                          sessionData?['phone'] ??
                          '',
                    ),
              ),
            );
          } else {
            String errorMessage =
                result['error'] ?? 'فشل في تحديث البريد الإلكتروني';

            // معالجة أخطاء كلمة المرور
            if (errorMessage.contains('password') ||
                errorMessage.contains('كلمة المرور')) {
              errorMessage =
                  '❌ كلمة المرور غير صحيحة. يرجى التحقق من كلمة المرور والمحاولة مرة أخرى';
            } else if (errorMessage.contains('email') ||
                errorMessage.contains('البريد')) {
              errorMessage = '❌ البريد الإلكتروني غير صالح أو مستخدم مسبقاً';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: AppColors.primaryDark,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        final success = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder:
                (_) => VerifiedPhoneScreen(
                  initialPhone: _phoneController.text.trim(),
                ),
          ),
        );
        if (success == true && mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحفظ: $e'),
            backgroundColor: AppColors.primaryDark,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'تغيير البيانات',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSelectionTabs(),
              const SizedBox(height: 30),
              _buildFormCard(),
              const SizedBox(height: 30),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isEmailSelected = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color:
                      _isEmailSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15),
                    bottomLeft: Radius.circular(15),
                  ),
                ),
                child: Text(
                  'البريد الإلكتروني',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isEmailSelected ? Colors.white : Colors.grey[600],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isEmailSelected = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color:
                      !_isEmailSelected
                          ? AppColors.primary
                          : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                ),
                child: Text(
                  'رقم الهاتف',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: !_isEmailSelected ? Colors.white : Colors.grey[600],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isEmailSelected) ...[
            const Text(
              'البريد الإلكتروني الجديد',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'أدخل البريد الإلكتروني الجديد',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'يرجى إدخال البريد الإلكتروني';
                }
                if (!RegExp(
                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(value!)) {
                  return 'يرجى إدخال بريد إلكتروني صحيح';
                }
                return null;
              },
            ),
          ] else ...[
            const Text(
              'رقم الهاتف الجديد',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            IraqiPhoneInput(
              controller: _phoneController,
              hintText: '7XX XXX XXXX',
            ),
          ],
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color:
                  _isEmailSelected
                      ? AppColors.secondaryLight.withValues(alpha: 0.1)
                      : AppColors.secondaryLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    _isEmailSelected
                        ? AppColors.secondaryLight
                        : AppColors.secondaryLight,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isEmailSelected
                      ? Icons.email_outlined
                      : Icons.phone_outlined,
                  color:
                      _isEmailSelected
                          ? AppColors.secondary
                          : AppColors.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEmailSelected
                            ? 'سيتم إرسال رمز تأكيد إلى البريد الجديد'
                            : 'سيتم إرسال رمز تأكيد إلى رقم الهاتف الجديد',
                        style: TextStyle(
                          color:
                              _isEmailSelected
                                  ? AppColors.secondaryDark
                                  : AppColors.secondaryDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_isEmailSelected) ...[
                        const SizedBox(height: 4),
                        Text(
                          'ستنتقل تلقائياً لشاشة التحقق لإدخال الرمز',
                          style: TextStyle(color: Colors.black, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveChanges,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child:
            _isLoading
                ? const CircularProgressIndicator(
                  color: const Color(0xFF00296B),
                )
                : const Text(
                  'حفظ التغييرات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
      ),
    );
  }
}
