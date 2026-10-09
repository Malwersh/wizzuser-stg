// نموذج لمعالجة العنوان من قاعدة البيانات
import 'dart:developer' as developer;

class BusinessAddress {
  final String? country;
  final String? city;
  final String? district;
  final String? street;

  BusinessAddress({
    this.country,
    this.city,
    this.district,
    this.street,
  });

  /// تحويل من JSON المُخزن في قاعدة البيانات
  /// مثال: { "country" : { "S" : "Iraq" }, "city" : { "S" : "النجف" }, "street" : { "S" : "مسلم بين عقيل" }, "district" : { "S" : "الكوفة" } }
  factory BusinessAddress.fromDynamoDBJson(Map<String, dynamic> json) {
    try {
      return BusinessAddress(
        country: json['country']?['S']?.toString(),
        city: json['city']?['S']?.toString(),
        district: json['district']?['S']?.toString(),
        street: json['street']?['S']?.toString(),
      );
    } catch (e) {
      developer.log('خطأ في تحليل العنوان من DynamoDB: $e');
      return BusinessAddress();
    }
  }

  /// تحويل من JSON عادي
  factory BusinessAddress.fromJson(Map<String, dynamic> json) {
    return BusinessAddress(
      country: json['country']?.toString(),
      city: json['city']?.toString(),
      district: json['district']?.toString(),
      street: json['street']?.toString(),
    );
  }

  /// تحويل من String (إذا كان العنوان مُحول مسبقاً إلى string)
  factory BusinessAddress.fromString(String addressString) {
    try {
      // محاولة تحليل العنوان من النص
      // تنسيق متوقع: "المدينة، المقاطعة، الشارع"
      final parts = addressString.split('، ').map((s) => s.trim()).toList();
      
      if (parts.length >= 3) {
        return BusinessAddress(
          city: parts[0].isNotEmpty ? parts[0] : null,
          district: parts[1].isNotEmpty ? parts[1] : null,
          street: parts[2].isNotEmpty ? parts[2] : null,
        );
      } else if (parts.length == 2) {
        return BusinessAddress(
          city: parts[0].isNotEmpty ? parts[0] : null,
          district: parts[1].isNotEmpty ? parts[1] : null,
        );
      } else if (parts.length == 1) {
        return BusinessAddress(
          city: parts[0].isNotEmpty ? parts[0] : null,
        );
      }
      
      return BusinessAddress();
    } catch (e) {
      developer.log('خطأ في تحليل العنوان من النص: $e');
      return BusinessAddress();
    }
  }

  /// تنسيق العنوان للعرض حسب المطلوب:
  /// المدينة، المقاطعة
  /// الشارع
  String getFormattedAddress() {
    final List<String> firstLine = [];
    final List<String> secondLine = [];

    // السطر الأول: المدينة، المقاطعة
    if (city?.isNotEmpty == true) {
      firstLine.add(city!);
    }
    if (district?.isNotEmpty == true) {
      firstLine.add(district!);
    }

    // السطر الثاني: الشارع
    if (street?.isNotEmpty == true) {
      secondLine.add(street!);
    }

    final List<String> result = [];
    if (firstLine.isNotEmpty) {
      result.add(firstLine.join('، '));
    }
    if (secondLine.isNotEmpty) {
      result.add(secondLine.join(''));
    }

    return result.isNotEmpty ? result.join('\n') : 'العنوان غير متوفر';
  }

  /// للعرض في سطر واحد
  String getShortAddress() {
    final List<String> parts = [];
    
    if (city?.isNotEmpty == true) {
      parts.add(city!);
    }
    if (district?.isNotEmpty == true) {
      parts.add(district!);
    }
    if (street?.isNotEmpty == true) {
      parts.add(street!);
    }

    return parts.isNotEmpty ? parts.join('، ') : 'العنوان غير متوفر';
  }

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'city': city,
      'district': district,
      'street': street,
    };
  }

  @override
  String toString() {
    return getShortAddress();
  }

  bool get isEmpty => 
    (city?.isEmpty ?? true) && 
    (district?.isEmpty ?? true) && 
    (street?.isEmpty ?? true);

  bool get isNotEmpty => !isEmpty;
}
