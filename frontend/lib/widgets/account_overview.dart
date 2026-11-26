import '../utils/iraqi_phone.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AccountOverview extends StatelessWidget {
  final String name, phone;
  final String? photoUrl;
  final VoidCallback? onFavorites;
  final VoidCallback onWallet, onOrders;
  const AccountOverview({
    super.key,
    required this.name,
    required this.phone,
    this.photoUrl,
    this.onFavorites,
    required this.onWallet,
    required this.onOrders,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    IraqiPhone.display(phone),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xff647184),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            ClipOval(
              child: SizedBox(
                width: 68,
                height: 68,
                child:
                    photoUrl?.startsWith('https://') == true
                        ? Image.network(
                          photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatar(),
                        )
                        : _avatar(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AccountShortcuts(
          onFavorites: onFavorites,
          onWallet: onWallet,
          onOrders: onOrders,
        ),
      ],
    );
  }

  Widget _avatar() => const ColoredBox(
    color: Color(0xffeef2f9),
    child: Icon(
      Icons.person_outline_rounded,
      size: 34,
      color: AppColors.secondaryDark,
    ),
  );
}

class AccountShortcuts extends StatelessWidget {
  final VoidCallback? onFavorites;
  final VoidCallback onWallet, onOrders;
  const AccountShortcuts({
    super.key,
    this.onFavorites,
    required this.onWallet,
    required this.onOrders,
  });
  @override
  Widget build(BuildContext context) {
    Widget shortcut(String label, IconData icon, VoidCallback onTap) =>
        Expanded(
          child: Material(
            color: const Color(0xfff4f5f7),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 27, color: AppColors.secondaryDark),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onFavorites != null) ...[
          shortcut('المفضلة', Icons.favorite_border_rounded, onFavorites!),
          const SizedBox(width: 12),
        ],
        shortcut('المحفظة', Icons.account_balance_wallet_outlined, onWallet),
        const SizedBox(width: 12),
        shortcut('الطلبات', Icons.receipt_long_outlined, onOrders),
      ],
    );
  }
}

class GuestAccountOverview extends StatelessWidget {
  final VoidCallback onLogin, onRegister;
  const GuestAccountOverview({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أهلًا، ضيفنا الكريم',
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryDark,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'احتفظ بعناوينك وتابع طلباتك من مكان واحد.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Color(0xff647184),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const CircleAvatar(
            radius: 32,
            backgroundColor: Color(0xffeef2f9),
            child: Icon(
              Icons.person_outline_rounded,
              size: 32,
              color: AppColors.secondaryDark,
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: onLogin,
        icon: const Icon(Icons.login_rounded, size: 20),
        label: const Text('تسجيل الدخول'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Center(
        child: TextButton(
          onPressed: onRegister,
          style: TextButton.styleFrom(foregroundColor: AppColors.secondaryDark),
          child: const Text('جديد في ويز؟ إنشاء حساب'),
        ),
      ),
    ],
  );
}
