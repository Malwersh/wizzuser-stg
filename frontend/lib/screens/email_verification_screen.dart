// lib/screens/email_verification_screen.dart
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../constants/app_colors.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String? password;
  final String? fullName;
  final String? phoneNumber;
  final String? userId;
  final String? phone;
  final bool? phoneVerificationRequired;
  final bool? emailVerificationRequired;
  final bool? phoneVerificationSent;
  final bool? emailVerificationSent;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    this.password,
    this.fullName,
    this.phoneNumber,
    this.userId,
    this.phone,
    this.phoneVerificationRequired,
    this.emailVerificationRequired,
    this.phoneVerificationSent,
    this.emailVerificationSent,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final TextEditingController _verificationCodeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sendVerificationCode();
  }

  Future<void> _sendVerificationCode() async {
    try {
      // لا نقوم بإعادة إرسال تلقائي عند فتح الشاشة.
      developer.log('📧 Email verification screen opened for: ${widget.email} (tempUserId=${widget.userId ?? ''})');
    } catch (e) {
      setState(() {
        _errorMessage = 'فشل في إرسال رمز التحقق: $e';
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationCodeController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال رمز التحقق';
      });
      return;
    }

    final tempUserId = (widget.userId != null && widget.userId!.trim().isNotEmpty)
        ? widget.userId!.trim()
        : '';

    if (tempUserId.isEmpty) {
      setState(() {
        _errorMessage = 'لا يمكن التحقق: معرف المستخدم غير متوفر';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // التحقق من الرمز
      final code = _verificationCodeController.text.trim();
      final isValid = code.length == 6 && RegExp(r'^\d+$').hasMatch(code);

      if (isValid) {
        final result = await AuthService.verifyEmailRegistration(
          tempUserId: tempUserId,
          code: code,
        );

        if (result['success'] == true) {
          developer.log('✅ Email verified successfully (tempUserId=$tempUserId)');
          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
            ),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'تم تأكيد البريد الإلكتروني. يمكنك تسجيل الدخول الآن'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          if (!mounted) return;
          setState(() {
            _errorMessage = result['error'] ?? result['message'] ?? 'فشل التحقق من الرمز';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'رمز التحقق غير صحيح';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء التحقق: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: const Text(
          'تحقق من البريد الإلكتروني',
          style: TextStyle(color: AppColors.primary),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.email_outlined,
              size: 80,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            const Text(
              'تحقق من بريدك الإلكتروني',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لقد أرسلنا رمز التحقق إلى\n${widget.email}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _verificationCodeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'رمز التحقق',
                hintText: 'ادخل الرمز المكون من 6 أرقام',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'تحقق',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                final tempUserId = (widget.userId != null && widget.userId!.isNotEmpty)
                    ? widget.userId!
                    : '';

                if (tempUserId.isEmpty) {
                  setState(() {
                    _errorMessage = 'لا يمكن إعادة الإرسال: معرف المستخدم غير متوفر';
                  });
                  return;
                }

                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });

                try {
                  final result = await AuthService.resendVerificationCode(
                    tempUserId: tempUserId,
                    type: 'email',
                  );

                  if (!mounted) return;

                  if (result['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result['message'] ?? 'تم إعادة إرسال الرمز'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    setState(() {
                      _errorMessage = result['error'] ?? result['message'] ?? 'فشل في إعادة إرسال الرمز';
                    });
                  }
                } catch (e) {
                  setState(() {
                    _errorMessage = 'فشل في إعادة إرسال الرمز: $e';
                  });
                } finally {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              },
              child: const Text(
                'إعادة إرسال الرمز',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _verificationCodeController.dispose();
    super.dispose();
  }
}
