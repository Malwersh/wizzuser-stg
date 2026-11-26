import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_colors.dart';
import 'promotion_appearance.dart';

class HomeDiscoveryHeader extends StatelessWidget {
  final String address;
  final Color? background;
  final Widget? promotion;
  final String? greeting;
  final VoidCallback onAddress, onNotifications, onAccount, onCart;
  final bool unread;
  final int cartCount;
  const HomeDiscoveryHeader({
    super.key,
    required this.address,
    this.background,
    this.promotion,
    this.greeting,
    required this.onAddress,
    required this.onNotifications,
    required this.onAccount,
    required this.onCart,
    required this.unread,
    this.cartCount = 0,
  });
  @override
  Widget build(BuildContext context) {
    final ink =
        background == null
            ? AppColors.secondaryDark
            : promotionForeground(background!);
    Widget action(
      IconData icon,
      String label,
      VoidCallback tap, {
      bool badge = false,
      String? count,
    }) => SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color:
            background == null
                ? const Color(0xFFEEF2F9)
                : Colors.white.withValues(alpha: .12),
        elevation: 2,
        shadowColor: Colors.black12,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: tap,
          child: Tooltip(
            message: label,
            child: Center(
              child: Badge(
                isLabelVisible: badge,
                label: count == null ? null : Text(count),
                backgroundColor: AppColors.secondaryDark,
                child: Icon(icon, size: 26, color: ink),
              ),
            ),
          ),
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          ink == Colors.white
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
      child: DecoratedBox(
        decoration: BoxDecoration(color: background ?? Colors.white),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              6,
              16,
              promotion == null && background == null ? 24 : 4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onAddress,
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'التوصيل إلى',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    background == null
                                        ? const Color(0xFF647184)
                                        : ink.withValues(alpha: .8),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 18,
                                  color: ink,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    address,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                Icon(Icons.expand_more, size: 16, color: ink),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: action(
                        Icons.notifications_none_rounded,
                        'الإشعارات',
                        onNotifications,
                        badge: unread,
                      ),
                    ),
                  ],
                ),
                if (greeting != null && promotion == null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        greeting!,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          color:
                              background == null
                                  ? const Color(0xFF647184)
                                  : ink.withValues(alpha: .8),
                        ),
                      ),
                    ),
                  ),
                if (promotion != null) promotion!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeTypeCategory {
  final String id, label, image;
  final String? imageUrl, imageKey;
  const HomeTypeCategory(
    this.id,
    this.label,
    this.image, {
    this.imageUrl,
    this.imageKey,
  });
  String? get imageCacheKey =>
      imageKey == null ? imageUrl : 'home-navigation:$imageKey';
}

class HomeTypeCategories extends StatelessWidget {
  final List<HomeTypeCategory> categories;
  final String selected;
  final ValueChanged<String> onChanged;
  const HomeTypeCategories({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final c = categories[index], active = c.id == selected;
        return Semantics(
          selected: active,
          button: true,
          label: c.label,
          child: Material(
            animationDuration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
            color: active ? AppColors.primary : const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(36),
            child: InkWell(
              borderRadius: BorderRadius.circular(36),
              onTap: () => onChanged(c.id),
              child: SizedBox(
                width: 66,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child:
                          c.id == 'all'
                              ? const Icon(
                                Icons.grid_view_rounded,
                                color: AppColors.secondaryDark,
                                size: 24,
                              )
                              : ClipOval(
                                child:
                                    c.imageUrl != null &&
                                            Uri.tryParse(c.imageUrl!)?.scheme ==
                                                'https'
                                        ? CachedNetworkImage(
                                          imageUrl: c.imageUrl!,
                                          cacheKey: c.imageCacheKey,
                                          useOldImageOnUrlChange: true,
                                          fadeInDuration: Duration.zero,
                                          fadeOutDuration: Duration.zero,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorWidget:
                                              (_, __, ___) => Image.asset(
                                                c.image,
                                                fit: BoxFit.cover,
                                              ),
                                        )
                                        : Image.asset(
                                          c.image,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                              ),
                    ),
                    const SizedBox(height: 7),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Tooltip(
                        message: c.label,
                        child: Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                            color: AppColors.secondaryDark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
