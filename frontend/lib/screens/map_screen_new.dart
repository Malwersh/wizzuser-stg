import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/business_model.dart';
import '../models/home_layout.dart';
import '../models/home_filters.dart';
import '../models/home_navigation.dart';
import '../services/home_slideshow_service.dart';
import '../models/store.dart';
import '../services/browsing_location_service.dart';
import '../services/storefront_pricing.dart';
import 'store_detail_screen.dart';

const _navy = Color(0xFF00296B);

bool explorationAvailable(BusinessModel b, {DateTime? now}) =>
    matchesHomeFilter(
      HomeFilter.fromJson({
        'id': 'open',
        'label': 'مفتوح الآن',
        'kind': 'openNow',
        'enabled': true,
      }),
      b,
      facts: const {},
      settings: HomeFilters.defaults(),
      now: now ?? DateTime.now(),
    );

bool explorationHasPoint(BusinessModel b) =>
    b.latitude != null &&
    b.longitude != null &&
    b.latitude!.isFinite &&
    b.longitude!.isFinite &&
    b.latitude!.abs() <= 90 &&
    b.longitude!.abs() <= 180;

List<BusinessModel> explorationFilter(
  List<BusinessModel> catalog, {
  String query = '',
  bool openOnly = false,
  bool ratedOnly = false,
}) {
  final q = query.trim().toLowerCase();
  return catalog
      .where(
        (b) =>
            (!openOnly || explorationAvailable(b)) &&
            (!ratedOnly ||
                ((b.reviewCount ?? 0) > 0 &&
                    b.rating.isFinite &&
                    b.rating >= 4 &&
                    b.rating <= 5)) &&
            (q.isEmpty ||
                '${b.businessName} ${b.businessType}'.toLowerCase().contains(
                  q,
                )),
      )
      .toList(growable: false);
}

/// Explore shares the home's region catalog and destination-scoped price cache.
/// It never requests another GPS fix or starts a product/status polling loop.
class MapScreenNew extends StatefulWidget {
  final List<BusinessModel>? businesses;
  final HomeLayout? layout;
  final Future<void> Function()? refreshAvailability;
  const MapScreenNew({
    super.key,
    this.businesses,
    this.layout,
    this.refreshAvailability,
  });
  @override
  State<MapScreenNew> createState() => _MapScreenNewState();
}

class _MapScreenNewState extends State<MapScreenNew> {
  final _search = TextEditingController();
  final _sheet = DraggableScrollableController();
  final _pricing = StorefrontPricing.instance;
  final _location = BrowsingLocationService.instance;
  final _requested = <String>{};
  GoogleMapController? _map;
  final _markerIcons = <String, BitmapDescriptor>{};
  final _markerJobs = <String>{};
  String _markerKey(BusinessModel b) =>
      '${b.businessType}|${b.businessPhotoUrl}';

  void _loadMarkers() {
    for (final b in widget.businesses ?? <BusinessModel>[]) {
      final key = _markerKey(b);
      if (_markerIcons.containsKey(key) || !_markerJobs.add(key)) continue;
      unawaited(
        _createMarker(b)
            .then((icon) {
              if (mounted) setState(() => _markerIcons[key] = icon);
            })
            .whenComplete(() => _markerJobs.remove(key)),
      );
    }
  }

