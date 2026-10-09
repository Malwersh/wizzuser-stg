// lib/models/menu_item.dart

class MenuItem {
  final String id;
  final String name;
  final String image;
  final double price;
  final int likesPercent;
  final int likesCount;
  final String? tag;         // وسوم مثل "#1 Most Liked"
  final String description;  // ← أضفنا حقل الوصف

  MenuItem({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    required this.likesPercent,
    required this.likesCount,
    this.tag,
    required this.description,  // ← أصبح إلزامياً
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String,
        name: json['name'] as String,
        image: json['image'] as String,
        price: (json['price'] as num).toDouble(),
        likesPercent: json['likesPercent'] as int,
        likesCount: json['likesCount'] as int,
        tag: json['tag'] as String?,
        description: json['description'] as String? 
            ?? '',  // إذا لم يأتِ من الـ API فلا بأس بأن نتركه فارغاً
      );

  /// عناصر تجريبية مؤقتة مع وصف افتراضي
  static MenuItem placeholder(int index) => MenuItem(
        id: 'placeholder-$index',
        name: 'بند ${index + 1}',
        image: 'assets/images/food_placeholder.png',
        price: 5.0 + index,
        likesPercent: 70 + index,
        likesCount: 10 * index,
        tag: index == 2 ? '#${index + 1} Most Liked' : null,
        description: 'هذا وصف تجريبي للعنصر ${index + 1}',
      );

  static List<MenuItem> placeholderList(int count) =>
      List.generate(count, (i) => placeholder(i));
}
