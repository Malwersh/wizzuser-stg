class HomeSlide {
  final String id, title, imageUrl, imageVersion, actionType, targetId;
  final String? merchantId, code, description;
  final DateTime endAt;
  final List<Map<String, String>> merchants;
  final bool allMerchants;
  final bool standalone;
  const HomeSlide({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.imageVersion,
    required this.actionType,
    required this.targetId,
    required this.endAt,
    this.merchantId,
    this.code,
    this.description,
    this.merchants = const [],
    this.allMerchants = false,
    this.standalone = false,
  });
  factory HomeSlide.fromJson(Map<String, dynamic> json) {
    final action = Map<String, dynamic>.from(json['action'] as Map);
    final uri = Uri.parse(json['imageUrl'] as String);
    if ((uri.scheme != 'https' &&
            !(json['standalone'] == true && uri.toString().isEmpty)) ||
        !['merchant', 'campaign', 'category'].contains(action['type'])) {
      throw const FormatException('Invalid slideshow destination');
    }
    return HomeSlide(
      standalone: json['standalone'] == true,
      id: json['id'] as String,
      title: json['title'] as String,
      imageUrl: uri.toString(),
      imageVersion: json['imageVersion'] as String? ?? '',
      actionType: action['type'] as String,
      targetId: action['id'] as String,
      merchantId: action['merchantId'] as String?,
      code: action['code'] as String?,
      description: action['description'] as String?,
      merchants:
          (action['merchants'] as List? ?? [])
              .map(
                (m) => <String, String>{
                  'id': m['id'] as String,
                  'name': m['name'] as String,
                },
              )
              .toList(),
      allMerchants: action['allMerchants'] == true,
      endAt: DateTime.parse(json['endAt'] as String),
    );
  }
}
