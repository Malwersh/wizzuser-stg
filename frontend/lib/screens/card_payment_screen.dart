import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class CardPaymentScreen extends StatefulWidget {
  final void Function(String cardNumber, String expiry, String cvv) onCardAdded;
  const CardPaymentScreen({super.key, required this.onCardAdded});

  @override
  State<CardPaymentScreen> createState() => _CardPaymentScreenState();
}

class _CardPaymentScreenState extends State<CardPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  void _handleAddCard() {
    if (_formKey.currentState!.validate()) {
      final card = _cardNumberController.text;
      final expiry = _expiryController.text;
      final cvv = _cvvController.text;
      // تحقق Luhn
      bool validCard = _validateCardLuhn(card);
      // تحقق تاريخ الانتهاء
      final now = DateTime.now();
      final expParts = expiry.split('/');
      bool validExpiry = false;
      if (expParts.length == 2) {
        final mm = int.tryParse(expParts[0]);
        final yy = int.tryParse(expParts[1]);
        if (mm != null && yy != null && mm >= 1 && mm <= 12) {
          final expDate = DateTime(2000 + yy, mm + 1);
          validExpiry = expDate.isAfter(now);
        }
      }
      bool validCvv = cvv.length == 3 || cvv.length == 4;
      if (validCard && validExpiry && validCvv) {
        // نجح التحقق
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 16),
                Text('تمت إضافة البطاقة بنجاح!', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pop(); // يغلق AlertDialog
            widget.onCardAdded(card, expiry, cvv);
            Navigator.of(context).pop(); // يغلق شاشة البطاقة
          }
        });
      } else {
        // فشل التحقق
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('معلومات البطاقة غير صحيحة، يرجى التحقق والمحاولة مجدداً'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعبئة جميع الحقول بشكل صحيح'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _validateCardLuhn(String cardNumber) {
    cardNumber = cardNumber.replaceAll(' ', '');
    if (cardNumber.length < 12 || cardNumber.length > 19) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int n = int.tryParse(cardNumber[i]) ?? 0;
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('إدخال معلومات البطاقة'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _cardNumberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'رقم البطاقة'),
                  validator: (v) => v == null || v.length < 12 ? 'أدخل رقم بطاقة صحيح' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _expiryController,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(labelText: 'تاريخ الانتهاء (MM/YY)'),
                        validator: (v) => v == null || v.isEmpty ? 'أدخل تاريخ الانتهاء' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _cvvController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'CVV'),
                        validator: (v) => v == null || v.length < 3 ? 'أدخل CVV صحيح' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _handleAddCard,
                  child: const Text('إضافة البطاقة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
