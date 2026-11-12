import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_colors.dart';
import 'home_discovery_header.dart';

class HomeTopicStrip extends StatelessWidget {
  final List<HomeTypeCategory> categories;
  final String selected;
  final ValueChanged<String> onChanged;
  const HomeTopicStrip({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 90 + (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0, 22),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (context, i) {
        final c = categories[i], active = c.id == selected;
        Widget fallback() =>
            c.id == 'all'
                ? const Icon(
                  Icons.grid_view_rounded,
                  color: AppColors.secondaryDark,
                  size: 25,
                )
                : Image.asset(c.image, fit: BoxFit.cover);
        return Semantics(
          key: ValueKey(c.id),
          selected: active,
          button: true,
          label: c.label,
          child: InkWell(
            onTap: () => onChanged(c.id),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration:
                        MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: 54,
                    height: 54,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF5F6F8),
                      border: Border.all(
                        color:
                            active
                                ? AppColors.primary
                                : const Color(0xFFD5D9E0),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child:
                          c.imageUrl != null &&
                                  Uri.tryParse(c.imageUrl!)?.scheme == 'https'
                              ? CachedNetworkImage(
                                imageUrl: c.imageUrl!,
                                cacheKey: c.imageCacheKey,
                                useOldImageOnUrlChange: true,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => fallback(),
                              )
                              : fallback(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryDark,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
