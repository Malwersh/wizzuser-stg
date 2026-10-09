// lib/services/order_cancellation_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/order_service_v2.dart';
import '../services/websocket_service.dart';

/// خدمة متخصصة في معالجة إلغاء الطلبات وتحديث الواجهة فورياً
class OrderCancellationService extends ChangeNotifier {
  static final OrderCancellationService _instance = OrderCancellationService._internal();
  factory OrderCancellationService() => _instance;
  static OrderCancellationService get instance => _instance;
  OrderCancellationService._internal() {
    _setupWebSocketListener();
  }

  final OrderServiceV2 _orderService = OrderServiceV2();
  final WebSocketService _wsService = WebSocketService();
  
  StreamSubscription? _wsSubscription;
  final StreamController<OrderCancellationEvent> _cancellationController = 
      StreamController<OrderCancellationEvent>.broadcast();

  /// Stream للاستماع لأحداث إلغاء الطلبات
  Stream<OrderCancellationEvent> get cancellationStream => _cancellationController.stream;

  /// إعداد مستمع WebSocket للتحديثات الفورية
  void _setupWebSocketListener() {
    // الاستماع لتحديثات الاتصال
    _wsService.connectionStream.listen((isConnected) {
      if (isConnected) {
        debugPrint('OrderCancellationService: WebSocket متصل - جاهز لاستقبال إشعارات الإلغاء');
      }
    });
  }

  /// إلغاء طلب مع تحديث فوري للواجهة
  Future<OrderCancellationResult> cancelOrder(String orderId, String reason) async {
    try {
      debugPrint('OrderCancellationService: بدء إلغاء الطلب $orderId');
      
      // إلغاء الطلب عبر API
      final success = await _orderService.cancelOrder(orderId, reason);
      
      if (success) {
        // إرسال إشعار للواجهة
        final event = OrderCancellationEvent(
          orderId: orderId,
          reason: reason,
          timestamp: DateTime.now(),
          success: true,
        );
        
        _cancellationController.add(event);
        
        debugPrint('OrderCancellationService: تم إلغاء الطلب $orderId بنجاح');
        
        return OrderCancellationResult(
          success: true,
          orderId: orderId,
          message: 'تم إلغاء الطلب بنجاح',
        );
        
      } else {
        final error = _orderService.error ?? 'فشل في إلغاء الطلب';
        debugPrint('OrderCancellationService: فشل إلغاء الطلب $orderId: $error');
        
        return OrderCancellationResult(
          success: false,
          orderId: orderId,
          message: error,
        );
      }
      
    } catch (e) {
      debugPrint('OrderCancellationService: خطأ في إلغاء الطلب $orderId: $e');
      
      return OrderCancellationResult(
        success: false,
        orderId: orderId,
        message: 'خطأ في إلغاء الطلب: $e',
      );
    }
  }

  /// معالجة إشعار إلغاء من WebSocket
  void handleWebSocketCancellation(String orderId, Map<String, dynamic> orderData) {
    debugPrint('OrderCancellationService: معالجة إشعار إلغاء WebSocket للطلب $orderId');
    
    final event = OrderCancellationEvent(
      orderId: orderId,
      reason: orderData['cancelReason'] ?? 'تم إلغاء الطلب',
      timestamp: DateTime.now(),
      success: true,
      fromWebSocket: true,
    );
    
    _cancellationController.add(event);
    notifyListeners();
  }

  /// تنظيف الموارد
  @override
  void dispose() {
    _wsSubscription?.cancel();
    _cancellationController.close();
    super.dispose();
  }
}

/// نتيجة عملية إلغاء الطلب
class OrderCancellationResult {
  final bool success;
  final String orderId;
  final String message;
  
  const OrderCancellationResult({
    required this.success,
    required this.orderId,
    required this.message,
  });
}

/// حدث إلغاء طلب
class OrderCancellationEvent {
  final String orderId;
  final String reason;
  final DateTime timestamp;
  final bool success;
  final bool fromWebSocket;
  
  const OrderCancellationEvent({
    required this.orderId,
    required this.reason,
    required this.timestamp,
    required this.success,
    this.fromWebSocket = false,
  });
}
