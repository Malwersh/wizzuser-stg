import 'package:flutter/material.dart';
import 'iraqi_mobile_field.dart';
import '../utils/validation_helper.dart';

/// Widget مخصص لإدخال أرقام الهاتف العراقية
/// يعرض كود البلد +964 منفصلاً ويقبل الصيغ: 07XXXXXXXX أو 7XXXXXXXX
class IraqiPhoneInput extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final String? errorText;
  final bool enabled;
  final Function(String)? onChanged;
  final Function()? onEditingComplete;
  final VoidCallback? onTap;
  final bool readOnly;
  final TextStyle? textStyle;
  final Color? fillColor;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final EdgeInsets? contentPadding;

  const IraqiPhoneInput({
    super.key,
    required this.controller,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.onEditingComplete,
    this.onTap,
    this.readOnly = false,
    this.textStyle,
    this.fillColor,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.contentPadding,
  });

  @override
  State<IraqiPhoneInput> createState() => _IraqiPhoneInputState();
}

class _IraqiPhoneInputState extends State<IraqiPhoneInput> {
  @override
  Widget build(BuildContext context) => IraqiMobileField(
    controller: widget.controller,
    enabled: widget.enabled,
    readOnly: widget.readOnly,
    onChanged: widget.onChanged,
    onEditingComplete: widget.onEditingComplete,
    onTap: widget.onTap,
    style: widget.textStyle,
    decoration: InputDecoration(
      errorText: widget.errorText,
      fillColor: widget.fillColor,
      filled: widget.fillColor != null,
      border: widget.border,
      enabledBorder: widget.enabledBorder,
      focusedBorder: widget.focusedBorder,
      errorBorder: widget.errorBorder,
      contentPadding: widget.contentPadding,
    ),
  );
}

/// Widget مبسط لعرض رقم الهاتف مع كود البلد
class IraqiPhoneDisplay extends StatelessWidget {
  final String phoneNumber;
  final TextStyle? textStyle;
  final Color? backgroundColor;
  final EdgeInsets? padding;

  const IraqiPhoneDisplay({
    super.key,
    required this.phoneNumber,
    this.textStyle,
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    String displayPhone = ValidationHelper.formatPhoneDisplay(phoneNumber);

    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '🇮🇶',
            style:
                textStyle ??
                TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            displayPhone,
            style:
                textStyle ??
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
