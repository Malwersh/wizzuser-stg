import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/home_filters.dart';

class HomeFilterStrip extends StatelessWidget {
  final List<HomeFilter> items;
  final bool Function(HomeFilter) selected;
  final void Function(HomeFilter) onTap;
  const HomeFilterStrip({
    super.key,
    required this.items,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final f = items[i], active = selected(f);
        return Semantics(
          button: true,
          selected: active,
          child: Material(
            color: active ? AppColors.secondaryDark : const Color(0xFFF1F2F4),
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onTap(f),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              active ? Colors.white : AppColors.secondaryDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (['menuPrice', 'sort'].contains(f.kind)) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.expand_more,
                          size: 16,
                          color:
                              active ? Colors.white : AppColors.secondaryDark,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
