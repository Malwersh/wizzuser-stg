import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/business_service.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/order_model.dart';
import '../models/live_driver_point.dart';
import '../services/websocket_service.dart';

class LiveOrderMap extends StatefulWidget {
  final OrderModel order;
  final Stream<LiveDriverPoint>? locationStream;
  final Widget Function(Set<Marker>, Set<Polyline>)? mapBuilder;
  const LiveOrderMap({
    super.key,
    required this.order,
    this.locationStream,
    this.mapBuilder,
  });
  @override
  State<LiveOrderMap> createState() => _LiveOrderMapState();
}

class _LiveOrderMapState extends State<LiveOrderMap>
    with SingleTickerProviderStateMixin {
  StreamSubscription<LiveDriverPoint>? _stream;
  GoogleMapController? _map;
  late final AnimationController _motion;
  LatLng? _from, _to;
  LiveDriverPoint? _point;
  Timer? _clock;
  BitmapDescriptor? _driverIcon, _homeIcon, _storeIcon;
  int _iconGeneration = 0;
  double _bearing = 0;
  List<LatLng> _road = [];
  bool _following = true;
  static const navy = Color(0xFF00296B);
  bool get _sharing => {
    'picked_up',
    'heading_to_customer',
    'arrived_at_customer',
    'on_the_way',
  }.contains(widget.order.status.value);
  LatLng? get _destination {
    final a = widget.order.deliveryAddress;
    return a.latitude != null &&
            a.longitude != null &&
            a.latitude!.abs() <= 90 &&
            a.longitude!.abs() <= 180
        ? LatLng(a.latitude!, a.longitude!)
        : null;
  }

  LatLng? get _position {
    if (_to == null) return null;
    final t = _motion.value;
    return LatLng(
      (_from ?? _to)!.latitude + (_to!.latitude - (_from ?? _to)!.latitude) * t,
      (_from ?? _to)!.longitude +
          (_to!.longitude - (_from ?? _to)!.longitude) * t,
    );
  }

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addListener(() {
      if (mounted) setState(() {});
    });
    _stream = (widget.locationStream ?? WebSocketService().driverLocations)
        .listen(_receive);
    if (widget.mapBuilder == null) {
      unawaited(_makeDriverIcon());
      unawaited(_makePlaceIcons());
    }
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _makeDriverIcon() async {
    final kind = widget.order.vehicleType?.toLowerCase();
    final path = switch (kind) {
      'car' || 'سيارة' => 'assets/images/tracking-car-3d-443.png',
      'motorcycle' ||
      'motorbike' ||
      'bike' ||
      'scooter' ||
      'دراجة نارية' => 'assets/images/tracking-scooter-3d-443.png',
      _ => null,
    };
    final generation = ++_iconGeneration;
    try {
      BitmapDescriptor marker;
      if (path != null) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: 160,
        );
        final frame = await codec.getNextFrame();
        final bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        frame.image.dispose();
        codec.dispose();
        if (bytes == null) return;
        marker = BitmapDescriptor.bytes(
          bytes.buffer.asUint8List(),
          width: 64,
          height: 64,
        );
      } else {
        marker = await _placeIcon(Icons.navigation_rounded);
      }
      if (mounted && generation == _iconGeneration)
        setState(() => _driverIcon = marker);
    } catch (_) {
      /* Keep native fallback marker if decoding fails. */
    }
  }

  Future<BitmapDescriptor> _placeIcon(IconData icon, {ui.Image? logo}) async {
    final recorder = ui.PictureRecorder();
    final draw = Canvas(recorder);
    draw.drawCircle(
      const Offset(48, 48),
      44,
      Paint()..color = const Color(0x2200296B),
    );
    draw.drawCircle(const Offset(48, 46), 40, Paint()..color = Colors.white);
    draw.drawCircle(const Offset(48, 46), 35, Paint()..color = navy);
    if (logo != null) {
      draw.save();
      draw.clipPath(
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(48, 46), radius: 33)),
      );
      paintImage(
        canvas: draw,
        rect: const Rect.fromLTWH(15, 13, 66, 66),
        image: logo,
        fit: BoxFit.cover,
      );
      draw.restore();
    } else {
      final text = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 40,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(draw, Offset(48 - text.width / 2, 46 - text.height / 2));
    }
    final image = await recorder.endRecording().toImage(96, 96);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: 46,
      height: 46,
    );
  }

  Future<void> _makePlaceIcons() async {
    final storeId = widget.order.storeId;
    final home = await _placeIcon(Icons.home_rounded);
    final fallback = await _placeIcon(Icons.storefront_rounded);
    if (!mounted || widget.order.storeId != storeId) return;
    setState(() {
      _homeIcon = home;
      _storeIcon = fallback;
    });
    try {
      final business = await BusinessService.getBusinessDetails(
        storeId,
      ).timeout(const Duration(seconds: 8));
      final url = Uri.tryParse(business?.logoUrl ?? '');
      if (url == null || url.scheme != 'https' || url.host.isEmpty) return;
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 4 * 1024 * 1024)
        return;
      final codec = await ui.instantiateImageCodec(
        response.bodyBytes,
        targetWidth: 132,
      );
      final frame = await codec.getNextFrame();
      final icon = await _placeIcon(
        Icons.storefront_rounded,
        logo: frame.image,
      );
      frame.image.dispose();
      codec.dispose();
      if (mounted && widget.order.storeId == storeId)
        setState(() => _storeIcon = icon);
    } catch (_) {
      /* A missing logo keeps the store icon; GPS remains independent. */
    }
  }

  void _receive(LiveDriverPoint p) {
    if (!_sharing ||
        p.orderId != widget.order.id ||
        p.driverId != widget.order.driverId ||
        _point != null && !p.observedAt.isAfter(_point!.observedAt))
      return;

    _from = _position ?? LatLng(p.latitude, p.longitude);
    _to = LatLng(p.latitude, p.longitude);
    final old = _from!;
    if ((old.latitude - p.latitude).abs() +
            (old.longitude - p.longitude).abs() >
        .00003) {
      final a = old.latitude * math.pi / 180,
          b = p.latitude * math.pi / 180,
          d = (p.longitude - old.longitude) * math.pi / 180;
      _bearing =
          (math.atan2(
                    math.sin(d) * math.cos(b),
                    math.cos(a) * math.sin(b) -
                        math.sin(a) * math.cos(b) * math.cos(d),
                  ) *
                  180 /
                  math.pi +
              360) %
          360;
    } else if (_point == null) {
      _bearing = p.heading;
    }
    _point = p;
    final coordinates = p.route?['coordinates'];
    if (coordinates is List && coordinates.length <= 20000) {
      _road = [
        for (final v in coordinates)
          if (v is List &&
              v.length == 2 &&
              v[0] is num &&
              v[1] is num &&
              (v[0] as num).abs() <= 180 &&
              (v[1] as num).abs() <= 90)
            LatLng((v[1] as num).toDouble(), (v[0] as num).toDouble()),
      ];
    }
    _motion.forward(from: 0);
    if (_following) unawaited(_follow());
  }

  Future<void> _follow() async {
    if (!_following || _map == null || _to == null) return;
    try {
      await _map!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _to!, zoom: 17, tilt: 45, bearing: 0),
        ),
      );
    } catch (_) {
      /* A disposed platform view must not interrupt tracking. */
    }
  }

  @override
  void didUpdateWidget(covariant LiveOrderMap old) {
    super.didUpdateWidget(old);
    if (widget.mapBuilder == null &&
        old.order.vehicleType != widget.order.vehicleType)
      unawaited(_makeDriverIcon());
    if (widget.mapBuilder == null && old.order.storeId != widget.order.storeId)
      unawaited(_makePlaceIcons());
    if (widget.order.id != old.order.id ||
        widget.order.driverId != old.order.driverId ||
        !_sharing) {
      _point = null;
      _road = [];
      _from = null;
      _to = null;
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _iconGeneration++;
    _stream?.cancel();
    _clock?.cancel();
    _motion.dispose();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stale =
        _point != null &&
        DateTime.now().difference(_point!.observedAt).inSeconds > 30;
    final markers = <Marker>{
      if (_destination != null)
        Marker(
          markerId: const MarkerId('customer'),
          position: _destination!,
          infoWindow: const InfoWindow(title: 'عنوان التوصيل'),
          icon:
              _homeIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      if (_sharing && _position != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _position!,
          rotation: _bearing,
          anchor: const Offset(.5, .5),
          flat: false,
          infoWindow: const InfoWindow(title: 'السائق'),
          icon:
              _driverIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
    };
    final origin = _point?.origin;
    if (origin != null)
      markers.add(
        Marker(
          markerId: const MarkerId('store'),
          icon: _storeIcon ?? BitmapDescriptor.defaultMarker,
          position: LatLng(origin[1], origin[0]),
          infoWindow: InfoWindow(title: widget.order.storeName),
        ),
      );
    final points = _road;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: SizedBox(
              height: 235,
              child:
                  _destination == null && _to == null
                      ? const Center(
                        child: Text('نقطة التوصيل غير متاحة على الخريطة'),
                      )
                      : widget.mapBuilder != null
                      ? widget.mapBuilder!(markers, {
                        if (points.length > 1)
                          Polyline(
                            polylineId: const PolylineId('road'),
                            points: points,
                            color: navy,
                            width: 4,
                          ),
                      })
                      : Listener(
                        onPointerDown: (_) {
                          _following = false;
                        },
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _to ?? _destination!,
                            zoom: 15,
                          ),
                          onMapCreated: (c) {
                            _map = c;
                            if (_to != null) unawaited(_follow());
                          },
                          markers: markers,
                          polylines: {
                            if (points.length > 1)
                              Polyline(
                                polylineId: const PolylineId('road'),
                                points: points,
                                color: navy,
                                width: 4,
                              ),
                          },
                          buildingsEnabled: true,
                          mapType: MapType.normal,
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                          mapToolbarEnabled: false,
                          compassEnabled: false,
                        ),
                      ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _sharing ? Icons.delivery_dining : Icons.location_on_outlined,
                  color: navy,
                  size: 21,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !_sharing
                        ? 'سيظهر موقع السائق بعد استلام الطلب'
                        : _point == null
                        ? 'بانتظار تحديث موقع السائق'
                        : stale
                        ? 'آخر تحديث منذ ${DateTime.now().difference(_point!.observedAt).inSeconds} ثانية'
                        : 'موقع السائق محدّث',
                    style: const TextStyle(fontSize: 12, color: navy),
                  ),
                ),
                if (_point != null)
                  IconButton(
                    tooltip: 'متابعة السائق',
                    onPressed: () {
                      setState(() => _following = true);
                      unawaited(_follow());
                    },
                    icon: const Icon(Icons.center_focus_strong, color: navy),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
