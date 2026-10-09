// lib/providers/improved_app_providers.dart
// Enhanced App State Providers using Riverpod

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/session_service.dart';
import '../services/auth_service.dart';

// Auth State Provider
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  return AuthStateNotifier();
});

class AuthState {
  final bool isLoggedIn;
  final bool isGuest;
  final bool isLoading;
  final Map<String, dynamic>? userData;
  final String? errorMessage;

  const AuthState({
    this.isLoggedIn = false,
    this.isGuest = false,
    this.isLoading = false,
    this.userData,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isGuest,
    bool? isLoading,
    Map<String, dynamic>? userData,
    String? errorMessage,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isGuest: isGuest ?? this.isGuest,
      isLoading: isLoading ?? this.isLoading,
      userData: userData ?? this.userData,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier() : super(const AuthState());

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    
    try {
      // Use the unified login endpoint
      Map<String, dynamic> result = await AuthService.login(
        username: username, 
        password: password
      );

      if (result['success'] == true) {
        final userData = result['data']?['user'] ?? {};
        final data = result['data'] ?? {};
        await SessionService.instance.saveSessionData({
          'access_token': data['access_token'] ?? '',
          'id_token': data['id_token'] ?? '',
          'refresh_token': data['refresh_token'] ?? '',
          'userData': userData,
        });
        state = state.copyWith(
          isLoggedIn: true,
          isLoading: false,
          userData: userData,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result['message'] ?? 'فشل في تسجيل الدخول',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'خطأ في الاتصال',
      );
    }
  }

  Future<void> logout() async {
    await SessionService.instance.logout();
    state = const AuthState();
  }

  Future<void> loginAsGuest() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    
    try {
      // Set guest mode
      state = state.copyWith(
        isLoggedIn: false,
        isGuest: true,
        isLoading: false,
        userData: {'userType': 'guest'},
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'خطأ في تسجيل الدخول كضيف',
      );
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

// Cart State Provider
final cartStateProvider = StateNotifierProvider<CartStateNotifier, CartState>((ref) {
  return CartStateNotifier();
});

class CartState {
  final List<Map<String, dynamic>> items;
  final double total;
  final bool isLoading;

  const CartState({
    this.items = const [],
    this.total = 0.0,
    this.isLoading = false,
  });

  CartState copyWith({
    List<Map<String, dynamic>>? items,
    double? total,
    bool? isLoading,
  }) {
    return CartState(
      items: items ?? this.items,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class CartStateNotifier extends StateNotifier<CartState> {
  CartStateNotifier() : super(const CartState());

  Future<void> loadCart() async {
    state = state.copyWith(isLoading: true);
    
    try {
      final cartItems = await SessionService.instance.getCartItems();
      final total = cartItems.fold<double>(
        0.0,
        (sum, item) => sum + ((item['price'] ?? 0.0) * (item['quantity'] ?? 1)),
      );
      
      state = state.copyWith(
        items: cartItems,
        total: total,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> addItem(Map<String, dynamic> item) async {
    final updatedItems = [...state.items, item];
    await SessionService.instance.saveCartItems(updatedItems);
    await loadCart();
  }

  Future<void> removeItem(int index) async {
    final updatedItems = [...state.items];
    updatedItems.removeAt(index);
    await SessionService.instance.saveCartItems(updatedItems);
    await loadCart();
  }

  Future<void> updateItemQuantity(int index, int quantity) async {
    final updatedItems = [...state.items];
    if (quantity <= 0) {
      updatedItems.removeAt(index);
    } else {
      updatedItems[index]['quantity'] = quantity;
    }
    await SessionService.instance.saveCartItems(updatedItems);
    await loadCart();
  }

  Future<void> clearCart() async {
    await SessionService.instance.saveCartItems([]);
    state = const CartState();
  }
}

// User Profile State Provider
final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfileState>((ref) {
  return UserProfileNotifier();
});

class UserProfileState {
  final Map<String, dynamic>? profile;
  final bool isLoading;
  final String? errorMessage;

  const UserProfileState({
    this.profile,
    this.isLoading = false,
    this.errorMessage,
  });

  UserProfileState copyWith({
    Map<String, dynamic>? profile,
    bool? isLoading,
    String? errorMessage,
  }) {
    return UserProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class UserProfileNotifier extends StateNotifier<UserProfileState> {
  UserProfileNotifier() : super(const UserProfileState());

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true);
    
    try {
      final userData = await SessionService.instance.getUserData();
      state = state.copyWith(
        profile: userData,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'فشل في تحميل بيانات المستخدم',
      );
    }
  }

  void updateProfile(Map<String, dynamic> updates) {
    if (state.profile != null) {
      final updatedProfile = {...state.profile!, ...updates};
      state = state.copyWith(profile: updatedProfile);
    }
  }
}
