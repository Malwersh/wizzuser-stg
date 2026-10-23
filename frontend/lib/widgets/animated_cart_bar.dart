// lib/widgets/animated_cart_bar.dart
import '../constants/app_colors.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/store.dart';
import '../screens/cart_screen.dart';
import 'modern_cart_icon.dart';

class AnimatedCartBar extends StatefulWidget {
  final String storeName;
  final bool isExpanded;
  final String? storeId; // إضافة معرف المطعم
  final List<Store>? stores; // إضافة قائمة المتاجر

  const AnimatedCartBar({
    super.key,
    required this.storeName,
    required this.isExpanded,
    this.storeId,
    this.stores,
  });

  @override
  State<AnimatedCartBar> createState() => _AnimatedCartBarState();
}

class _AnimatedCartBarState extends State<AnimatedCartBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtl;
  late final Animation<double> _scaleAnim;
  late int _prevCount;
  Timer? _timer;
  AppStateProvider? _appStateProvider; // إضافة مرجع للـ AppStateProvider

  static const Color _primaryPink = AppColors.primary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // حفظ مرجع للـ AppStateProvider هنا بدلاً من في dispose()
    _appStateProvider = context.read<AppStateProvider>();
  }

  @override
  void initState() {
    super.initState();

    _pulseCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: widget.isExpanded ? 1.025 : 1.2),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: widget.isExpanded ? 1.025 : 1.2, end: 1.0),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));

    final appState = context.read<AppStateProvider>();
    _prevCount = _quantity(appState);

    if (widget.isExpanded) {
      // نبضة عند إضافة عنصر جديد فقط
      appState.addListener(_onCartChanged);
    } else {
      // نبضة كل 5 ثوانٍ
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        _pulseCtl.forward(from: 0);
      });
    }
  }

  int _quantity(AppStateProvider state) => state.cartItems
      .where(
        (item) => widget.storeId == null || item['store_id'] == widget.storeId,
      )
      .fold<int>(0, (sum, item) => sum + (item['quantity'] as num).toInt());

  void _onCartChanged() {
    if (!mounted) return;
    final currentCount = _quantity(
      _appStateProvider ?? context.read<AppStateProvider>(),
    );
    if (currentCount != _prevCount) {
      final increased = currentCount > _prevCount;
      _prevCount = currentCount;
      if (increased) _pulseCtl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    if (widget.isExpanded && _appStateProvider != null) {
      _appStateProvider!.removeListener(_onCartChanged);
    }
    _timer?.cancel();
    _pulseCtl.dispose();
    super.dispose();
  }

  /// حل اسم المطعم بنفس المنطق المستخدم في الشاشات الأخرى
  String _resolveStoreName() {
    final rejectedNames = ['متجر', 'المطعم', 'عربة التسوق'];

    // إذا كان الاسم المرسل صالح (ليس فارغ وليس من الأسماء المرفوضة)
    if (widget.storeName.isNotEmpty &&
        !rejectedNames.contains(widget.storeName)) {
      return widget.storeName;
    }

    // محاولة الحصول على الاسم من معرف المطعم
    if (widget.storeId != null && widget.stores != null) {
      final store = widget.stores!.firstWhere(
        (s) => s.id == widget.storeId,
        orElse:
            () => Store(
              id: widget.storeId!,
              name: 'متجر غير معروف',
              image: '',
              logoUrl: '',
              isOpen: true,
              fee: '',
              rating: '0.0',
              reviews: '0',
              distance: '',
              time: '',
              address: '',
              combos: [],
              sandwiches: [],
              drinks: [],
              extras: [],
              specialties: [],
            ),
      );
      if (!rejectedNames.contains(store.name)) {
        return store.name;
      }
    }

    // آخر حل: الحصول على الاسم من عناصر السلة
    final appState = context.read<AppStateProvider>();
    if (appState.cartItems.isNotEmpty) {
      final storeName = appState.cartItems.first['store_name'] as String?;
      if (storeName != null &&
          storeName.isNotEmpty &&
          !rejectedNames.contains(storeName)) {
        return storeName;
      }
    }

    return 'متجر غير معروف';
  }

  @override
  Widget build(BuildContext context) {
    final storeId = widget.storeId;

    return Selector<AppStateProvider, ({int count, double total})>(
      selector: (context, appState) {
        if (storeId != null) {
          return (
            count: _quantity(appState),
            total: appState.getCartTotalForStore(storeId),
          );
        }
        return (count: _quantity(appState), total: appState.cartTotal);
      },
      builder: (context, cartData, child) {
        final cartCount = cartData.count;
        if (cartCount == 0) return const SizedBox.shrink();

        final alignment =
            widget.isExpanded ? Alignment.bottomCenter : Alignment.bottomLeft;
        final bottomSafe = MediaQuery.paddingOf(context).bottom;
        final padding =
            widget.isExpanded
                ? EdgeInsets.fromLTRB(24, 12, 24, 12 + bottomSafe)
                : EdgeInsets.only(left: 24, bottom: 12 + bottomSafe);

        return Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: GestureDetector(
              onTap: () {
                final resolvedStoreName = _resolveStoreName();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => CartScreen(
                          storeName: resolvedStoreName,
                          storeId: widget.storeId,
                          stores: widget.stores,
                        ),
                  ),
                );
              },
              child: Material(
                type: MaterialType.transparency,
                child:
                    widget.isExpanded
                        ? ScaleTransition(
                          scale: _scaleAnim,
                          child: _buildExpanded(cartCount),
                        )
                        : _buildCollapsed(cartCount),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpanded(int count) {
    return Container(
      key: const ValueKey('restaurant-cart-pill'),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 32,
            child: Icon(
              Icons.shopping_cart_outlined,
              color: AppColors.secondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'عرض السلة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _resolveStoreName(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              maxLines: 1,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsed(int count) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _primaryPink,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ModernCartIcon(
              color: AppColors.secondary,
              size: 28,
              hasGlowEffect: false,
              isGlassmorphic: false,
              badgeCount: count,
            ),
          ],
        ),
      ),
    );
  }
}
