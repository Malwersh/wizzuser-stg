class StoreModel {
  final String id;
  final String name;
  final String location;
  final String city;
  final bool isOpen;
  final double rating;

  StoreModel({
    required this.id,
    required this.name,
    required this.location,
    required this.city,
    required this.isOpen,
    required this.rating,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    return StoreModel(
      id: json['id'],
      name: json['name'],
      location: json['location'],
      city: json['city'],
      isOpen: json['isOpen'],
      rating: json['rating'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'city': city,
      'isOpen': isOpen,
      'rating': rating,
    };
  }
}
