import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_colors.dart';
import '../services/google_places_service.dart';
import '../services/region_boundary_service.dart';
import '../services/region_resolver_service.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final LatLngBounds? initialViewport;
  final String? initialAddress, requiredRegionId;
  final bool requirePinSelection;
  final RegionResolverService? regionResolver;
  final RegionBoundaryService? boundaryService;
  final GooglePlacesService? placesService;
  final Widget Function(GoogleMap)? mapBuilder;
  const LocationPickerScreen({
    super.key,
    this.initialPosition,
    this.initialViewport,
    this.initialAddress,
    this.requiredRegionId,
    this.requirePinSelection = false,
    this.regionResolver,
    this.boundaryService,
    this.placesService,
    this.mapBuilder,
  });
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _map;
  final _mapGestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };
  late final GooglePlacesService _places;
  late final RegionResolverService _resolver;
  final _search = TextEditingController();
  Timer? _searchTimer, _checkTimer;
  late LatLng _position;
  Future<String?>? _addressLookup;
  LatLng? _addressLookupPoint;
  RegionResolveResult? _resolved;
  List<PlacePrediction> _predictions = [];
  String? _pointError;
  bool _moving = false,
      _checking = false,
      _confirming = false,
      _searching = false;
  bool _hasSelected = false, _locationGranted = false;
  int _pointGeneration = 0, _searchGeneration = 0;
  MapType _mapType = MapType.normal;
  bool get _valid =>
      _hasSelected &&
      !_moving &&
      !_checking &&
      !_confirming &&
      _resolved?.effective.isDeliveryAvailable == true &&
      (widget.requiredRegionId == null ||
          _resolved!.region.id == widget.requiredRegionId);

  @override
  void initState() {
    super.initState();
    final viewport = widget.initialViewport;
    _position =
        widget.initialPosition ??
        (viewport == null
            ? const LatLng(33.3128, 44.3615)
            : LatLng(
              (viewport.southwest.latitude + viewport.northeast.latitude) / 2,
              (viewport.southwest.longitude + viewport.northeast.longitude) / 2,
            ));
    _places = widget.placesService ?? GooglePlacesService();
    _resolver = widget.regionResolver ?? RegionResolverService();
    if (widget.initialPosition == null && widget.initialViewport == null) {
      _useCurrentLocation();
    } else if (widget.initialPosition != null && !widget.requirePinSelection) {
      _hasSelected = true;
      _scheduleCheck();
    }
  }

  @override
  void dispose() {
    _pointGeneration++;
    _searchGeneration++;
    _searchTimer?.cancel();
    _checkTimer?.cancel();
    _search.dispose();
    if (widget.placesService == null) _places.dispose();
    // GoogleMap owns and disposes its native controller.
    _map = null;
    super.dispose();
  }

  void _invalidatePoint() {
    _pointGeneration++;
    _checkTimer?.cancel();
    _resolved = null;
    _addressLookup = null;
    _addressLookupPoint = null;
    _pointError = null;
    _checking = false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_confirming) return;
    setState(() {
      _hasSelected = true;
      _moving = true;
      _invalidatePoint();
    });
  }

  void _cameraStarted() {
    if (!mounted) return;
    setState(() {
      _moving = true;
      _invalidatePoint();
    });
  }

  void _cameraMoved(CameraPosition camera) {
    _position = camera.target;
  }

  void _cameraIdle() {
    if (!mounted) return;
    setState(() => _moving = false);
    if (_hasSelected) _scheduleCheck();
  }

  Future<void> _pick(LatLng point) async {
    if (!mounted || _confirming) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _invalidatePoint();
      _hasSelected = true;
      _position = point;
      _moving = false;
    });
    if (_map != null) await _map!.animateCamera(CameraUpdate.newLatLng(point));
    if (mounted) _scheduleCheck();
  }

  void _scheduleCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer(const Duration(milliseconds: 250), _checkPoint);
  }

  Future<void> _checkPoint() async {
    if (!mounted || !_hasSelected || _moving) return;
    final point = _position, generation = ++_pointGeneration;
    setState(() {
      _checking = true;
      _resolved = null;
      _pointError = null;
    });
    try {
      final result = await _resolver.resolvePoint(
        lat: point.latitude,
        lng: point.longitude,
        throwOnFailure: true,
      );
      if (!mounted || generation != _pointGeneration || point != _position) {
        return;
      }
      setState(() {
        _checking = false;
        if (result == null || !result.effective.isDeliveryAvailable) {
          _pointError = 'الخدمة غير متاحة عند هذه النقطة.';
        } else if (widget.requiredRegionId != null &&
            result.region.id != widget.requiredRegionId) {
          _pointError =
              'النقطة خارج ${widget.initialAddress ?? 'المنطقة المختارة'}. حرّك الخريطة إلى داخل الحدود.';
        } else {
          _resolved = result;
        }
      });
      if (_resolved != null) _prefetchAddress(point);
    } catch (_) {
      if (mounted && generation == _pointGeneration) {
        setState(() {
          _checking = false;
          _pointError = 'تعذر التحقق من النقطة. أعد المحاولة.';
        });
      }
    }
  }

  void _prefetchAddress(LatLng point) {
    _addressLookupPoint = point;
    _addressLookup = () async {
      try {
        return await _places
            .getAddressFromCoordinates(
              latitude: point.latitude,
              longitude: point.longitude,
              language: 'ar',
            )
            .timeout(const Duration(milliseconds: 1500));
      } catch (_) {
        return null;
      }
    }();
  }

  Future<void> _useCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception();
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      if (!position.accuracy.isFinite || position.accuracy > 100)
        throw Exception('Location accuracy insufficient');
      if (!mounted) return;
      setState(() => _locationGranted = true);
      await _pick(LatLng(position.latitude, position.longitude));
      await _map?.animateCamera(CameraUpdate.zoomTo(17));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _pointError =
                  'تعذر تحديد موقع جهازك. يمكنك تحريك الخريطة واختيار النقطة يدويًا.',
        );
      }
    }
  }

  Future<void> _zoom(double delta) async {
    final map = _map;
    if (map == null || _confirming) return;
    final zoom = await map.getZoomLevel();
    if (!mounted) return;
    setState(() => _hasSelected = true);
    await map.animateCamera(
      CameraUpdate.zoomTo((zoom + delta).clamp(3, 21).toDouble()),
    );
  }

  void _searchChanged(String text) {
    final generation = ++_searchGeneration;
    _searchTimer?.cancel();
    if (text.trim().length < 3) {
      setState(() {
        _predictions = [];
        _searching = false;
      });
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final predictions = await _places.searchPlaces(
          query: text.trim(),
          language: 'ar',
          countries: ['iq'],
        );
        if (mounted && generation == _searchGeneration) {
          setState(() {
            _predictions = predictions;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted && generation == _searchGeneration) {
          setState(() {
            _searching = false;
            _pointError = 'تعذر البحث الآن. يمكنك الاختيار من الخريطة.';
          });
        }
      }
    });
  }

  Future<void> _selectPlace(PlacePrediction prediction) async {
    final generation = ++_searchGeneration;
    _searchTimer?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _predictions = [];
      _searching = true;
    });
    try {
      final details = await _places.getPlaceDetails(
        placeId: prediction.placeId,
        language: 'ar',
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searching = false;
        _search.text = prediction.description;
      });
      await _pick(LatLng(details.latitude, details.longitude));
      await _map?.animateCamera(CameraUpdate.zoomTo(17));
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _searching = false;
          _pointError = 'تعذر فتح العنوان. حاول مجددًا.';
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (!_valid) return;
    final point = _position, generation = _pointGeneration;
    setState(() => _confirming = true);
    try {
      // Recheck current source at confirmation; a displayed outline is not authorization.
      final region = await _resolver.resolvePoint(
        lat: point.latitude,
        lng: point.longitude,
        throwOnFailure: true,
      );
      if (!mounted || generation != _pointGeneration) return;
      if (region == null ||
          !region.effective.isDeliveryAvailable ||
          (widget.requiredRegionId != null &&
              region.region.id != widget.requiredRegionId)) {
        setState(() {
          _resolved = null;
          _pointError =
              'هذه النقطة غير متاحة في المنطقة المختارة. اختر نقطة أخرى.';
        });
        return;
      }
      var address =
          '${region.region.nameAr}، ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
      final lookup = _addressLookupPoint == point ? _addressLookup : null;
      if (lookup != null) {
        final label = await lookup.timeout(
          const Duration(milliseconds: 800),
          onTimeout: () => null,
        );
        if (label != null && label.trim().isNotEmpty) address = label;
      }
      if (mounted && generation == _pointGeneration) {
        Navigator.pop(context, {
          'position': point,
          'address': address,
          'region': region,
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pointError = 'تعذر تأكيد النقطة الآن. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Widget _mapButton(IconData icon, String label, VoidCallback action) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(14),
          child: IconButton(
            tooltip: label,
            onPressed: _confirming ? null : action,
            icon: Icon(icon, color: AppColors.secondaryDark),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final googleMap = GoogleMap(
      key: const ValueKey('delivery-location-map'),
      initialCameraPosition: CameraPosition(
        target: widget.initialPosition ?? _position,
        zoom:
            widget.initialPosition == null && widget.initialViewport != null
                ? 12
                : 17,
      ),
      mapType: _mapType,
      polygons: const {},
      markers: const {},
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      zoomControlsEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      liteModeEnabled: false,
      myLocationEnabled: _locationGranted,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      gestureRecognizers: _mapGestures,
      onMapCreated: (controller) async {
        _map = controller;
        if (widget.initialPosition == null && widget.initialViewport != null) {
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || _map == null || _hasSelected) return;
          await _map!.animateCamera(
            CameraUpdate.newLatLngBounds(widget.initialViewport!, 36),
          );
        }
      },
      onCameraMoveStarted: _cameraStarted,
      onCameraMove: _cameraMoved,
      onCameraIdle: _cameraIdle,
      onTap: _pick,
    );
    final status =
        _moving
            ? 'حرّك الخريطة حتى يصبح الدبوس فوق عنوانك'
            : _checking
            ? 'جارٍ التحقق من نقطة التوصيل…'
            : _pointError ??
                (_valid
                    ? 'نقطة التوصيل متاحة'
                    : 'حرّك الخريطة لتحديد نقطة التوصيل ثم أكد الموقع');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialAddress ?? 'اختيار موقع التوصيل'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.secondaryDark,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AbsorbPointer(
                  absorbing: _confirming,
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    child: widget.mapBuilder?.call(googleMap) ?? googleMap,
                  ),
                ),
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(
                        Icons.location_pin,
                        size: 48,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Material(
                    color: Colors.white,
                    elevation: 3,
                    borderRadius: BorderRadius.circular(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _search,
                          onChanged: _searchChanged,
                          decoration: InputDecoration(
                            hintText: 'ابحث عن شارع أو معلم قريب',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon:
                                _searching
                                    ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                    : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(14),
                          ),
                        ),
                        if (_predictions.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ListView(
                              shrinkWrap: true,
                              children:
                                  _predictions
                                      .map(
                                        (p) => ListTile(
                                          title: Text(p.mainText),
                                          subtitle: Text(p.secondaryText),
                                          onTap: () => _selectPlace(p),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  left: 12,
                  bottom: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _mapButton(Icons.add, 'تكبير الخريطة', () => _zoom(1)),
                      _mapButton(
                        Icons.remove,
                        'تصغير الخريطة',
                        () => _zoom(-1),
                      ),
                      _mapButton(
                        Icons.my_location,
                        'موقعي الحالي',
                        _useCurrentLocation,
                      ),
                      _mapButton(
                        Icons.layers_outlined,
                        'تغيير نوع الخريطة',
                        () => setState(
                          () =>
                              _mapType =
                                  _mapType == MapType.normal
                                      ? MapType.hybrid
                                      : MapType.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        _valid
                            ? Icons.check_circle_outline
                            : Icons.location_on_outlined,
                        color:
                            _pointError != null
                                ? Colors.red.shade700
                                : AppColors.secondaryDark,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                _pointError != null
                                    ? Colors.red.shade700
                                    : AppColors.secondaryDark,
                          ),
                        ),
                      ),
                      if (_checking)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  if (_pointError != null && !_moving)
                    TextButton(
                      onPressed: _hasSelected ? _checkPoint : null,
                      child: const Text('إعادة التحقق'),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      key: const ValueKey('confirm-delivery-point'),
                      onPressed: _valid ? _confirm : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.secondaryDark,
                        disabledBackgroundColor: const Color(0xFFE7EAF0),
                        disabledForegroundColor: const Color(0xFF5B6578),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _confirming
                            ? 'جارٍ تأكيد النقطة…'
                            : 'تأكيد نقطة التوصيل',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
