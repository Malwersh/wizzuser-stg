/// Browsing an area never supplies invented delivery coordinates.
class BrowsingLocation {
  final String regionId, regionName;
  final String source;
  final double? latitude, longitude;
  final String? addressText, savedAddressId;
  const BrowsingLocation({
    required this.regionId,
    required this.regionName,
    required this.source,
    this.latitude,
    this.longitude,
    this.addressText,
    this.savedAddressId,
  });
  bool get hasPoint => latitude != null && longitude != null;
  Map<String, dynamic> toJson() => {
    'regionId': regionId,
    'regionName': regionName,
    'source': source,
    'latitude': latitude,
    'longitude': longitude,
    'addressText': addressText,
    'savedAddressId': savedAddressId,
  };
  factory BrowsingLocation.fromJson(Map<String, dynamic> row) {
    if (row['regionId'] is! String ||
        (row['regionId'] as String).isEmpty ||
        row['regionName'] is! String ||
        !['region', 'search', 'gps', 'saved'].contains(row['source']))
      throw const FormatException('Invalid browsing selection');
    final lat = row['latitude'], lng = row['longitude'];
    if ((lat == null) != (lng == null) ||
        (lat != null &&
            (lat is! num ||
                lng is! num ||
                !lat.isFinite ||
                !lng.isFinite ||
                lat.abs() > 90 ||
                lng.abs() > 180)))
      throw const FormatException('Invalid browsing point');
    if (lat == null) throw const FormatException('Missing selected point');
    if (row['source'] == 'saved' &&
        (row['savedAddressId'] is! String ||
            (row['savedAddressId'] as String).isEmpty))
      throw const FormatException('Missing saved address');
    if (row['source'] == 'region' && row['savedAddressId'] != null)
      throw const FormatException(
        'Region selection cannot claim a saved address',
      );
    return BrowsingLocation(
      regionId: row['regionId'],
      regionName: row['regionName'],
      source: row['source'],
      latitude: (lat as num?)?.toDouble(),
      longitude: (lng as num?)?.toDouble(),
      addressText: row['addressText'] as String?,
      savedAddressId: row['savedAddressId'] as String?,
    );
  }
}
