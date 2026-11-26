import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class RegionBoundary {
  final String regionId, name;
  final List<List<List<LatLng>>> polygons;
  RegionBoundary({
    required this.regionId,
    required this.name,
    required this.polygons,
  });
  factory RegionBoundary.fromJson(Map<String, dynamic> value) {
    final geometry = Map<String, dynamic>.from(value['geometry'] as Map);
    final type = geometry['type'];
    if (type != 'Polygon' && type != 'MultiPolygon') {
      throw const FormatException('Unsupported boundary');
    }
    final raw =
        type == 'Polygon'
            ? [geometry['coordinates']]
            : geometry['coordinates'] as List;
    final polygons = <List<List<LatLng>>>[];
    var vertices = 0;
    for (final p in raw) {
      final rings = <List<LatLng>>[];
      for (final ring in p as List) {
        final points = <LatLng>[];
        for (final coordinate in ring as List) {
          final lon = (coordinate[0] as num).toDouble(),
              lat = (coordinate[1] as num).toDouble();
          if (!lat.isFinite ||
              !lon.isFinite ||
              lat.abs() > 90 ||
              lon.abs() > 180 ||
              ++vertices > 6000) {
            throw const FormatException('Invalid boundary');
          }
          points.add(LatLng(lat, lon));
        }
        if (points.length < 4 || points.first != points.last) {
          throw const FormatException('Unclosed boundary');
        }
        rings.add(points);
      }
      if (rings.isEmpty) throw const FormatException('Empty polygon');
      polygons.add(rings);
    }
    if (polygons.isEmpty) throw const FormatException('Empty boundary');
    return RegionBoundary(
      regionId: value['regionId'] as String,
      name: value['nameAr'] as String,
      polygons: polygons,
    );
  }
  LatLngBounds get bounds {
    final points = polygons.expand((p) => p.first).toList();
    var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }
}

class RegionBoundaryService {
  final http.Client? client;
  RegionBoundaryService({this.client});
  Future<RegionBoundary> load(String id) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.regionLookupEndpoint}',
    ).replace(queryParameters: {'view': 'boundary', 'region_id': id});
    final response = await (client?.get ?? http.get)(uri).timeout(
      const Duration(seconds: 15),
    );
    if (response.statusCode != 200) {
      throw Exception('تعذر تحميل حدود المنطقة. أعد المحاولة.');
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload['success'] != true) {
      throw const FormatException('Invalid boundary response');
    }
    final boundary = RegionBoundary.fromJson(
      Map<String, dynamic>.from(payload['data']),
    );
    if (boundary.regionId != id) {
      throw const FormatException('Wrong region boundary');
    }
    return boundary;
  }
}
