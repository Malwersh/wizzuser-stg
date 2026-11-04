import 'rotating_search_hint.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class CustomBottomNavigation extends StatelessWidget {
  final List<String> searchHints;
  final int hintIntervalSeconds;
  final int currentIndex, cartCount;
  final ValueChanged<int> onTap;
  const CustomBottomNavigation({
    super.key,
    required this.currentIndex,
    this.searchHints = const ['ابحث عن مطعم أو متجر'],
    this.hintIntervalSeconds = 5,
    required this.onTap,
    this.cartCount = 0,
  });
  @override
  Widget build(BuildContext context) {
    final buttonSize = MediaQuery.sizeOf(context).width < 360 ? 42.0 : 46.0;
    Widget circle(
      IconData icon,
      String label,
      int index, {
      bool badge = false,
    }) => Semantics(
      button: true,
      selected: currentIndex == index,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Material(
            color:
                currentIndex == index ? const Color(0xFFF0F3F7) : Colors.white,
            elevation: 5,
            shadowColor: const Color(0x4000296B),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onTap(index),
              child: Center(
                child: Badge(
                  isLabelVisible: badge && cartCount > 0,
                  label: Text(cartCount > 99 ? '99+' : '$cartCount'),
                  backgroundColor: AppColors.secondaryDark,
                  textColor: Colors.white,
                  child: Icon(
                    icon,
                    size: 23,
                    color:
                        currentIndex == index
                            ? AppColors.secondaryDark
                            : const Color(0xFF647184),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0xEFFFFFFF), Colors.white],
          stops: [0, .3, .65],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: SizedBox(
          height: 52,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                circle(Icons.home_rounded, 'الرئيسية', 0),
                const SizedBox(width: 6),
                circle(Icons.shopping_cart_outlined, 'السلة', 7, badge: true),
                const SizedBox(width: 6),
                Expanded(
                  child: Material(
                    color: Colors.white,
                    elevation: 5,
                    shadowColor: const Color(0x4000296B),
                    borderRadius: BorderRadius.circular(30),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => onTap(6),
                      child: SizedBox(
                        height: 48,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              const Icon(
                                Icons.search,
                                size: 21,
                                color: Color(0xFF647184),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: RotatingSearchHint(
                                  hints: searchHints,
                                  intervalSeconds: hintIntervalSeconds,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                circle(Icons.map_outlined, 'تصفح المطاعم', 3),
                const SizedBox(width: 6),
                circle(Icons.person_outline_rounded, 'حسابي', 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
