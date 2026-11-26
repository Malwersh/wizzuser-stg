import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff5f6fa),
    appBar: AppBar(
      title: const Text('اللغة'),
      centerTitle: true,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.secondaryDark,
      elevation: 0,
    ),
    body: const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.language, color: AppColors.secondaryDark),
              title: Text('العربية'),
              subtitle: Text('لغة التطبيق الحالية'),
              trailing: Icon(
                Icons.check_circle_outline,
                color: AppColors.secondaryDark,
              ),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'التطبيق متاح حاليًا باللغة العربية.',
            style: TextStyle(color: Color(0xff647184)),
          ),
        ],
      ),
    ),
  );
}
