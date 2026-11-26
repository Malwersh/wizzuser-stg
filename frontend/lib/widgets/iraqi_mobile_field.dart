import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/iraqi_phone.dart';

/// The caller retains an E.164 value; the visible field shows only the local part.
class IraqiMobileField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled, readOnly;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onEditingComplete, onTap;
  final TextStyle? style;
  const IraqiMobileField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.readOnly = false,
    this.decoration = const InputDecoration(labelText: 'رقم الهاتف'),
    this.onChanged,
    this.validator,
    this.onEditingComplete,
    this.onTap,
    this.style,
  });
  @override
  State<IraqiMobileField> createState() => _IraqiMobileFieldState();
}

class _IraqiMobileFieldState extends State<IraqiMobileField> {
  late final TextEditingController visible;
  bool writing = false;
  @override
  void initState() {
    super.initState();
    visible = TextEditingController(
      text: IraqiPhone.nationalInput(widget.controller.text),
    );
    widget.controller.addListener(sync);
  }

  void sync() {
    if (writing) return;
    final text = IraqiPhone.nationalInput(widget.controller.text);
    if (text != visible.text) {
      visible.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void didUpdateWidget(covariant IraqiMobileField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(sync);
      widget.controller.addListener(sync);
      sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(sync);
    visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: TextFormField(
      controller: visible,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      onEditingComplete: widget.onEditingComplete,
      onTap: widget.onTap,
      style: widget.style,
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        TextInputFormatter.withFunction((old, value) {
          final text = IraqiPhone.nationalInput(value.text);
          if (text == value.text) return value;
          return TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }),
      ],
      decoration: widget.decoration.copyWith(
        prefixIcon: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🇮🇶 +964', style: TextStyle(color: Color(0xff00296b))),
            ],
          ),
        ),
        prefixText: null,
        hintText: '7XX XXX XXXX',
      ),
      validator: (_) => widget.validator?.call(widget.controller.text),
      onChanged: (value) {
        final canonical =
            IraqiPhone.valid(value) ? IraqiPhone.normalize(value) : value;
        writing = true;
        widget.controller.value = TextEditingValue(
          text: canonical,
          selection: TextSelection.collapsed(offset: canonical.length),
        );
        writing = false;
        widget.onChanged?.call(canonical);
      },
    ),
  );
}
