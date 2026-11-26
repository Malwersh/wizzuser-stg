import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Foreground acquisition only. A hint never changes the chosen destination.
class DeviceLocationHint {
  static final instance = DeviceLocationHint();
  Future<LatLng?>? _pending;
  LatLng? _point;
  DateTime? _at;
  LatLng? get recent =>
      _at != null &&
              DateTime.now().difference(_at!) < const Duration(minutes: 2)
          ? _point
          : null;
  Future<LatLng?> acquire({bool requestPermission = false}) async {
    if (recent != null) return recent;
    if (_pending != null) {
      final result = await _pending;
      if (result != null || !requestPermission) return result;
    }
    final task = _read(requestPermission);
    _pending = task;
    try {
      return await task;
    } finally {
      if (identical(_pending, task)) _pending = null;
    }
  }

  Future<LatLng?> _read(bool request) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && request)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));
      if (!p.latitude.isFinite ||
          !p.longitude.isFinite ||
          !p.accuracy.isFinite ||
          p.accuracy > 100)
        return null;
      _point = LatLng(p.latitude, p.longitude);
      _at = DateTime.now();
      return _point;
    } catch (_) {
      return null;
    }
  }
}
