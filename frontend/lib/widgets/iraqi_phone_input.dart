import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isValid = true;
  String _validationMessage = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validateInput);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_validateInput);
    super.dispose();
  }

  void _validateInput() {
    String phone = widget.controller.text;
    bool isValid = phone.isEmpty || ValidationHelper.isValidIraqiPhoneInput(phone);
    
    setState(() {
      _isValid = isValid;
      if (!isValid && phone.isNotEmpty) {
        if (phone.startsWith('07')) {
          _validationMessage = 'يجب أن يكون الرقم 11 رقماً بصيغة 07XXXXXXXX';
        } else if (phone.startsWith('7')) {
          _validationMessage = 'يجب أن يكون الرقم 10 أرقام بصيغة 7XXXXXXXX';
        } else {
          _validationMessage = 'الرقم يجب أن يبدأ بـ 07 أو 7';
        }
      } else {
        _validationMessage = '';
      }
    });
  }

  String _formatInput(String text) {
    // إزالة كل شيء عدا الأرقام
    String digitsOnly = text.replaceAll(RegExp(r'[^\d]'), '');
    
    // تحديد طول الحد الأقصى حسب النمط
    int maxLength;
    if (digitsOnly.startsWith('07')) {
      maxLength = 11; // 07XXXXXXXX
    } else if (digitsOnly.startsWith('7')) {
      maxLength = 10; // 7XXXXXXXX
    } else {
      maxLength = 11; // افتراضي
    }
    
    // قطع النص إذا تجاوز الحد الأقصى
    if (digitsOnly.length > maxLength) {
      digitsOnly = digitsOnly.substring(0, maxLength);
    }
    
    return digitsOnly;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.errorText != null || !_isValid 
                  ? Colors.red 
                  : Colors.grey.shade300,
              width: 1,
            ),
            color: widget.fillColor ?? Colors.grey.shade50,
          ),
          child: Row(
            children: [
              // كود البلد (ثابت)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border(
                    left: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🇮🇶',
                      style: TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '+964',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              
              // حقل إدخال الرقم
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  enabled: widget.enabled,
                  readOnly: widget.readOnly,
                  onTap: widget.onTap,
                  onChanged: (value) {
                    String formatted = _formatInput(value);
                    if (formatted != value) {
                      widget.controller.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                    widget.onChanged?.call(formatted);
                  },
                  onEditingComplete: widget.onEditingComplete,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11), // الحد الأقصى 11 رقم
                  ],
                  style: widget.textStyle ?? const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? '7XX XXX XXXX',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    contentPadding: widget.contentPadding ?? 
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    fillColor: Colors.transparent,
                    filled: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // رسالة التحقق
        if ((widget.errorText != null && widget.errorText!.isNotEmpty) || 
            (!_isValid && _validationMessage.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 12),
            child: Text(
              widget.errorText ?? _validationMessage,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ),
        
        // نص إرشادي
        if (_isValid && widget.controller.text.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 12),
            child: Text(
              'أدخل رقم الهاتف بصيغة 07XXXXXXXX أو 7XXXXXXXX',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
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
            '🇮🇶 +964',
            style: textStyle ?? TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            displayPhone,
            style: textStyle ?? const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
