// lib/widgets/password_strength_indicator.dart

import 'package:flutter/material.dart';
import '../utils/validators.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({
    super.key,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequirement(
          'حرف أبجدي (أ - ي)',
          Validators.hasArabicLetters(password),
        ),
        const SizedBox(height: 4),
        _buildRequirement(
          'إذا كنت تستخدم أحرفاً إنجليزية، يجب أن تتضمن كلمة المرور الحروف الكبيرة (A-Z) والحروف الصغيرة (a-z)',
          Validators.hasEnglishRequirement(password),
        ),
        const SizedBox(height: 4),
        _buildRequirement(
          'رقم (0 - 9)',
          Validators.hasNumber(password),
        ),
        const SizedBox(height: 4),
        _buildRequirement(
          'رمز (@#\$%^&*_-+=!,.?/)',
          Validators.hasSpecialChar(password),
        ),
      ],
    );
  }

  Widget _buildRequirement(String text, bool isValid) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: isValid ? Colors.green : Colors.grey[400],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isValid ? Colors.green[700] : Colors.grey[600],
              fontWeight: isValid ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
