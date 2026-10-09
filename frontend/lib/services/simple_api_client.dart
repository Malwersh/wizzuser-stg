// Placeholder SimpleApiClient - Frontend Only
// This is a simple placeholder service for the frontend until backend is ready

// import 'dart:convert'; // Unused import
// import 'package:http/http.dart' as http; // Unused import

class SimpleApiClient {
  static final SimpleApiClient _instance = SimpleApiClient._internal();
  factory SimpleApiClient() => _instance;
  SimpleApiClient._internal();

  // final String _baseUrl = 'https://placeholder-api.example.com'; // Unused field
  // final Map<String, String> _defaultHeaders = { // Unused field
  //   'Content-Type': 'application/json',
  //   'Accept': 'application/json',
  // };

  // GET request placeholder
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? headers}) async {
    await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
    
    // Return placeholder data based on endpoint
    if (endpoint.contains('/restaurants')) {
      return _getRestaurantsPlaceholder();
    } else if (endpoint.contains('/dishes')) {
      return _getDishesPlaceholder();
    } else if (endpoint.contains('/orders')) {
      return _getOrdersPlaceholder();
    } else if (endpoint.contains('/user')) {
      return _getUserPlaceholder();
    }
    
    return {
      'success': true,
      'data': {},
      'message': 'Placeholder response'
    };
  }

  // POST request placeholder
  Future<Map<String, dynamic>> post(String endpoint, {Map<String, dynamic>? body, Map<String, String>? headers}) async {
    await Future.delayed(const Duration(milliseconds: 800)); // Simulate network delay
    
    return {
      'success': true,
      'data': body ?? {},
      'message': 'Data processed successfully'
    };
  }

  // PUT request placeholder
  Future<Map<String, dynamic>> put(String endpoint, {Map<String, dynamic>? body, Map<String, String>? headers}) async {
    await Future.delayed(const Duration(milliseconds: 700)); // Simulate network delay
    
    return {
      'success': true,
      'data': body ?? {},
      'message': 'Data updated successfully'
    };
  }

  // DELETE request placeholder
  Future<Map<String, dynamic>> delete(String endpoint, {Map<String, String>? headers}) async {
    await Future.delayed(const Duration(milliseconds: 600)); // Simulate network delay
    
    return {
      'success': true,
      'message': 'Data deleted successfully'
    };
  }

  // Upload file placeholder
  Future<Map<String, dynamic>> upload(String endpoint, String filePath, {Map<String, String>? fields}) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate upload delay
    
    return {
      'success': true,
      'data': {
        'url': 'https://placeholder-images.example.com/uploaded-file.jpg',
        'filename': filePath.split('/').last,
      },
      'message': 'File uploaded successfully'
    };
  }

  // Login method placeholder
  Future<Map<String, dynamic>> login({required String username, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Always succeed in placeholder mode
    return {
      'success': true,
      'data': {
        'user': {
          'id': 'placeholder_user_id',
          'username': username,
          'email': username.contains('@') ? username : 'user@example.com',
          'name': 'Placeholder User',
        },
        'token': 'placeholder_jwt_token',
        'refreshToken': 'placeholder_refresh_token',
      },
      'message': 'Login successful'
    };
  }

  // Register method placeholder
  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    await Future.delayed(const Duration(seconds: 1));
    
    return {
      'success': true,
      'data': {
        'user': {
          'id': 'placeholder_user_id',
          'name': userData['name'] ?? 'New User',
          'email': userData['email'] ?? 'newuser@example.com',
          'phone': userData['phone'] ?? '+1234567890',
        },
        'token': 'placeholder_jwt_token',
        'refreshToken': 'placeholder_refresh_token',
      },
      'message': 'Registration successful'
    };
  }

  // Placeholder data generators
  Map<String, dynamic> _getRestaurantsPlaceholder() {
    return {
      'success': true,
      'data': [
        {
          'id': '1',
          'name': 'Pizza Palace',
          'image': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400',
          'rating': 4.5,
          'deliveryTime': '25-30 min',
          'deliveryFee': 2.99,
          'category': 'Italian',
          'isOpen': true,
        },
        {
          'id': '2',
          'name': 'Burger House',
          'image': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400',
          'rating': 4.2,
          'deliveryTime': '20-25 min',
          'deliveryFee': 1.99,
          'category': 'Fast Food',
          'isOpen': true,
        },
        {
          'id': '3',
          'name': 'Sushi Express',
          'image': 'https://images.unsplash.com/photo-1553621042-f6e147245754?w=400',
          'rating': 4.8,
          'deliveryTime': '30-40 min',
          'deliveryFee': 3.99,
          'category': 'Japanese',
          'isOpen': false,
        },
      ],
      'pagination': {
        'currentPage': 1,
        'totalPages': 3,
        'totalItems': 25,
      }
    };
  }

  Map<String, dynamic> _getDishesPlaceholder() {
    return {
      'success': true,
      'data': [
        {
          'id': '1',
          'name': 'Margherita Pizza',
          'description': 'Classic pizza with tomato sauce, mozzarella, and fresh basil',
          'price': 12.99,
          'image': 'https://images.unsplash.com/photo-1604382354936-07c5d9983bd3?w=400',
          'category': 'Pizza',
          'isVegetarian': true,
          'isAvailable': true,
        },
        {
          'id': '2',
          'name': 'Beef Burger',
          'description': 'Juicy beef patty with lettuce, tomato, and special sauce',
          'price': 9.99,
          'image': 'https://images.unsplash.com/photo-1571091718767-18b5b1457add?w=400',
          'category': 'Burgers',
          'isVegetarian': false,
          'isAvailable': true,
        },
        {
          'id': '3',
          'name': 'Salmon Roll',
          'description': 'Fresh salmon sushi roll with avocado and cucumber',
          'price': 8.99,
          'image': 'https://images.unsplash.com/photo-1579584425555-c3ce17fd4351?w=400',
          'category': 'Sushi',
          'isVegetarian': false,
          'isAvailable': true,
        },
      ]
    };
  }

  Map<String, dynamic> _getOrdersPlaceholder() {
    return {
      'success': true,
      'data': [
        {
          'id': 'ORD001',
          'status': 'delivered',
          'restaurant': 'Pizza Palace',
          'items': [
            {'name': 'Margherita Pizza', 'quantity': 2, 'price': 12.99},
            {'name': 'Garlic Bread', 'quantity': 1, 'price': 4.99},
          ],
          'total': 30.97,
          'orderDate': '2024-01-15T18:30:00Z',
          'deliveryAddress': '123 Main St, City, State',
        },
        {
          'id': 'ORD002',
          'status': 'preparing',
          'restaurant': 'Burger House',
          'items': [
            {'name': 'Beef Burger', 'quantity': 1, 'price': 9.99},
            {'name': 'French Fries', 'quantity': 1, 'price': 3.99},
          ],
          'total': 13.98,
          'orderDate': '2024-01-16T12:15:00Z',
          'deliveryAddress': '456 Oak Ave, City, State',
        },
      ]
    };
  }

  Map<String, dynamic> _getUserPlaceholder() {
    return {
      'success': true,
      'data': {
        'id': 'placeholder_user_id',
        'name': 'Placeholder User',
        'email': 'user@example.com',
        'phone': '+1234567890',
        'addresses': [
          {
            'id': '1',
            'type': 'home',
            'address': '123 Main St',
            'city': 'Sample City',
            'state': 'Sample State',
            'zipCode': '12345',
            'isDefault': true,
          },
          {
            'id': '2',
            'type': 'work',
            'address': '456 Oak Ave',
            'city': 'Sample City',
            'state': 'Sample State',
            'zipCode': '12345',
            'isDefault': false,
          },
        ],
        'preferences': {
          'language': 'en',
          'currency': 'USD',
          'notifications': true,
        }
      }
    };
  }
}
