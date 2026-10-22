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

  /// 🔥 محاولة تحويل بيانات الإضافات/الخيارات الخام من الباك إند إلى OptionGroup.
  /// الشكل غير موحد في الـ API الحالي، لذلك هذه الدالة دفاعية:
  /// تتعرف على مجموعات {title/options} وعلى القوائم المسطحة {name, price}
  /// وتعيد قائمة فارغة عندما لا يتعرف على الشكل.
  static List<OptionGroup> listFromAddons(dynamic raw) {
    try {
      if (raw == null) return const [];

      // خريطة تحتوي على قائمة مجموعات
      if (raw is Map) {
        for (final key in const ['groups', 'optionGroups', 'addons', 'items']) {
          final inner = raw[key];
          if (inner is List) return listFromAddons(inner);
        }
        return const [];
      }

      if (raw is! List || raw.isEmpty) return const [];

      final groups = <OptionGroup>[];
      final flatOptions = <Option>[];

      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);

        final nested = map['options'] ?? map['choices'] ?? map['items'];
        if (nested is List) {
          final options = <Option>[];
          for (var j = 0; j < nested.length; j++) {
            final opt = nested[j];
            if (opt is! Map) continue;
            final optMap = Map<String, dynamic>.from(opt);
            if (optMap['isAvailable'] == false) continue;
            final name = (optMap['name'] ?? optMap['label'] ?? optMap['title'])?.toString() ?? '';
            if (name.isEmpty) continue;
            options.add(Option(
              id: (optMap['id'] ?? optMap['value'] ?? name).toString(),
              name: name,
              extraPrice: (optMap['extraPrice'] ?? optMap['price'] ?? optMap['additionalPrice']) is num
                  ? ((optMap['extraPrice'] ?? optMap['price'] ?? optMap['additionalPrice']) as num).toDouble()
                  : 0.0,
            ));
          }
          if (options.isEmpty) continue;

          final required = map['required'] == true || map['isRequired'] == true;
          final rawMax = map['maxSelections'] ?? map['max'] ?? map['maxChoices'] ?? map['limit'];
          final max = rawMax is num
              ? rawMax.toInt()
              : (required ? 1 : options.length);

          groups.add(OptionGroup(
            id: (map['id'] ?? map['name'] ?? 'group_$i').toString(),
            title: (map['title'] ?? map['name'] ?? map['groupName'] ?? map['label'] ?? 'خيارات').toString(),
            required: required,
            maxSelections: max <= 0 ? 1 : max,
            options: options,
          ));
        } else {
          // عنصر مسطح: {name, price} → إضافة بسيطة
          final name = (map['name'] ?? map['label'] ?? map['title'])?.toString() ?? '';
          if (name.isEmpty) continue;
          flatOptions.add(Option(
            id: (map['id'] ?? map['value'] ?? name).toString(),
            name: name,
            extraPrice: (map['extraPrice'] ?? map['price'] ?? map['additionalPrice']) is num
                ? ((map['extraPrice'] ?? map['price'] ?? map['additionalPrice']) as num).toDouble()
                : 0.0,
          ));
        }
      }

      if (flatOptions.isNotEmpty) {
        groups.add(OptionGroup(
          id: 'addons_flat',
          title: 'إضافات',
          required: false,
          maxSelections: flatOptions.length,
          options: flatOptions,
        ));
      }

      return groups;
    } catch (_) {
      return const [];
    }
  }

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
