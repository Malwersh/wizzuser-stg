import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/browsing_location_service.dart';
import '../services/session_service.dart';
import 'address_gate_screen.dart';

class CountrySettingsScreen extends StatelessWidget {
  final BrowsingLocationService? browsingService;
  final VoidCallback? onChooseRegion;
  const CountrySettingsScreen({
    super.key,
    this.browsingService,
    this.onChooseRegion,
  });
  @override
  Widget build(BuildContext context) {
    final browsing = browsingService ?? BrowsingLocationService.instance;
    return Scaffold(
      backgroundColor: const Color(0xfff5f6fa),
      appBar: AppBar(
        title: const Text('البلد ومنطقة التوصيل'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.secondaryDark,
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: browsing,
        builder:
            (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Card(
                  color: Colors.white,
                  elevation: 0,
                  child: ListTile(
                    leading: Text('🇮🇶', style: TextStyle(fontSize: 28)),
                    title: Text('العراق'),
                    subtitle: Text('بلد الخدمة الحالي'),
                    trailing: Icon(
                      Icons.check_circle_outline,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.white,
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.secondaryDark,
                    ),
                    title: const Text('منطقة التوصيل'),
                    subtitle: Text(
                      browsing.selection?.regionName ??
                          'لم تُحدّد منطقة التوصيل بعد',
                    ),
                    trailing: const Icon(
                      Icons.chevron_left,
                      textDirection: ui.TextDirection.ltr,
                      color: AppColors.secondaryDark,
                    ),
                    onTap:
                        onChooseRegion ??
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => AddressGateScreen(
                                  isGuest:
                                      SessionService.instance.currentUserId ==
                                      null,
                                  showBackButton: true,
                                ),
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'اختر نقطة التوصيل داخل المناطق المخدومة في العراق لعرض المتاجر ورسوم التوصيل المناسبة.',
                  style: TextStyle(color: Color(0xff647184), height: 1.6),
                ),
              ],
            ),
      ),
    );
  }
}
