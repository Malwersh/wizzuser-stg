import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/home_promotion.dart';
import 'promotion_appearance.dart';
import '../../models/delivery_address.dart';
import '../../services/home_slideshow_service.dart';
import '../../services/platform_benefits_service.dart';
import '../../services/session_service.dart';
import '../../services/browsing_location_service.dart';
import '../../services/delivery_address_manager.dart';

/// Data refresh is separate from the animation: cycling never makes API requests.
class HomePromotionHeader extends StatefulWidget {
  final HomePromotionSettings settings;
  final Widget Function(Color? background, Widget? promotion) headerBuilder;
  final ValueChanged<HomePromotion> onOffer;
  const HomePromotionHeader({
    super.key,
    required this.settings,
    required this.headerBuilder,
    required this.onOffer,
  });
  @override
  State<HomePromotionHeader> createState() => _HomePromotionHeaderState();
}

class _HomePromotionHeaderState extends State<HomePromotionHeader>
    with WidgetsBindingObserver {
  List<HomePromotion> _items = [];
  HomePromotionSettings? _serverSettings;
  HomePromotionSettings get _settings => _serverSettings ?? widget.settings;
  Timer? _refresh, _expiry;
  StreamSubscription<DeliveryAddress?>? _addresses;
  int _request = 0;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionService.instance.addListener(_scopeChanged);
    BrowsingLocationService.instance.addListener(_scopeChanged);
    _addresses = DeliveryAddressManager.instance.addressStream.listen(
      (_) => _scopeChanged(),
    );
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_foreground) _load();
    });
  }

  @override
  void didUpdateWidget(covariant HomePromotionHeader old) {
    super.didUpdateWidget(old);
    if (_key(old.settings) != _key(widget.settings)) _scopeChanged();
  }

  String _key(HomePromotionSettings s) =>
      '${s.enabled}|${s.source}|${s.selection}|${s.startAt}|${s.endAt}|${s.scenes}';
  void _scopeChanged() {
    _request++;
    _serverSettings = null;
    _expiry?.cancel();
    if (mounted) setState(() => _items = []);
    _load();
  }

  Future<List<HomePromotion>> _loadBenefits() async {
    final region = BrowsingLocationService.instance.selection?.regionId;
    final savedRegion = DeliveryAddressManager.instance.activeAddress?.regionId;
    if (region != null && savedRegion != null && region != savedRegion)
      return [];
    final service = PlatformBenefitsService();
    try {
      return (await service.load())
          .where((b) => b.eligible && b.remaining > 0)
          .map(HomePromotion.benefit)
          .toList();
    } finally {
      service.dispose();
    }
  }

  Future<void> _load() async {
    final n = ++_request;
    try {
      // Read control state even while other home sections are hidden by filtering.
      final feed = await HomeSlideshowService().headerFeed();
      if (!mounted || n != _request) return;
      final s = feed.settings;
      if (!s.active(DateTime.now())) {
        setState(() {
          _serverSettings = s;
          _items = [];
        });
        _expiry?.cancel();
        return;
      }
      final benefits =
          SessionService.instance.isLoggedIn && s.source != 'merchant'
              ? await _loadBenefits().catchError((_) => <HomePromotion>[])
              : <HomePromotion>[];
      if (!mounted || n != _request) return;
      final ids = <String>{}, now = DateTime.now();
      setState(() {
        _serverSettings = s;
        _items =
            [...benefits, ...feed.offers.map(HomePromotion.offer)]
                .where(
                  (p) =>
                      p.endAt.isAfter(now) &&
                      s.accepts(p.source, p.slide?.targetId ?? p.benefit!.id) &&
                      ids.add(p.id),
                )
                .toList();
      });
      _armExpiry();
    } catch (_) {
      if (mounted && n == _request) setState(() => _items = []);
    }
  }

  void _armExpiry() {
    _expiry?.cancel();
    final dates =
        [
            ..._items.map((x) => x.endAt),
            if (_settings.endAt != null) _settings.endAt!,
          ].where((d) => d.isAfter(DateTime.now())).toList()
          ..sort();
    if (dates.isEmpty) return;
    _expiry = Timer(
      dates.first.difference(DateTime.now()) + const Duration(milliseconds: 10),
      () {
        if (!mounted) return;
        setState(
          () => _items.removeWhere((x) => !x.endAt.isAfter(DateTime.now())),
        );
        _armExpiry();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _load();
    }
  }

  @override
  void dispose() {
    ++_request;
    _refresh?.cancel();
    _expiry?.cancel();
    _addresses?.cancel();
    SessionService.instance.removeListener(_scopeChanged);
    BrowsingLocationService.instance.removeListener(_scopeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _items.where((p) => p.endAt.isAfter(DateTime.now())).toList();
    if (!_settings.active(DateTime.now()) ||
        HomePromotionScene.build(visible, _settings).isEmpty) {
      return widget.headerBuilder(null, null);
    }
    final hex = _settings.backgroundColor.replaceFirst('#', '');
    final color = Color(
      0xff000000 | (int.tryParse(hex, radix: 16) ?? 0x00296B),
    );
    return widget.headerBuilder(
      color,
      HomePromotionRail(
        items: visible,
        settings: _settings,
        title: _settings.title,
        background: color,
        interval: _settings.intervalSeconds,
        onTap: () => _openAll(visible),
      ),
    );
  }

  void _openAll(List<HomePromotion> items) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  title: const Text('العروض والمزايا'),
                  backgroundColor: Colors.white,
                ),
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    for (final platform in [true, false])
                      if (items.any((x) => x.platform == platform)) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            platform ? 'مزايا وعروض ويز' : 'عروض المطاعم',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xff00296b),
                            ),
                          ),
                        ),
                        for (final item in items.where(
                          (x) => x.platform == platform,
                        ))
                          Card(
                            elevation: 0,
                            color: const Color(0xfff2f5fa),
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Icon(
                                item.delivery
                                    ? Icons.delivery_dining
                                    : Icons.local_offer_outlined,
                                color: const Color(0xff00296b),
                              ),
                              title: Text(
                                item.headline,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xff00296b),
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  item.subtitle,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onOffer(item);
                              },
                            ),
                          ),
                      ],
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class HomePromotionRail extends StatefulWidget {
  final List<HomePromotion> items;
  final String title;
  final Color background;
  final int interval;
  final HomePromotionSettings? settings;
  final VoidCallback onTap;
  const HomePromotionRail({
    super.key,
    required this.items,
    required this.title,
    required this.background,
    required this.interval,
    required this.onTap,
    this.settings,
  });
  @override
  State<HomePromotionRail> createState() => _HomePromotionRailState();
}

