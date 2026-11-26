import 'package:flutter/material.dart';
import 'addresses_screen.dart';

/// Compatibility entry. All address management uses the current account-bound service.
class AddressManagementScreen extends StatelessWidget {
  final String token, userId;
  const AddressManagementScreen({
    super.key,
    required this.token,
    required this.userId,
  });
  @override
  Widget build(BuildContext context) => const AddressesScreen();
}
