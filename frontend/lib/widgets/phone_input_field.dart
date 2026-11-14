import 'package:flutter/material.dart';
import 'iraqi_mobile_field.dart';

class PhoneInputField extends StatelessWidget {
  final TextEditingController controller;
  final String countryCode;
  final ValueChanged<String>? onCountryChanged;
  final FormFieldValidator<String>? validator;
  const PhoneInputField({
    super.key,
    required this.controller,
    required this.countryCode,
    this.onCountryChanged,
    this.validator,
  });
  @override
  Widget build(BuildContext context) =>
      IraqiMobileField(controller: controller, validator: validator);
}
