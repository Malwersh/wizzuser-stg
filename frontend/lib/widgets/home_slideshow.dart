import '../models/home_layout.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/home_slide.dart';
import '../models/delivery_address.dart';
import '../services/home_slideshow_service.dart';
import '../services/delivery_address_manager.dart';
import '../services/browsing_location_service.dart';
import '../services/session_service.dart';

class HomeSlideshow extends StatefulWidget {
  final ValueChanged<HomeSlide> onTap;
  final ValueChanged<HomeLayout?>? onLayout;
  const HomeSlideshow({super.key, required this.onTap, this.onLayout});
  @override
  State<HomeSlideshow> createState() => _HomeSlideshowState();
}

class _HomeSlideshowState extends State<HomeSlideshow>
    with WidgetsBindingObserver {
  static const _initialPage = 10000;
  final _controller = PageController(
    initialPage: _initialPage,
    viewportFraction: 0.90,
  );
  final _service = HomeSlideshowService();
  final _session = SessionService();
  StreamSubscription<DeliveryAddress?>? _addresses;
  Timer? _rotation, _refresh;
  List<HomeSlide> _slides = [];
  HomeLayout? _layout;
  int _page = _initialPage, _request = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_contextChanged);
    BrowsingLocationService.instance.addListener(_contextChanged);
    _addresses = DeliveryAddressManager.instance.addressStream.listen(
      (_) => _contextChanged(),
    );
    _load();
    _rotation = Timer.periodic(const Duration(seconds: 3), (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          !_controller.hasClients)
        return;
      _recordView();
      final count = _slides.length;
      if (count > 1)
        _controller.animateToPage(
          _page + 1,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOut,
        );
    });
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        _load();
    });
  }

  void _recordView() {
    if (!mounted ||
        _slides.isEmpty ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true)
      return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy,
        screen = MediaQuery.sizeOf(context).height;
    if (top < screen && top + box.size.height > 0)
      _service.track(_slides[_page % _slides.length].id, 'view');
  }

  void _contextChanged() {
    // Remove content for the previous account/address while eligibility reloads.
    if (mounted) setState(() => _slides = []);
    _layout = null;
    widget.onLayout?.call(null);
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final feed = await _service.load();
      if (!mounted || request != _request) return;
      _layout = feed.layout;
      widget.onLayout?.call(_layout);
      setState(() {
        _slides =
            feed.slides.where((s) => s.endAt.isAfter(DateTime.now())).toList();
        // Start on the first slide with preceding pages available for a preview.
        _page =
            _slides.length > 1
                ? _initialPage - (_initialPage % _slides.length)
                : 0;
      });
      final firstPage = _page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || request != _request) return;
        if (_controller.hasClients) _controller.jumpToPage(firstPage);
        _recordView();
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      widget.onLayout?.call(_layout);
      setState(
        () =>
            _slides =
                _slides.where((s) => s.endAt.isAfter(DateTime.now())).toList(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_contextChanged);
    BrowsingLocationService.instance.removeListener(_contextChanged);
    _addresses?.cancel();
    _rotation?.cancel();
    _refresh?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) return const SizedBox.shrink();
    final count = _slides.length;
    return SizedBox(
      height: 180,
      child: PageView.builder(
        controller: _controller,
        itemCount: count > 1 ? null : 1,
        onPageChanged: (i) {
          _page = i;
          _recordView();
        },
        itemBuilder: (context, index) {
          final slide = _slides[index % count];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              label: slide.title,
              button: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Material(
                  child: InkWell(
                    onTap: () {
                      _service.track(slide.id, 'tap');
                      widget.onTap(slide);
                    },
                    child: CachedNetworkImage(
                      imageUrl: slide.imageUrl,
                      cacheKey: 'home-slide-${slide.id}-${slide.imageVersion}',
                      fit: BoxFit.cover,
                      placeholder:
                          (_, _) => const ColoredBox(color: Color(0xffedf1f5)),
                      errorWidget:
                          (_, _, _) => Center(child: Text(slide.title)),
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
}
