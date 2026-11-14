import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ActiveRegion {
  final String id, name;
  String? city;
  String? district;
  final String? parentId;
  final int level;
  final Map<String, dynamic>? bounds;
  ActiveRegion.fromJson(Map<String, dynamic> value)
    : id = value['id'] as String,
      name = value['labelAr'] as String,
      parentId = value['parentId'] as String?,
      level = value['level'] as int,
      bounds =
          value['bounds'] == null
              ? null
              : Map<String, dynamic>.from(value['bounds']);
}

class ActiveRegionCatalog {
  final http.Client? client;
  ActiveRegionCatalog({this.client});
  Future<List<ActiveRegion>> load() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.regionLookupEndpoint}',
    ).replace(queryParameters: {'view': 'active-tree'});
    final response = await (client?.get ?? http.get)(uri).timeout(
      const Duration(seconds: 15),
    );
    if (response.statusCode != 200)
      throw Exception('تعذر تحميل المناطق. أعد المحاولة.');
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload['success'] != true ||
        payload['data']?['schemaVersion'] != 313 ||
        payload['data']?['items'] is! List) {
      throw const FormatException('Invalid region catalog');
    }
    final items =
        (payload['data']['items'] as List)
            .map((r) => ActiveRegion.fromJson(Map<String, dynamic>.from(r)))
            .toList();
    final byId = {for (final item in items) item.id: item};
    for (final item in items.where((r) => r.level == 3)) {
      final district = byId[item.parentId];
      item.district = district?.name;
      item.city = byId[district?.parentId]?.name;
    }
    return items;
  }
}