  Future<BitmapDescriptor> _createMarker(BusinessModel b) async {
    ImageInfo? logo;
    if (b.businessPhotoUrl.trim().isNotEmpty) {
      final stream = CachedNetworkImageProvider(
        b.businessPhotoUrl,
      ).resolve(const ImageConfiguration());
      final loaded = Completer<ImageInfo>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!loaded.isCompleted) loaded.complete(info.clone());
        },
        onError: (Object error, StackTrace? trace) {
          if (!loaded.isCompleted) loaded.completeError(error, trace);
        },
      );
      stream.addListener(listener);
      try {
        logo = await loaded.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        /* A missing logo uses the appropriate store icon. */
      } finally {
        stream.removeListener(listener);
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(64, 64);
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: 58)),
      Colors.black,
      5,
      false,
    );
    canvas.drawCircle(center, 60, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: 53)),
    );
    canvas.drawCircle(center, 53, Paint()..color = const Color(0xFFEFF3F9));
    if (logo != null) {
      paintImage(
        canvas: canvas,
        rect: const Rect.fromLTWH(11, 11, 106, 106),
        image: logo.image,
        fit: BoxFit.cover,
      );
    } else {
      final type = b.businessType.toLowerCase();
      final icon =
          type.contains('restaurant') || type.contains('مطعم')
              ? Icons.restaurant
              : type.contains('cafe') || type.contains('مقه')
              ? Icons.local_cafe
              : Icons.storefront;
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 62,
            color: _navy,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(64 - painter.width / 2, 64 - painter.height / 2),
      );
      painter.dispose();
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(128, 128);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    logo?.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: 52,
      height: 52,
    );
  }

  String? _selected;
  final _filtersSelected = <String>{};
  String? _activityId, _topicId, _priceTier;
  bool _nearest = false, _preparing = false;
  int _filterGeneration = 0;
  String? _filterError;
  final _menuPrices = <String, dynamic>{};
  HomeFilters get _filters => widget.layout?.filters ?? HomeFilters.defaults();
  HomeNavigation? get _navigation => widget.layout?.navigation;
  Map<String, dynamic> get _facts => widget.layout?.discovery ?? const {};
  List<HomeFilter> get _filterItems =>
      _filters.enabled
          ? _filters.items.where((f) => f.enabled && f.kind != 'all').toList()
          : [];
  HomeNavigationItem? _item(String? id) {
    if (_navigation?.enabled != true) return null;
    for (final item in _navigation?.items ?? <HomeNavigationItem>[]) {
      if (item.id == id &&
          (item.kind == 'activity'
              ? _navigation!.activitiesEnabled
              : _navigation!.topicsEnabled))
        return item;
    }
    return null;
  }

  List<BusinessModel> get _results {
    final rows =
        explorationFilter(
          widget.businesses ?? const [],
          query: _search.text,
        ).where((b) {
          if (_item(_activityId)?.matches(b, _facts) == false ||
              _item(_topicId)?.matches(b, _facts) == false)
            return false;
          return _filterItems
              .where((f) => _filtersSelected.contains(f.id))
              .every(
                (f) => matchesHomeFilter(
                  f,
                  b,
                  facts: _facts,
                  route: _pricing.peekRoute(b.id)?.data,
                  fee: _pricing.feeIqd(b.id, const []),
                  price:
                      (_menuPrices[b.id] ?? widget.layout?.menuPrices[b.id])
                          as Map<String, dynamic>?,
                  priceTier: _priceTier,
                  settings: _filters,
                  now: DateTime.now(),
                ),
              );
        }).toList();
    if (_nearest &&
        _point != null &&
        _filterItems.any(
          (f) => f.kind == 'sort' && _filtersSelected.contains(f.id),
        )) {
      double distance(BusinessModel b) =>
          b.calculateDistanceFrom(_point!.latitude, _point!.longitude) ??
          double.infinity;
      rows.sort((a, b) {
        final c = distance(a).compareTo(distance(b));
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    }
    return rows;
  }

  Future<void> _chooseFilter(HomeFilter filter) async {
    if (_preparing) return;
    if (_filtersSelected.contains(filter.id)) {
      setState(() {
        _filtersSelected.remove(filter.id);
        _selected = null;
        if (filter.kind == 'sort') _nearest = false;
      });
      return;
    }
    if (filter.kind == 'menuPrice' || filter.kind == 'sort') {
      final options =
          filter.kind == 'sort'
              ? {'nearest': 'الأقرب إلى نقطة التوصيل'}
              : {
                'economy': 'اقتصادي',
                'medium': 'متوسط',
                'premium': 'أعلى سعرًا',
              };
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder:
            (c) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options.entries)
                    ListTile(
                      title: Text(option.value, textAlign: TextAlign.right),
                      onTap: () => Navigator.pop(c, option.key),
                    ),
                ],
              ),
            ),
      );
      if (!mounted || choice == null) return;
      if (filter.kind == 'sort')
        _nearest = true;
      else
        _priceTier = choice;
    }
    if (filter.kind == 'sort' && _point == null) {
      setState(() => _filterError = 'حدد نقطة التوصيل أولًا لترتيب الأقرب.');
      _nearest = false;
      return;
    }
    final generation = ++_filterGeneration;
    setState(() {
      _preparing = true;
      _filterError = null;
      _selected = null;
    });
    try {
      if (filter.kind == 'openNow') await widget.refreshAvailability?.call();
      final catalog = widget.businesses ?? const <BusinessModel>[];
      if ([
        'fastDelivery',
        'preparation',
        'freeDelivery',
        'deliveryFee',
      ].contains(filter.kind)) {
        for (var i = 0; i < catalog.length; i += 3) {
          if (!mounted || generation != _filterGeneration) return;
          await Future.wait(
            catalog.skip(i).take(3).map((b) {
              _pricing.seedBusiness(b.id, b.metadata ?? {}, onlyIfAbsent: true);
              return _pricing.load(b.id, const []);
            }),
          );
        }
      }
      if (filter.kind == 'menuPrice') {
        for (var i = 0; i < catalog.length; i += 12) {
          final feed = await HomeSlideshowService().load(
            priceBusinessIds:
                catalog.skip(i).take(12).map((b) => b.id).toList(),
          );
          if (!mounted || generation != _filterGeneration) return;
          _menuPrices.addAll(feed.layout?.menuPrices ?? {});
        }
      }
      if (mounted && generation == _filterGeneration)
        setState(() => _filtersSelected.add(filter.id));
    } catch (_) {
      if (mounted && generation == _filterGeneration)
        setState(() {
          _filterError = 'تعذر تحديث الفلتر. أعد المحاولة.';
          if (filter.kind == 'sort') _nearest = false;
        });
    } finally {
      if (mounted && generation == _filterGeneration)
        setState(() => _preparing = false);
      _schedulePrices();
    }
  }

  Future<void> _showFilters() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder:
        (sheetContext) => StatefulBuilder(
          builder: (sheetContext, update) {
            void refresh() {
              if (sheetContext.mounted) update(() {});
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * .65,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'تصفية الأماكن',
                          style: TextStyle(
                            color: _navy,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final filter in _filterItems)
                              _chip(
                                filter.label,
                                _filtersSelected.contains(filter.id),
                                () async {
                                  final task = _chooseFilter(filter);
                                  refresh();
                                  await task;
                                  refresh();
                                },
                              ),
                          ],
                        ),
                        if (_preparing)
                          const LinearProgressIndicator(
                            minHeight: 2,
                            color: _navy,
                          ),
                        if (_filterError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _filterError!,
                              style: const TextStyle(color: _navy),
                            ),
                          ),
                        if (_navigation?.enabled == true &&
                            _navigation!.activitiesEnabled) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'نوع المكان',
                            style: TextStyle(
                              color: _navy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _navigationStrip(
                            _navigation!.activities
                                .where((i) => i.kind != 'all')
                                .toList(),
                            _activityId,
                            activity: true,
                            onChanged: refresh,
                          ),
                        ],
                        if (_navigation?.enabled == true &&
                            _navigation!.topicsEnabled &&
                            _navigation!
                                .topicsFor(_item(_activityId)?.value)
                                .isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'ماذا تبحث عنه؟',
                            style: TextStyle(
                              color: _navy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _navigationStrip(
                            _navigation!.topicsFor(_item(_activityId)?.value),
                            _topicId,
                            onChanged: refresh,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed:
                              _preparing
                                  ? null
                                  : () => Navigator.pop(sheetContext),
                          style: FilledButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('عرض النتائج'),
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

  Widget _navigationStrip(
    List<HomeNavigationItem> items,
    String? selected, {
    bool activity = false,
    VoidCallback? onChanged,
  }) => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final item = items[i];
        return _chip(item.label, selected == item.id, () {
          setState(() {
            _selected = null;
            if (activity) {
              _activityId = _activityId == item.id ? null : item.id;
              _topicId = null;
            } else {
              _topicId = _topicId == item.id ? null : item.id;
            }
          });
          _schedulePrices();
          onChanged?.call();
        });
      },
    ),
  );
  LatLng? get _point {
    final p = _location.selection;
    if (p?.hasPoint != true) return null;
    return LatLng(p!.latitude!, p.longitude!);
  }

  @override
  void initState() {
    super.initState();
    _pricing.addListener(_priceChanged);
    _location.addListener(_destinationChanged);
    _loadMarkers();
    _schedulePrices();
  }

  @override
  void didUpdateWidget(covariant MapScreenNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) _menuPrices.clear();
    _loadMarkers();
    if (!(widget.businesses ?? const []).any((b) => b.id == _selected)) {
      _selected = null;
    }
    _schedulePrices();
  }

  void _priceChanged() {
    if (mounted) setState(() {});
  }

  void _destinationChanged() {
    ++_filterGeneration;
    _preparing = false;
    _filterError = null;
    _filtersSelected.clear();
    _menuPrices.clear();
    _nearest = false;
    _requested.clear();
    _selected = null;
    if (mounted) setState(() {});
    _schedulePrices();
    final p = _point;
    if (p != null) _map?.animateCamera(CameraUpdate.newLatLngZoom(p, 14));
  }

  void _schedulePrices() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final b in _results.take(4)) {
        _loadPrice(b);
      }
    });
  }

  void _loadPrice(BusinessModel b) {
    _pricing.seedBusiness(b.id, b.metadata ?? {}, onlyIfAbsent: true);
    final key = _pricing.key(b.id, const []);
    if (key == null || !_requested.add(key)) return;
    unawaited(_pricing.load(b.id, const []));
  }

  void _select(BusinessModel b) {
    setState(() => _selected = b.id);
    _loadPrice(b);
    if (explorationHasPoint(b)) {
      _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(b.latitude!, b.longitude!), 15),
      );
    }
    if (_sheet.isAttached) {
      unawaited(
        _sheet.animateTo(
          .55,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _open(BusinessModel b) {
    final p = _pricing.peekDisplay(b.id, const []);
    final store = Store(
      id: b.id,
      name: b.businessName,
      image: b.businessPhotoUrl,
      logoUrl: b.businessPhotoUrl,
      isOpen: explorationAvailable(b),
      rating: b.ratingString,
      reviews: b.reviewCount?.toString() ?? '',
      address: b.address,
      fee: p?.feeText ?? '',
      distance: p?.distanceText ?? '',
      time: p?.arrivalText ?? '',
      averagePreparationMinutes: b.averagePreparationMinutes,
      businessType: b.businessType,
      isOnline: b.isOnline,
      acceptingOrders: b.acceptingOrders,
      isBusy: b.isBusy,
      businessMode: b.businessMode,
      currentOrdersCount: b.currentOrdersCount,
      maxOrdersCapacity: b.maxOrdersCapacity,
      combos: [],
      sandwiches: [],
      drinks: [],
      extras: [],
      specialties: [],
    );
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)));
  }

  @override
  void dispose() {
    ++_filterGeneration;
    _pricing.removeListener(_priceChanged);
    _location.removeListener(_destinationChanged);
    _search.dispose();
    _sheet.dispose();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final shown =
        _selected == null
            ? results
            : results.where((b) => b.id == _selected).toList();
    final point = _point;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child:
                point == null
                    ? const ColoredBox(
                      color: Color(0xFFF1F4F9),
                      child: Center(
                        child: Text(
                          'اختر نقطة التوصيل من عنوان الرئيسية',
                          style: TextStyle(color: _navy),
                        ),
                      ),
                    )
                    : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: point,
                        zoom: 14,
                      ),
                      onMapCreated: (controller) => _map = controller,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      padding: EdgeInsets.only(top: 100, bottom: 230),
                      markers: {
                        Marker(
                          markerId: const MarkerId('delivery-point'),
                          position: point,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueAzure,
                          ),
                          infoWindow: const InfoWindow(title: 'نقطة التوصيل'),
                        ),
                        for (final b in results.where(explorationHasPoint))
                          Marker(
                            markerId: MarkerId(b.id),
                            position: LatLng(b.latitude!, b.longitude!),
                            alpha: explorationAvailable(b) ? 1 : .55,
                            anchor: const Offset(.5, .5),
                            zIndexInt: b.id == _selected ? 2 : 1,
                            icon:
                                _markerIcons[_markerKey(b)] ??
                                BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueBlue,
                                ),
                            infoWindow: InfoWindow(title: b.businessName),
                            onTap: () => _select(b),
                          ),
                      },
                    ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1800296B),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFE8ECF3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: const Color(0xFFF4F6FA),
                            elevation: 0,
                            shadowColor: Colors.black12,
                            borderRadius: BorderRadius.circular(22),
                            child: TextField(
                              controller: _search,
                              onChanged: (_) {
                                setState(() => _selected = null);
                                _schedulePrices();
                              },
                              style: const TextStyle(color: _navy),
                              decoration: InputDecoration(
                                hintText: 'ابحث عن مطعم أو متجر',
                                hintStyle: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF8190A5),
                                ),
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: _navy,
                                ),
                                suffixIcon:
                                    _search.text.isEmpty
                                        ? null
                                        : IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            _search.clear();
                                            setState(() => _selected = null);
                                            _schedulePrices();
                                          },
                                        ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Badge(
                          isLabelVisible:
                              _filtersSelected.isNotEmpty ||
                              _activityId != null ||
                              _topicId != null,
                          label: Text(
                            '${_filtersSelected.length + (_activityId == null ? 0 : 1) + (_topicId == null ? 0 : 1)}',
                          ),
                          backgroundColor: _navy,
                          child: IconButton(
                            tooltip: 'الفلاتر',
                            onPressed: _showFilters,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFEAF0F8),
                              padding: const EdgeInsets.all(14),
                            ),
                            icon: const Icon(Icons.tune_rounded, color: _navy),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: 16,
            top: MediaQuery.paddingOf(context).top + 104,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: 'نقطة التوصيل',
                icon: const Icon(Icons.my_location, color: _navy),
                onPressed:
                    point == null
                        ? null
                        : () => _map?.animateCamera(
                          CameraUpdate.newLatLngZoom(point, 14),
                        ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: .35,
            minChildSize: .22,
            maxChildSize: .85,
            builder:
                (context, controller) => Material(
                  color: Colors.white,
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'استكشف حولك · ${results.length}',
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_selected != null)
                            IconButton(
                              tooltip: 'إغلاق تحديد المطعم',
                              onPressed: () => setState(() => _selected = null),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: _navy,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                      if (shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'لا توجد نتائج مطابقة. جرّب تغيير البحث أو الفلاتر.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      for (final b in shown) _card(b),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, bool selected, VoidCallback action) => FilterChip(
    label: Text(text, style: TextStyle(color: selected ? Colors.white : _navy)),
    selected: selected,
    onSelected: (_) => action(),
    selectedColor: _navy,
    backgroundColor: const Color(0xFFF5F6F9),
    checkmarkColor: Colors.white,
    side: BorderSide(color: selected ? _navy : const Color(0xFFE7EBF2)),
    shape: const StadiumBorder(),
    showCheckmark: false,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    visualDensity: VisualDensity.compact,
  );

  Widget _card(BusinessModel b) {
    final p = _pricing.peekDisplay(b.id, const []);
    // Loading is on demand, never periodic. A valid display is kept during revalidation.
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(b),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE4E9F1)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  b.businessPhotoUrl,
                  width: 86,
                  height: 86,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => const SizedBox(
                        width: 86,
                        height: 86,
                        child: ColoredBox(
                          color: Color(0xFFF1F4F9),
                          child: Icon(Icons.storefront, color: _navy),
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            b.businessName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!explorationAvailable(b))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC62828),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Text(
                              'غير متاح',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '★ ${b.ratingString}${p == null ? '' : '  ·  ${p.arrivalText}'}',
                      style: const TextStyle(color: _navy, fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    if (p != null)
                      Text(
                        '${p.feeText}  ·  ${p.distanceText}',
                        style: const TextStyle(color: _navy, fontSize: 13),
                      )
                    else
                      TextButton(
                        onPressed: () {
                          _requested.remove(_pricing.key(b.id, const []));
                          _loadPrice(b);
                        },
                        child: const Text(
                          'عرض رسوم التوصيل',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
