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
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));

    final appState = context.read<AppStateProvider>();
    _prevCount = appState.cartItems.length;

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

  void _onCartChanged() {
    // فحص أن الWidget لا يزال mounted
    if (!mounted) return;
    
    // Debug: AnimatedCartBar: _onCartChanged called
    final appState = _appStateProvider ?? context.read<AppStateProvider>();
    final currentCount = appState.cartItems.length;
    
    // التحقق من تغيير العدد فقط إذا كان الWidget مخصص لنفس المطعم
    if (widget.storeId != null) {
      final storeItemsCount = appState.getCartItemsCountForStore(widget.storeId!);
      if (storeItemsCount != _prevCount) {
        _prevCount = storeItemsCount;
        if (mounted) {
          _pulseCtl.forward(from: 0);
        }
        // Debug: AnimatedCartBar: Pulse animation triggered for store
      }
    } else {
      // للشريط العام (بدون معرف مطعم)
      if (currentCount != _prevCount) {
        _prevCount = currentCount;
        if (mounted) {
          _pulseCtl.forward(from: 0);
        }
        // Debug: AnimatedCartBar: Pulse animation triggered
      }
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
    if (widget.storeName.isNotEmpty && !rejectedNames.contains(widget.storeName)) {
      return widget.storeName;
    }
    
    // محاولة الحصول على الاسم من معرف المطعم
    if (widget.storeId != null && widget.stores != null) {
      final store = widget.stores!.firstWhere(
        (s) => s.id == widget.storeId,
        orElse: () => Store(
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
      if (storeName != null && storeName.isNotEmpty && !rejectedNames.contains(storeName)) {
        return storeName;
      }
    }
    
    return 'متجر غير معروف';
  }

  @override
  Widget build(BuildContext context) {
    // Debug: AnimatedCartBar build: isExpanded = ${widget.isExpanded}
    
    // إذا كان لدينا معرف مطعم، نتحقق من عناصر هذا المطعم فقط
    if (widget.storeId != null) {
      return Selector<AppStateProvider, int>(
        selector: (context, appState) => appState.getCartItemsCountForStore(widget.storeId!),
        builder: (context, cartCount, child) {
          if (cartCount == 0) return const SizedBox.shrink();

          final alignment = widget.isExpanded
              ? Alignment.bottomCenter
              : Alignment.bottomLeft;
          final padding = widget.isExpanded
              ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
              : const EdgeInsets.only(left: 24, bottom: 12);

          return Align(
            alignment: alignment,
            child: Padding(
              padding: padding,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: GestureDetector(
                  onTap: () {
                    // Debug: AnimatedCartBar tapped! Navigating to CartScreen...
                    final resolvedStoreName = _resolveStoreName();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CartScreen(
                          storeName: resolvedStoreName,
                          storeId: widget.storeId,
                          stores: widget.stores,
                        ),
                      ),
                    );
                  },
                  child: widget.isExpanded
                      ? _buildExpanded(cartCount)
                      : _buildCollapsed(cartCount),
                ),
              ),
            ),
          );
        },
      );
    }
    
    // الكود الأصلي للشريط العام (بدون معرف مطعم)
    return Selector<AppStateProvider, int>(
      selector: (context, appState) => appState.cartItems.length,
      builder: (context, cartCount, child) {
        if (cartCount == 0) return const SizedBox.shrink();

        final alignment = widget.isExpanded
            ? Alignment.bottomCenter
            : Alignment.bottomLeft;
        final padding = widget.isExpanded
            ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
            : const EdgeInsets.only(left: 24, bottom: 12);

        return Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: GestureDetector(
                onTap: () {
                  // Debug: AnimatedCartBar tapped! Navigating to CartScreen...
                  final resolvedStoreName = _resolveStoreName();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CartScreen(
                        storeName: resolvedStoreName,
                        storeId: widget.storeId,
                        stores: widget.stores,
                      ),
                    ),
                  );
                },
                child: widget.isExpanded
                    ? _buildExpanded(cartCount)
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
      height: 56,
      decoration: BoxDecoration(
        color: _primaryPink,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ModernCartIcon(
              color: AppColors.secondary,
              size: 24,
              hasGlowEffect: false,
              isGlassmorphic: false,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'عرض السلة',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _resolveStoreName(),
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 32,
                maxWidth: 48,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: _primaryPink,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsed(int count) {
    return Container(
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
    );
  }
}
