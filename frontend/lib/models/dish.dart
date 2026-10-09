// lib/models/dish.dart

class Option {
  /// معرف الخيار (مستخدم كقيمة في الـ Radio/Checkbox)
  final String id;

  /// اسم الخيار المعروض
  final String name;

  /// الزيادة على السعر الأساسي (يمكن أن تكون صفر)
  final double extraPrice;

  Option({
    required this.id,
    required this.name,
    required this.extraPrice,
  });

  // إذا احتجنا لاحقاً لتحويل من/إلى JSON:
  factory Option.fromJson(Map<String, dynamic> json) => Option(
        id: json['id'] as String,
        name: json['name'] as String,
        extraPrice: (json['extraPrice'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'extraPrice': extraPrice,
      };
}

class OptionGroup {
  /// معرف المجموعة الفريد
  final String id;

  /// عنوان المجموعة (مثلاً "اختيار نوع الجبن")
  final String title;

  /// هل هذه المجموعة مطلوبة (Required) أم اختيارية
  final bool required;

  /// الحد الأقصى لعدد الاختيارات (up to هذه القيمة)
  final int maxSelections;

  /// قائمة الخيارات ضمن هذه المجموعة
  final List<Option> options;

  OptionGroup({
    required this.id,
    required this.title,
    required this.required,
    required this.maxSelections,
    required this.options,
  });

  factory OptionGroup.fromJson(Map<String, dynamic> json) => OptionGroup(
        id: json['id'] as String,
        title: json['title'] as String,
        required: json['required'] as bool,
        maxSelections: json['maxSelections'] as int,
        options: (json['options'] as List<dynamic>)
            .map((e) => Option.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'required': required,
        'maxSelections': maxSelections,
        'options': options.map((o) => o.toJson()).toList(),
      };
}

class Dish {
  final String id;
  final String name;
  final List<String> imageUrls;
  final String description;
  final int likesPercent;
  final int likesCount;
  final double basePrice;

  /// كل مجموعة خيارات لهذا الطبق
  final List<OptionGroup> optionGroups;

  Dish({
    required this.id,
    required this.name,
    required this.imageUrls,
    required this.description,
    required this.likesPercent,
    required this.likesCount,
    required this.basePrice,
    required this.optionGroups,
  });

  factory Dish.fromJson(Map<String, dynamic> json) => Dish(
        id: json['id'] as String,
        name: json['name'] as String,
        imageUrls:
            List<String>.from(json['imageUrls'] as List<dynamic>),
        description: json['description'] as String,
        likesPercent: json['likesPercent'] as int,
        likesCount: json['likesCount'] as int,
        basePrice: (json['basePrice'] as num).toDouble(),
        optionGroups: (json['optionGroups'] as List<dynamic>)
            .map((e) =>
                OptionGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrls': imageUrls,
        'description': description,
        'likesPercent': likesPercent,
        'likesCount': likesCount,
        'basePrice': basePrice,
        'optionGroups': optionGroups.map((g) => g.toJson()).toList(),
      };
}
