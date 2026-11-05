import 'package:flutter/material.dart';

class AccountMoreScreen extends StatelessWidget {
  const AccountMoreScreen({
    super.key,
    required this.onSupport,
    required this.onDeleteAccount,
    required this.onLogout,
  });

  final VoidCallback onSupport;
  final VoidCallback onDeleteAccount;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المزيد')),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('الدردشة مع الدعم'),
              trailing: const Icon(Icons.chevron_left),
              onTap: onSupport,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('حذف الحساب'),
              trailing: const Icon(Icons.chevron_left),
              onTap: onDeleteAccount,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('تسجيل الخروج'),
              trailing: const Icon(Icons.chevron_left),
              onTap: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}
