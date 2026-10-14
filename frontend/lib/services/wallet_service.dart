import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wallet_model.dart';
import '../models/wallet_transaction_model.dart';
import '../config.dart';
import 'session_service.dart';

class WalletService {
  static const String baseUrl = ApiConfig.baseUrl;

  // Initialize wallet for new user
  static Future<Map<String, dynamic>> initializeWallet(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/wallet/init'),
        headers: {
          'Content-Type': 'application/json',
          if (SessionService().accessToken?.isNotEmpty == true)
            'Authorization': 'Bearer ${SessionService().accessToken}',
        },
        body: jsonEncode({'userId': userId}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
          'wallet':
              data['wallet'] != null
                  ? WalletModel.fromJson(data['wallet'])
                  : null,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل في إنشاء المحفظة',
        };
      }
    } catch (e) {
      print('WalletService.initializeWallet Error: $e');
      return {'success': false, 'message': 'خطأ في الشبكة: $e'};
    }
  }

  // Get wallet balance
  static Future<Map<String, dynamic>> getWalletBalance(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wallet/balance?userId=$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'balance': (data['balance'] ?? 0).toDouble(),
          'currency': data['currency'] ?? 'IQD',
          'isActive': data['isActive'] ?? true,
          'updatedAt': data['updatedAt'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل في الحصول على الرصيد',
        };
      }
    } catch (e) {
      print('WalletService.getWalletBalance Error: $e');
      return {'success': false, 'message': 'خطأ في الشبكة: $e'};
    }
  }

  // Request wallet top-up with enhanced retry mechanism and session timeout handling
  static Future<Map<String, dynamic>> requestTopUp({
    required String userId,
    required double amount,
    String currency = 'IQD',
    Map<String, String>? customerInfo,
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse('$baseUrl/wallet/topup'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'userId': userId,
                'amount': amount,
                'currency': currency,
                'sessionTimeout': 2700, // 45 minutes - match backend setting
                'customerInfo':
                    customerInfo ??
                    {
                      'name': 'مستخدم التطبيق',
                      'email': 'user@foodapp.com',
                      'phone': '+964xxxxxxxxx',
                      'city': 'بغداد',
                      'country': 'IQ',
                    },
              }),
            )
            .timeout(const Duration(seconds: 45)); // Increased timeout

        final data = jsonDecode(response.body);

        if (response.statusCode == 200) {
          // Validate payment URL
          String? paymentUrl = data['paymentUrl'] as String?;
          if (paymentUrl == null || paymentUrl.isEmpty) {
            throw Exception('رابط الدفع فارغ أو غير صحيح');
          }

          if (!paymentUrl.startsWith('http://') &&
              !paymentUrl.startsWith('https://')) {
            throw Exception('رابط الدفع غير صالح');
          }

          // Enhanced PayTabs environment logging
          if (paymentUrl.contains('secure-iraq.paytabs.com')) {
          } else if (paymentUrl.contains('sandbox-secure.paytabs.com')) {
          } else if (paymentUrl.contains('secure.paytabs.com')) {
            print('⚠️ Using PayTabs Production environment');
          } else {
            print('ℹ️ Unknown PayTabs environment: $paymentUrl');
          }

          return {
            'success': true,
            'message': data['message'] ?? 'تم إنشاء طلب الدفع بنجاح',
            'paymentUrl': paymentUrl,
            'transactionId': data['transactionId'],
            'reference': data['reference'],
            'amount': data['amount'],
            'currency': data['currency'],
            'sessionTimeout': data['sessionTimeout'] ?? 2700,
            'note': data['note'],
          };
        } else if (response.statusCode >= 500 && attempt < maxRetries) {
          // Server error, retry
          print('Server error on attempt $attempt, retrying...');
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'فشل في إنشاء طلب الدفع',
          };
        }
      } catch (e) {
        print('WalletService.requestTopUp Error (attempt $attempt): $e');

        if (attempt == maxRetries) {
          return {'success': false, 'message': 'خطأ في الشبكة: $e'};
        }

        // Wait before retry
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    return {
      'success': false,
      'message': 'فشل في الاتصال بعد $maxRetries محاولات',
    };
  }

  // Spend from wallet
  static Future<Map<String, dynamic>> spendFromWallet({
    required String userId,
    required double amount,
    String? orderId,
    String? description,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/wallet/spend'),
        headers: {
          'Content-Type': 'application/json',
          if (SessionService().accessToken?.isNotEmpty == true)
            'Authorization': 'Bearer ${SessionService().accessToken}',
        },
        body: jsonEncode({
          'userId': userId,
          'amount': amount,
          'orderId': orderId,
          'description': description,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'transactionId': data['transactionId'],
          'deductedAmount': data['deductedAmount'],
          'previousBalance': data['previousBalance'],
          'newBalance': data['newBalance'],
          'currency': data['currency'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل في خصم المبلغ',
          'currentBalance': data['currentBalance'],
          'requiredAmount': data['requiredAmount'],
        };
      }
    } catch (e) {
      print('WalletService.spendFromWallet Error: $e');
      return {'success': false, 'message': 'خطأ في الشبكة: $e'};
    }
  }

  // Get wallet transactions
  static Future<Map<String, dynamic>> getWalletTransactions({
    required String userId,
    int limit = 20,
    String? lastKey,
  }) async {
    try {
      String url = '$baseUrl/wallet/transactions?userId=$userId&limit=$limit';
      if (lastKey != null) {
        url += '&lastKey=${Uri.encodeComponent(lastKey)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> transactionsJson = data['transactions'] ?? [];
        final List<WalletTransactionModel> transactions =
            transactionsJson
                .map((json) => WalletTransactionModel.fromJson(json))
                .toList();

        return {
          'success': true,
          'transactions': transactions,
          'count': data['count'] ?? 0,
          'lastKey': data['lastEvaluatedKey'],
          'hasMore': data['hasMore'] ?? false,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل في الحصول على المعاملات',
        };
      }
    } catch (e) {
      print('WalletService.getWalletTransactions Error: $e');
      return {'success': false, 'message': 'خطأ في الشبكة: $e'};
    }
  }

  // Check if user has sufficient balance
  static Future<bool> hasSufficientBalance(String userId, double amount) async {
    final result = await getWalletBalance(userId);
    if (result['success']) {
      return result['balance'] >= amount;
    }
    return false;
  }

  // Format currency display
  static String formatCurrency(double amount, String currency) {
    if (currency == 'USD') {
      return '\$${amount.toStringAsFixed(2)}';
    } else if (currency == 'IQD') {
      return '${amount.toStringAsFixed(0)} د.ع';
    }
    return '${amount.toStringAsFixed(2)} $currency';
  }

  // Get predefined top-up amounts
  static List<double> getTopUpAmounts(String currency) {
    if (currency == 'USD') {
      return [5.0, 10.0, 20.0, 50.0, 100.0];
    } else if (currency == 'IQD') {
      return [5000.0, 10000.0, 25000.0, 50000.0, 100000.0];
    }
    return [10.0, 20.0, 50.0, 100.0, 200.0];
  }
}
