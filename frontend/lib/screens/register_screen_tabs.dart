import 'package:flutter/material.dart';
import 'customer_phone_auth_screen.dart';

class RegisterScreenTabs extends StatelessWidget {
  const RegisterScreenTabs({super.key});
  @override
  Widget build(BuildContext context) =>
      const CustomerPhoneAuthScreen(registration: true);
}
