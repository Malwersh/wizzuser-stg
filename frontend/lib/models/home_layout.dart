/// Published layout contains presentation rules only, never prices or benefits.
class HomeSection {
  final String id, title, source;
  final List<String> merchantIds;
  final int limit;
  final DateTime? startAt, endAt;
  HomeSection.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      source = json['source'] as String,
      merchantIds = List<String>.from(json['merchantIds'] ?? []),
      limit = json['limit'] as int,
      startAt = DateTime.tryParse(json['startAt'] ?? ''),
      endAt = DateTime.tryParse(json['endAt'] ?? '') {
    if (!['region', 'rating', 'new', 'curated', 'favorites'].contains(source) ||
        limit < 1 ||
        limit > 12 ||
        title.isEmpty) {
      throw const FormatException('Unsupported home section');
    }
  }
  bool activeAt(DateTime now) =>
      (startAt == null || !now.isBefore(startAt!)) &&
      (endAt == null || now.isBefore(endAt!));
}

class HomeLayout {
  final bool configured;
  final List<HomeSection> sections;
  HomeLayout.fromJson(Map<String, dynamic> json)
    : configured = json['configured'] == true,
      sections =
          (json['sections'] as List? ?? [])
              .map((x) => HomeSection.fromJson(Map<String, dynamic>.from(x)))
              .toList();
}