class _HomePromotionRailState extends State<HomePromotionRail>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: _duration,
  )..addStatusListener(_status);
  int _index = 0;
  bool _reduced = false;
  Duration get _duration =>
      Duration(milliseconds: 4600 + widget.interval * 1000);
  HomePromotionSettings get _settings =>
      widget.settings ??
      HomePromotionSettings.fromJson({
        'title': widget.title,
        'intervalSeconds': widget.interval,
      });
  List<HomePromotionScene> get _scenes =>
      HomePromotionScene.build(widget.items, _settings);
  Color get _ink => promotionForeground(widget.background);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.of(context).disableAnimations;
    if (_reduced) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.forward();
    }
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _index = (_index + 1) % math.max(1, _scenes.length));
      _motion.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant HomePromotionRail old) {
    super.didUpdateWidget(old);
    _motion.duration = _duration;
    if (_index >= _scenes.length) _index = 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_reduced) {
      _motion.forward();
    } else {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  void _swipe(DragEndDetails d) {
    final n = _scenes.length;
    if (n < 2) return;
    setState(
      () => _index = (_index + (d.primaryVelocity! < 0 ? 1 : -1) + n) % n,
    );
    if (!_reduced) _motion.forward(from: 0);
  }

  double _range(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);
  Widget _image(String url, Widget fallback, {bool circle = false}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(circle ? 100 : 12),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          errorWidget: (_, __, ___) => fallback,
          placeholder: (_, __) => fallback,
        ),
      );
  Widget _brand(HomePromotionScene scene) => Container(
    width: 80,
    height: 80,
    padding: EdgeInsets.all(scene.platform ? 12 : 4),
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
    child:
        scene.platform
            ? Image.asset(
              'assets/images/wizz-wordmark-blue.png',
              fit: BoxFit.contain,
            )
            : scene.logoUrl.startsWith('https://')
            ? _image(
              scene.logoUrl,
              const Icon(Icons.storefront, color: Color(0xff00296b), size: 36),
              circle: true,
            )
            : const Icon(Icons.storefront, color: Color(0xff00296b), size: 36),
  );
  Widget _visual(HomePromotionScene scene, int index) {
    final background = promotionItemBackground(
      widget.background,
      override: widget.settings?.itemBackgroundColor,
    );
    final ink = promotionForeground(background);
    final item = scene.offers[index % scene.offers.length];
    return Container(
      key: const ValueKey('promotion-item-container'),
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child:
          scene.products.isNotEmpty
              ? _image(
                scene.products[index % scene.products.length]['imageUrl']
                    as String,
                Icon(Icons.restaurant, color: ink, size: 34),
              )
              : item.delivery
              ? Icon(Icons.delivery_dining, color: ink, size: 34)
              : Center(
                child:
                    item.slide?.offerValue != null
                        ? FittedBox(
                          child: Text(
                            '${item.slide!.offerValue}${item.slide!.offerType == 'percentage' ? '٪' : ''}',
                            style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 23,
                            ),
                          ),
                        )
                        : Icon(
                          Icons.local_offer_outlined,
                          color: ink,
                          size: 32,
                        ),
              ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scenes = _scenes;
    if (scenes.isEmpty) return const SizedBox.shrink();
    final scene = scenes[_index % scenes.length];
    return Semantics(
      button: true,
      label: '${scene.title}، استعرض العروض والمزايا',
      child: GestureDetector(
        onTap: widget.onTap,
        onHorizontalDragEnd: _swipe,
        child: ColoredBox(
          color: widget.background,
          child: SizedBox(
            height: 128 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 3,
            child: LayoutBuilder(
              builder:
                  (context, box) => AnimatedBuilder(
                    animation: _motion,
                    builder: (context, _) {
                      final t =
                          _reduced
                              ? 3200.0
                              : _motion.value * _duration.inMilliseconds;
                      final readEnd = 3000 + widget.interval * 1000.0;
                      final entering =
                          1 - Curves.easeOutCubic.transform(_range(t, 0, 1450));
                      final pulse =
                          t >= 1650 && t < 2350
                              ? 1 +
                                  .22 *
                                      math.sin(math.pi * _range(t, 1650, 2350))
                              : 1.0;
                      final opening =
                          t >= readEnd + 300 ? 0.0 : _range(t, 2350, 2750);
                      final leaving = _range(t, readEnd + 300, readEnd + 1600);
                      final objectsOpacity = (1 - opening) * (1 - leaving);
                      final surroundingOpacity =
                          t >= readEnd + 300 ? 1.0 : 1 - _range(t, 1450, 1650);
                      final copyOpacity =
                          _range(t, 2650, 3000) *
                          (1 - _range(t, readEnd, readEnd + 300));
                      return Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Opacity(
                            opacity: objectsOpacity,
                            child: Transform.translate(
                              offset: Offset(
                                box.maxWidth * 1.4 * entering -
                                    box.maxWidth * 1.4 * leaving,
                                0,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  for (final step in [-3, -2, -1, 1, 2, 3])
                                    Transform.translate(
                                      offset: Offset(step * 88.0, 0),
                                      child: Opacity(
                                        key: ValueKey('promotion-side-$step'),
                                        opacity: surroundingOpacity,
                                        child: _visual(scene, step.abs() - 1),
                                      ),
                                    ),
                                  Transform.scale(
                                    key: const ValueKey(
                                      'promotion-brand-scale',
                                    ),
                                    scale: math.min(
                                      1.25,
                                      pulse * (1 + opening * .12),
                                    ),
                                    child: _brand(scene),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Opacity(
                              key: const ValueKey('promotion-copy'),
                              opacity: copyOpacity,
                              child: Transform.scale(
                                scale: .82 + .18 * _range(t, 2650, 3000),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: SizedBox(
                                      width: box.maxWidth - 48,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            scene.title,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _ink,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (scene.subtitle.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              scene.subtitle,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: _ink.withValues(
                                                  alpha: .92,
                                                ),
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
