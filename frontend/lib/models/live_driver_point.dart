class LiveDriverPoint {
  final String orderId, driverId;
  final double latitude, longitude, heading, accuracy;
  final DateTime observedAt;
  final Map<String, dynamic>? route;
  final List<double>? origin, destination;
  LiveDriverPoint({
    required this.orderId,
    required this.driverId,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.accuracy,
    required this.observedAt,
    this.route,
    this.origin,
    this.destination,
  });
  static LiveDriverPoint? parse(Map<String, dynamic> data, {DateTime? now}) {
    try {
      final p = Map<String, dynamic>.from(data['location']);
      final lat = (p['latitude'] as num).toDouble(),
          lng = (p['longitude'] as num).toDouble(),
          heading = (p['heading'] as num).toDouble(),
          accuracy = (p['accuracy'] as num).toDouble();
      final at = DateTime.parse(p['observedAt']), clock = now ?? DateTime.now();
      if (![lat, lng, heading, accuracy].every((v) => v.isFinite) ||
          lat.abs() > 90 ||
          lng.abs() > 180 ||
          heading < 0 ||
          heading >= 360 ||
          accuracy < 0 ||
          accuracy > 100 ||
          clock.difference(at).inSeconds > 60 ||
          at.difference(clock).inSeconds > 5)
        return null;
      List<double>? point(dynamic v) {
        if (v is! List || v.length != 2) return null;
        final a = v.map((x) => (x as num).toDouble()).toList();
        return a.every((x) => x.isFinite) &&
                a[0].abs() <= 180 &&
                a[1].abs() <= 90
            ? a
            : null;
      }

      return LiveDriverPoint(
        orderId: data['orderId'] as String,
        driverId: data['driverId'] as String,
        latitude: lat,
        longitude: lng,
        heading: heading,
        accuracy: accuracy,
        observedAt: at,
        route:
            data['route'] is Map
                ? Map<String, dynamic>.from(data['route'])
                : null,
        origin: point(data['origin']),
        destination: point(data['destination']),
      );
    } catch (_) {
      return null;
    }
  }
}
