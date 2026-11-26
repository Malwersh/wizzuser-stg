import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodapp_user/services/discovery_history.dart';
import 'package:foodapp_user/models/order_model.dart';

OrderModel order(
  String branch,
  String product, {
  String status = 'delivered',
  String at = '2026-10-30T00:00:00Z',
}) => OrderModel.fromJson({
  'storeId': branch,
  'status': status,
  'createdAt': at,
  'items': [
    {'productId': product, 'quantity': 1, 'price': 3000},
  ],
  'deliveryAddress': <String, dynamic>{},
});
void main() {
  test(
    'history uses the current authenticated account orders contract and keeps delivered only',
    () async {
      var requests = 0;
      final history = DiscoveryHistory(
        account: () => 'customer',
        tokenReader: () async => 'test-token',
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, endsWith('/users/customer/orders'));
          expect(request.url.queryParameters, {
            'status': 'completed',
            'historyDays': '30',
          });
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response(
            jsonEncode({
              'success': true,
              'orders': [
                {
                  'storeId': 'frouj',
                  'status': 'delivered',
                  'createdAt': '2026-11-02T10:00:00Z',
                  'items': [],
                  'deliveryAddress': {},
                },
                {
                  'storeId': 'cancelled',
                  'status': 'cancelled',
                  'createdAt': '2026-11-02T11:00:00Z',
                  'items': [],
                  'deliveryAddress': {},
                },
              ],
            }),
            200,
          );
        }),
      );
      await history.load();
      expect(history.pastStores, ['frouj']);
      await history.load();
      expect(requests, 1);
    },
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'completed orders and last order are isolated by account and exact branch',
    () async {
      var account = 'one';
      final h = DiscoveryHistory(
        account: () => account,
        loader:
            (_) async => [
              order('b', 'old'),
              order('b', 'new', at: '2026-10-31T00:00:00Z'),
              order('other', 'foreign'),
              order('b', 'cancelled', status: 'cancelled'),
            ],
      );
      await h.load();
      expect(h.products('b', last: true), ['new']);
      expect(h.products('b'), ['new', 'old']);
      account = 'two';
      expect(h.products('b'), isEmpty);
      expect(h.pastStores, isEmpty);
    },
  );
  test(
    'late response cannot cross account boundary and concurrent reads share request',
    () async {
      var account = 'one', calls = 0;
      final gate = Completer<List<OrderModel>>();
      final h = DiscoveryHistory(
        account: () => account,
        loader: (_) {
          calls++;
          return gate.future;
        },
      );
      final a = h.load(), b = h.load();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      account = 'two';
      gate.complete([order('private', 'p')]);
      await Future.wait([a, b]);
      expect(h.pastStores, isEmpty);
    },
  );
  test(
    'recent observations persist bounded and separately per user, without saved prices',
    () async {
      var account = 'one';
      final h = DiscoveryHistory(account: () => account);
      for (var i = 0; i < 45; i++) h.viewedStore('b$i');
      h.viewedProduct('b44', 'p');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.recentStores.length, 40);
      final restored = DiscoveryHistory(account: () => account);
      await restored.load();
      expect(restored.recentStores.first, 'b44');
      expect(restored.recentProducts('b44'), ['p']);
      account = 'guest';
      expect(restored.recentStores, isEmpty);
      expect(restored.recentProducts('b44'), isEmpty);
    },
  );
}
