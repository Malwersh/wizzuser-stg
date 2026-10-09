class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final DateTime? birthdate;
  final String gender;
  final bool marketingConsent;
  final bool newsletterSubscription;
  final String languagePreference;
  final Map<String, dynamic> notificationSettings;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.birthdate,
    required this.gender,
    required this.marketingConsent,
    required this.newsletterSubscription,
    required this.languagePreference,
    required this.notificationSettings,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    DateTime? parseBirthdate(dynamic birthdateValue) {
      if (birthdateValue == null) return null;
      if (birthdateValue is String && birthdateValue.isEmpty) return null;
      
      try {
        if (birthdateValue is String) {
          return DateTime.parse(birthdateValue);
        } else if (birthdateValue is DateTime) {
          return birthdateValue;
        }
      } catch (e) {
        // Ignore date parsing errors
      }
      return null;
    }

    return UserProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      birthdate: parseBirthdate(json['birthdate']),
      gender: json['gender'] ?? 'male',
      marketingConsent: json['marketing_consent'] ?? false,
      newsletterSubscription: json['newsletter_subscription'] ?? false,
      languagePreference: json['language_preference'] ?? 'ar',
      notificationSettings: json['notification_settings'] ?? {
        'order_notifications': true,
        'promotion_notifications': true,
        'newsletter_notifications': false,
        'reminder_notifications': true,
        'sound_enabled': true,
        'vibration_enabled': true,
      },
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'birthdate': birthdate?.toIso8601String(),
      'gender': gender,
      'marketing_consent': marketingConsent,
      'newsletter_subscription': newsletterSubscription,
      'language_preference': languagePreference,
      'notification_settings': notificationSettings,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    DateTime? birthdate,
    String? gender,
    bool? marketingConsent,
    bool? newsletterSubscription,
    String? languagePreference,
    Map<String, dynamic>? notificationSettings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      birthdate: birthdate ?? this.birthdate,
      gender: gender ?? this.gender,
      marketingConsent: marketingConsent ?? this.marketingConsent,
      newsletterSubscription: newsletterSubscription ?? this.newsletterSubscription,
      languagePreference: languagePreference ?? this.languagePreference,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'UserProfile(id: $id, name: $name, email: $email, phone: $phone, birthdate: $birthdate, gender: $gender, marketingConsent: $marketingConsent, newsletterSubscription: $newsletterSubscription, languagePreference: $languagePreference)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is UserProfile &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.phone == phone &&
        other.birthdate == birthdate &&
        other.gender == gender &&
        other.marketingConsent == marketingConsent &&
        other.newsletterSubscription == newsletterSubscription &&
        other.languagePreference == languagePreference;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        email.hashCode ^
        phone.hashCode ^
        birthdate.hashCode ^
        gender.hashCode ^
        marketingConsent.hashCode ^
        newsletterSubscription.hashCode;
  }
}
