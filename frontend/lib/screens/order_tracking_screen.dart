import 'customer_order_complaint_screen.dart';
import '../utils/readable_colors.dart';
import 'order_rating_screen.dart';
import 'customer_cash_review_screen.dart';
import '../services/customer_cash_review_service.dart';
import 'package:intl/intl.dart' show NumberFormat;
import '../services/live_activity_service.dart';
import '../widgets/order_arrival_card.dart';
// lib/screens/order_tracking_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../models/order_model.dart';
import '../services/order_service_v2.dart';
import '../services/websocket_service.dart';
import '../services/order_cancellation_service.dart';
import '../widgets/connection_status_widget.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String orderNumber;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final OrderServiceV2 _orderService = OrderServiceV2();
  final WebSocketService _wsService = WebSocketService();
  final OrderCancellationService _cancellationService =
      OrderCancellationService();

  String _money(num value) =>
      '${NumberFormat('#,##0.###', 'en').format(value)} د.ع';

  OrderModel? _order;
  bool _isLoading = true;
  String? _error;
  Timer? _pollingTimer;
  bool _refreshingOrder = false;
  bool _isForeground = true;
  StreamSubscription<OrderModel>? _orderUpdates;
  StreamSubscription<bool>? _connectionUpdates;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  VoidCallback? _wsListener;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    WidgetsBinding.instance.addObserver(this);

    // Listen to WebSocket connection status changes
    _wsListener = () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              // Update UI when WebSocket status changes
            });
          }
        });
      }
    };
    _wsService.addListener(_wsListener!);

    // 🚀 FIX: الاستماع لتحديثات OrderServiceV2 لضمان التزامن مع شاشة الطلبات
    _orderService.addListener(_onOrderServiceUpdated);

    // 🚀 FIX: تأخير _initializeOrderTracking() لتجنب setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeOrderTracking();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollingTimer?.cancel();
    _orderUpdates?.cancel();
    _connectionUpdates?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_wsListener != null) {
      _wsService.removeListener(_wsListener!);
    }

    // إزالة listener من OrderServiceV2
    _orderService.removeListener(_onOrderServiceUpdated);

    // لا نقطع اتصال WebSocket هنا لأنه مُشارك على مستوى التطبيق
    // WebSocket يجب أن يبقى متصلاً للحصول على تحديثات مباشرة في شاشات أخرى
    // _wsService.disconnect(); // تم إزالة هذا السطر
    super.dispose();
  }

  // دالة للاستجابة لتحديثات OrderServiceV2
  void _onOrderServiceUpdated() {
    if (!mounted) return;

    debugPrint('OrderTracking: 🔔 تحديث من OrderServiceV2');

    // البحث عن الطلب المحدث في قائمة OrderServiceV2
    if (_orderService.orders.isEmpty) return;
    final updatedOrder = _orderService.orders.firstWhere(
      (order) => order.id == widget.orderId,
      orElse: () => _orderService.orders.first,
    );

    // إذا وجد طلب محدث، حديث الطلب المحلي
    if (updatedOrder.id == widget.orderId && updatedOrder != _order) {
      debugPrint('OrderTracking: 📝 تحديث الطلب المحلي من OrderServiceV2');
      debugPrint(
        '   - الحالة القديمة: ${_order?.status.arabicName ?? 'غير محددة'}',
      );
      debugPrint('   - الحالة الجديدة: ${updatedOrder.status.arabicName}');

      // 🚀 FIX: تأخير setState() لتجنب خطأ "setState during build"
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _order = updatedOrder;
          });
          debugPrint(
            'OrderTracking: ✅ تم تحديث الطلب المحلي بعد انتهاء البناء',
          );
        }
      });
    }
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  Future<void> _initializeOrderTracking() async {
    try {
      // Load initial order data first with enhanced error handling
      debugPrint('OrderTracking: Attempting to load order ${widget.orderId}');

      if (widget.orderId.isEmpty) {
        debugPrint('OrderTracking: Empty order ID provided');
        setState(() {
          _error = 'معرف الطلب مفقود';
          _isLoading = false;
        });
        return;
      }

      final order = await _orderService.getOrderDetails(widget.orderId);

      debugPrint(
        'OrderTracking: Order data received: ${order != null ? "SUCCESS" : "NULL"}',
      );

      if (order != null) {
        if (!LiveActivityService.isTerminal(order.status))
          unawaited(LiveActivityService.startForOrder(order));
        debugPrint(
          'OrderTracking: Order loaded successfully - ${order.orderNumber}',
        );
        debugPrint('OrderTracking: Order status: ${order.status.arabicName}');
        debugPrint('OrderTracking: Order total: ${order.total}');
        debugPrint('OrderTracking: Order items count: ${order.items.length}');

        setState(() {
          _order = order;
          _isLoading = false;
        });

        // 🚀 FIX: إضافة/تحديث الطلب في OrderServiceV2 لضمان التزامن
        debugPrint('OrderTracking: 📝 إضافة/تحديث الطلب في OrderServiceV2...');
        final existingOrder = _orderService.orders.firstWhere(
          (o) => o.id == order.id,
          orElse: () => order,
        );

        if (existingOrder.id != order.id) {
          // الطلب غير موجود، أضفه
          debugPrint('OrderTracking: ➕ إضافة طلب جديد إلى OrderServiceV2');
          _orderService.addOrderToLocal(order);
        } else {
          // الطلب موجود، حدثه
          debugPrint('OrderTracking: 🔄 تحديث الطلب الموجود في OrderServiceV2');
          _orderService.updateOrderInList(order);
        }

        // ✅ CORRECT: استخدام connectForOrder مع معرف الطلب
        try {
          if (!_wsService.isConnected && !_wsService.isConnecting) {
            debugPrint(
              'OrderTracking: 🚀 بدء اتصال WebSocket للطلب ${widget.orderId}',
            );
            // ✅ استخدام الطريقة الصحيحة: connectForOrder
            await _wsService.connectForOrder(widget.orderId);
            // Wait a moment for connection to establish
            await Future.delayed(Duration(seconds: 1));
          } else if (_wsService.isConnecting) {
            debugPrint('OrderTracking: WebSocket اتصال قيد التقدم، انتظار...');
            // انتظار قصير للاتصال الجاري
            await Future.delayed(Duration(seconds: 2));
          } else {
            debugPrint(
              'OrderTracking: WebSocket متصل بالفعل، اشتراك مباشر في التحديثات',
            );
          } // 🔧 FIX: Enhanced WebSocket subscription for real-time order updates
          if (_wsService.isConnected) {
            debugPrint(
              'OrderTracking: WebSocket connected, subscribing to order updates for ${widget.orderId}',
            );

            // Subscribe to order-specific updates with proper stream management
            debugPrint(
              'OrderTracking: 🔔 بدء الاشتراك في تحديثات الطلب ${widget.orderId}...',
            );
            final orderStream = _wsService.subscribeToOrder(widget.orderId);
            debugPrint(
              'OrderTracking: 📡 تم إنشاء stream تحديثات الطلب ${widget.orderId}',
            );

            // 🔧 ENHANCED: Listen to WebSocket message processing globally
            debugPrint('OrderTracking: 🎧 بدء الاستماع لتحديثات WebSocket...');
            _orderUpdates = orderStream.listen(
              (updatedOrder) {
                debugPrint(
                  'OrderTracking: 🎉 🔄 استلام تحديث WebSocket للطلب ${updatedOrder.id}',
                );
                debugPrint(
                  'OrderTracking: الحالة الجديدة: ${updatedOrder.status.arabicName}',
                );
                debugPrint(
                  'OrderTracking: الحالة الحالية: ${_order?.status.arabicName ?? 'غير محددة'}',
                );
                debugPrint(
                  'OrderTracking: معرف الطلب الحالي: ${widget.orderId}',
                );
                debugPrint(
                  'OrderTracking: معرف الطلب المحدث: ${updatedOrder.id}',
                );

                if (mounted) {
                  final bool statusChanged =
                      _order?.status != updatedOrder.status;
                  debugPrint('OrderTracking: هل تغيرت الحالة؟ $statusChanged');

                  // 🚀 FIX: استخدم OrderServiceV2 للتحديث لضمان التزامن مع شاشة الطلبات
                  debugPrint(
                    'OrderTracking: 🔄 تحديث الطلب في OrderServiceV2...',
                  );
                  _orderService.updateOrderInList(updatedOrder);

                  // تحديث الطلب المحلي أيضاً
                  setState(() {
                    _order = updatedOrder;
                    debugPrint(
                      'OrderTracking: ✅ تم تحديث الطلب محلياً وفي OrderServiceV2',
                    );
                  });

                  // Show status change notification if status actually changed
                  if (statusChanged) {
                    debugPrint('OrderTracking: 🔔 عرض إشعار تغيير الحالة');
                    _showStatusUpdate(updatedOrder.status);
                  } else {
                    debugPrint(
                      'OrderTracking: الحالة لم تتغير، لكن تم تحديث البيانات الأخرى',
                    );
                  }
                } else {
                  debugPrint(
                    'OrderTracking: ⚠️ الشاشة غير مفعلة - تجاهل التحديث',
                  );
                }
              },
              onError: (error) {
                debugPrint('OrderTracking: ❌ خطأ في اشتراك WebSocket: $error');
                // Fallback to periodic polling if WebSocket fails
                _startPollingFallback();
              },
              onDone: () {
                debugPrint(
                  'OrderTracking: 🔚 انتهى stream تحديثات الطلب ${widget.orderId}',
                );
              },
            );

            // 🔧 FIX: Add additional debugging to verify WebSocket service receives messages
            debugPrint('OrderTracking: 📊 معلومات WebSocket Service:');
            debugPrint('  - isConnected: ${_wsService.isConnected}');
            debugPrint('  - تم إنشاء اشتراك للطلب: ${widget.orderId}');

            // Also subscribe to general order updates that might not be order-specific
            _connectionUpdates = _wsService.connectionStream.listen((
              isConnected,
            ) {
              debugPrint(
                'OrderTracking: WebSocket connection status changed: $isConnected',
              );
              if (!isConnected && mounted) {
                // If connection is lost, start polling as backup
                _startPollingFallback();
              }
            });
          } else {
            debugPrint(
              'OrderTracking: WebSocket connection failed, using polling fallback',
            );
            // If WebSocket connection failed, use polling fallback immediately
            _startPollingFallback();
          }
        } catch (e) {
          debugPrint('WebSocket connection failed: $e');
          // Use polling fallback if WebSocket fails
          _startPollingFallback();
        }

        // 🔧 FIX: Always start polling as additional backup
        // This ensures UI updates even if WebSocket messages are not received properly
        debugPrint('OrderTracking: 🚀 بدء polling إضافي كنسخة احتياطية');
        _startPollingFallback();
      } else {
        debugPrint('OrderTracking: Order not found - ${widget.orderId}');
        final errorMessage = _orderService.error ?? 'لم يتم العثور على الطلب';
        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('OrderTracking: Error loading order: $e');
      setState(() {
        _error = 'خطأ في تحميل بيانات الطلب: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      _startPollingFallback();
      unawaited(_refreshOrder());
    } else {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  // A connected socket does not prove that every status event was delivered.
  void _startPollingFallback() {
    if (!_isForeground || _pollingTimer?.isActive == true) return;
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshOrder());
    });
  }

  Future<void> _refreshOrder() async {
    if (!mounted || !_isForeground || _isLoading || _refreshingOrder) return;
    if (_order != null && LiveActivityService.isTerminal(_order!.status)) {
      _pollingTimer?.cancel();
      return;
    }
    _refreshingOrder = true;
    try {
      final updated = await _orderService.getOrderDetails(widget.orderId);
      if (!mounted || updated == null) return;
      final changed = _order?.status != updated.status;
      setState(() => _order = updated);
      if (changed) _showStatusUpdate(updated.status);
    } finally {
      _refreshingOrder = false;
    }
  }

  void _showStatusUpdate(OrderStatus status) {
    String message = '';
    switch (status) {
      case OrderStatus.confirmed:
        message = 'تم تأكيد طلبك من المطعم! 🎉';
        break;
      case OrderStatus.preparing:
        message = 'يتم تحضير طلبك الآن في المطعم 👨‍🍳';
        break;
      case OrderStatus.ready:
        message = 'طلبك جاهز وسيتم شحنه قريباً! 📦';
        break;
      case OrderStatus.reassigning:
        message = 'جارٍ البحث عن سائق بديل... 🔄';
        break;
      case OrderStatus.onTheWay:
        message = 'سائق التوصيل في الطريق إليك! 🚗';
        break;
      case OrderStatus.delivered:
        message = 'تم توصيل طلبك بنجاح! ✅';
        break;
      case OrderStatus.cancelled:
        message = 'تم إلغاء الطلب 📋';
        break;
      case OrderStatus.failed:
        message = 'عذراً، حدث خطأ في معالجة طلبك ⚠️';
        break;
      case OrderStatus.expired:
        message = 'عذراً، لم يتم تأكيد الطلب من المطعم في الوقت المحدد ⏰';
        break;
      case OrderStatus.rejected:
        message = 'عذراً، رفض المطعم تأكيد طلبك 🏪';
        break;
      default:
        return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            status == OrderStatus.delivered
                ? Colors.green
                : status == OrderStatus.cancelled ||
                    status == OrderStatus.failed ||
                    status == OrderStatus.expired ||
                    status == OrderStatus.rejected
                ? Colors.red
                : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Helper method to build address details string
  String _buildAddressDetails() {
    final List<String> details = [];

    if (_order!.deliveryAddress.buildingNumber?.isNotEmpty == true) {
      details.add('مبنى ${_order!.deliveryAddress.buildingNumber}');
    }

    if (_order!.deliveryAddress.floorNumber?.isNotEmpty == true) {
      details.add('الطابق ${_order!.deliveryAddress.floorNumber}');
    }

    if (_order!.deliveryAddress.apartmentNumber?.isNotEmpty == true) {
      details.add('شقة ${_order!.deliveryAddress.apartmentNumber}');
    }

    return details.isNotEmpty
        ? details.join(' - ')
        : 'تفاصيل إضافية غير متوفرة';
  }

  // Helper method to make phone calls
  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'لا يمكن إجراء المكالمة. تأكد من توفر تطبيق الهاتف.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error making phone call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء محاولة الاتصال'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: Text('تتبع الطلب #${widget.orderNumber}'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              tooltip: 'مراجعة النقد ورد المبلغ',
              icon: const Icon(Icons.payments_outlined),
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => CustomerCashReviewScreen(
                            call:
                                (body) => CustomerCashReviewService().call(
                                  widget.orderId,
                                  body,
                                ),
                          ),
                    ),
                  ),
            ),
            // Connection Status Icon with built-in tap functionality
            ConnectionStatusIcon(),
            const SizedBox(width: 16),
          ],
        ),
        body:
            _isLoading
                ? _buildLoadingState()
                : _error != null
                ? _buildErrorState()
                : _buildTrackingContent(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          SizedBox(height: 16),
          Text(
            'جاري تحميل بيانات الطلب...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _initializeOrderTracking();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.secondary,
            ),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingContent() {
    if (_order == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connection Status Bar
          ConnectionStatusWidget(showDetailed: false),
          const SizedBox(height: 16),
          OrderArrivalCard(order: _order!),
          const SizedBox(height: 16),
          _buildOrderHeader(),
          if (_order?.driverSearchUnavailable == true)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'تعذر العثور على سائق حاليًا. طلبك ما زال قائمًا ويحتاج متابعة من المنصة.',
              ),
            ),
          // إخفاء قسم تتبع الطلب عندما يكون الطلب ملغياً
          if (_order!.status != OrderStatus.cancelled &&
              _order!.status != OrderStatus.rejected &&
              _order!.status != OrderStatus.expired &&
              _order!.status != OrderStatus.failed) ...[
            const SizedBox(height: 24),
            ExpansionTile(
              title: const Text('مراحل الطلب'),
              children: [_buildStatusTimeline()],
            ),
          ],
          // Driver Info Card - Show when driver is assigned
          if (_shouldShowDriverInfo) ...[
            const SizedBox(height: 24),
            _buildDriverInfoCard(),
          ],
          const SizedBox(height: 24),
          _buildDeliveryInfo(),
          const SizedBox(height: 24),
          _buildOrderItems(),
          // Cancel Order Button - Show for orders that can be cancelled
          if (_order!.canBeCancelled) ...[
            const SizedBox(height: 24),
            _buildCancelOrderSection(),
          ],
          if (_order!.status == OrderStatus.onTheWay) ...[
            const SizedBox(height: 24),
            _buildDeliveryTracking(),
          ],
          if (_order!.status == OrderStatus.delivered) ...[
            const SizedBox(height: 24),
            _buildDeliveredActions(),
          ],
        ],
      ),
    );
  }

  Widget _buildOrderHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _getStatusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  _getStatusIcon(),
                  color: _getStatusColor(),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طلب #${_order!.orderNumber}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getStatusText(),
                      style: TextStyle(
                        fontSize: 14,
                        color: _getStatusColor(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(_order!.createdAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    // Special message for rejected or expired orders
                    if (_order!.status == OrderStatus.rejected) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'طلبك تم رفضه من قبل المطعم',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ] else if (_order!.status == OrderStatus.expired) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'المطعم لم يؤكد طلبك في الوقت المحدد',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ] else if (_order!.status == OrderStatus.cancelled &&
                        _order!.cancelReason != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تم إلغاء الطلب',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Colors.red[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'السبب: ${_order!.cancelReason}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Check if driver info should be shown
  bool get _shouldShowDriverInfo {
    if (_order == null) return false;

    // Show driver info when status is assigned or later (accepted, headingToStore, etc.)
    final driverStatuses = [
      OrderStatus.assigned,
      OrderStatus.accepted,
      OrderStatus.headingToStore,
      OrderStatus.arrivedAtStore,
      OrderStatus.pickedUp,
      OrderStatus.headingToCustomer,
      OrderStatus.arrivedAtCustomer,
    ];

    final hasDriverInfo =
        _order!.driverName != null || _order!.vehicleType != null;
    final shouldShow = driverStatuses.contains(_order!.status) && hasDriverInfo;

    debugPrint('🚗 _shouldShowDriverInfo check:');
    debugPrint('   - Order status: ${_order!.status.arabicName}');
    debugPrint('   - driverId: ${_order!.driverId}');
    debugPrint('   - driverName: ${_order!.driverName}');
    debugPrint('   - vehicleType: ${_order!.vehicleType}');
    debugPrint('   - vehiclePlate: ${_order!.vehiclePlate}');
    debugPrint('   - hasDriverInfo: $hasDriverInfo');
    debugPrint('   - shouldShow: $shouldShow');

    return shouldShow;
  }

  /// Build driver info card
  Widget _buildDriverInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delivery_dining,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'معلومات السائق',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Driver name
          if (_order!.driverName != null) ...[
            _buildDriverInfoRow(
              icon: Icons.person,
              label: 'اسم السائق',
              value: _order!.driverName!,
            ),
            const SizedBox(height: 12),
          ],
          // Vehicle type
          if (_order!.vehicleType != null) ...[
            _buildDriverInfoRow(
              icon: Icons.directions_car,
              label: 'نوع المركبة',
              value: _order!.vehicleType!,
            ),
            if (_order!.vehiclePlate != null) const SizedBox(height: 12),
          ],
          // Vehicle plate
          if (_order!.vehiclePlate != null) ...[
            _buildDriverInfoRow(
              icon: Icons.confirmation_number,
              label: 'رقم اللوحة',
              value: _order!.vehiclePlate!,
            ),
          ],
        ],
      ),
    );
  }

  /// Build driver info row widget
  Widget _buildDriverInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusTimeline() {
    // Timeline كامل يشمل جميع المراحل المهمة للمستخدم
    final statuses = [
      OrderStatus.pending, // 1. تم استلام الطلب
      OrderStatus.confirmed, // 2. تأكيد الطلب
      OrderStatus.preparing, // 3. يتم التحضير
      OrderStatus.readyForPickup, // 4. جاهز للاستلام
      OrderStatus.accepted, // 5. تم تعيين سائق (assigned → accepted)
      OrderStatus.headingToStore, // 6. السائق في الطريق للمطعم
      OrderStatus.arrivedAtStore, // 7. السائق وصل للمطعم
      OrderStatus.pickedUp, // 8. تم استلام الطلب من المطعم
      OrderStatus.headingToCustomer, // 9. السائق في الطريق للتوصيل
      OrderStatus.arrivedAtCustomer, // 10. السائق وصل للعميل
      OrderStatus.delivered, // 11. تم التوصيل
    ];

    // معالجة الحالات القديمة: تحويل ready → readyForPickup و onTheWay → headingToCustomer
    OrderStatus currentStatus = _order!.status;
    if (currentStatus == OrderStatus.ready) {
      currentStatus = OrderStatus.readyForPickup;
      debugPrint('⚠️ Timeline: Converting legacy "ready" to "readyForPickup"');
    }
    if (currentStatus == OrderStatus.onTheWay) {
      currentStatus = OrderStatus.headingToCustomer;
      debugPrint(
        '⚠️ Timeline: Converting legacy "onTheWay" to "headingToCustomer"',
      );
    }

    // التعامل مع حالة 'assigned' - نعرضها كـ 'accepted'
    // Backend/Driver يرسل 'assigned' عند تعيين سائق للطلب
    if (currentStatus == OrderStatus.assigned) {
      currentStatus = OrderStatus.accepted;
      debugPrint(
        '⚠️ Timeline: Converting "assigned" to "accepted" for timeline display',
      );
    }

    // 🚀 FIX: التعامل مع حالة 'reassigning' - عند إلغاء السائق، نعرضها كـ 'readyForPickup'
    // لأن الطلب عاد لمرحلة البحث عن سائق جديد
    if (currentStatus == OrderStatus.reassigning) {
      currentStatus = OrderStatus.readyForPickup;
      debugPrint(
        '⚠️ Timeline: Converting "reassigning" to "readyForPickup" for timeline display',
      );
    }

    final currentIndex = statuses.indexOf(currentStatus);

    // إذا لم يتم العثور على الحالة في القائمة، استخدم موقع افتراضي بدلاً من -1
    final effectiveIndex = currentIndex >= 0 ? currentIndex : 0;

    debugPrint(
      '📊 Timeline: Current status = ${_order!.status}, Converted = $currentStatus, Index = $currentIndex, Effective = $effectiveIndex',
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تتبع الطلب',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          Column(
            children: List.generate(statuses.length, (index) {
              final status = statuses[index];
              final isCompleted =
                  index <=
                  effectiveIndex; // استخدام effectiveIndex بدلاً من currentIndex
              final isActive = index == effectiveIndex;

              return _buildTimelineItem(
                status: status,
                isCompleted: isCompleted,
                isActive: isActive,
                isLast: index == statuses.length - 1,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required OrderStatus status,
    required bool isCompleted,
    required bool isActive,
    required bool isLast,
  }) {
    return Row(
      children: [
        Column(
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: isActive ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isCompleted ? AppColors.primary : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isActive
                                ? AppColors.primary
                                : isCompleted
                                ? AppColors.primary
                                : Colors.grey[300]!,
                        width: 2,
                      ),
                    ),
                    child:
                        isCompleted
                            ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                            : null,
                  ),
                );
              },
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted ? AppColors.primary : Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusDisplayText(status),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    color: isCompleted ? Colors.black87 : Colors.grey[500],
                  ),
                ),
                if (isActive && status == OrderStatus.preparing)
                  Text(
                    'الوقت المتوقع: 15-20 دقيقة',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                if (isActive && status == OrderStatus.onTheWay)
                  Text(
                    'الوقت المتوقع: 10-15 دقيقة',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with delivery icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'معلومات التوصيل',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Delivery Address Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'عنوان التوصيل',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _order!.deliveryAddress.fullAddress,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),

                // Additional address details if available
                if (_order!.deliveryAddress.buildingNumber?.isNotEmpty ==
                        true ||
                    _order!.deliveryAddress.floorNumber?.isNotEmpty == true ||
                    _order!.deliveryAddress.apartmentNumber?.isNotEmpty ==
                        true) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.apartment, color: Colors.grey, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildAddressDetails(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Customer Contact Info
          if (_order!.customerPhone?.isNotEmpty == true ||
              _order!.customerName?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'معلومات الاتصال',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_order!.customerName?.isNotEmpty == true) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.account_circle_outlined,
                          color: Colors.grey[600],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _order!.customerName!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (_order!.customerPhone?.isNotEmpty == true) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          color: Colors.grey[600],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _order!.customerPhone!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _makePhoneCall(_order!.customerPhone!),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.call,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Restaurant Info
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'المطعم',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _order!.storeName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Delivery Instructions
          if (_order!.deliveryInstructions?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    color: Colors.amber[700],
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ملاحظات التوصيل',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _order!.deliveryInstructions!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Payment Method
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(
                  _order!.paymentMethod == PaymentMethod.cash
                      ? Icons.payments_outlined
                      : Icons.credit_card_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'طريقة الدفع',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _order!.paymentMethod.arabicName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _order!.paymentMethod == PaymentMethod.cash
                            ? Colors.green[100]
                            : Colors.blue[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _order!.paymentMethod == PaymentMethod.cash
                        ? 'نقدي'
                        : 'إلكتروني',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color:
                          _order!.paymentMethod == PaymentMethod.cash
                              ? Colors.green[700]
                              : Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItems() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'تفاصيل الطلب',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_order!.items.length} عنصر',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Order Items List
          ...List.generate(_order!.items.length, (index) {
            final item = _order!.items[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.restaurant_menu,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.dishName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              _money(item.unitPrice * item.quantity),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'الكمية: ${item.quantity}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_money(item.unitPrice)} للوحدة',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Item customizations if available
                  if (item.selectedOptions?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tune,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'التخصيصات:',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...item.selectedOptions!.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${entry.key}: ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      entry.value.join(', '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ],

                  // Special instructions if available
                  if (item.specialInstructions?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.note_outlined,
                            size: 16,
                            color: Colors.amber[700],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.specialInstructions!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber[800],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

          // Order Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  'المجموع الفرعي',
                  '${_money(_order!.subtotal)}',
                ),
                if (_order!.deliveryFee > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'رسوم التوصيل',
                    '${_money(_order!.deliveryFee)}',
                  ),
                ],
                if (_order!.serviceFee > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow('رسوم الخدمة', _money(_order!.serviceFee)),
                ],
                if (_order!.tip > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow('إكرامية السائق', _money(_order!.tip)),
                ],
                if (_order!.tax > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow('الضريبة', '${_money(_order!.tax)}'),
                ],
                if (_order!.discount > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'الخصم',
                    '-${_money(_order!.discount)}',
                    valueColor: Colors.green,
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'المجموع الكلي',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${_money(_order!.total)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryTracking() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Icon(
                  Icons.delivery_dining,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سائق التوصيل في الطريق',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'سيصل خلال 10-15 دقيقة',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement call driver functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'ميزة الاتصال بالسائق ستكون متاحة قريباً',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.phone),
                  label: const Text('اتصال بالسائق'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: Implement live tracking map
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ميزة التتبع المباشر ستكون متاحة قريباً'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('تتبع مباشر'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCancelOrderSection() {
    if (_order?.cancellationStatus == 'REQUESTED') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'طلب الإلغاء قيد المراجعة. يستمر الطلب حتى تأكيد الإلغاء.\nمرجع القضية: ${_order?.cancellationCaseId ?? ""}',
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.cancel_outlined,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'إلغاء الطلب',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'قبل قبول المطعم يمكن الإلغاء دون رسوم. بعد القبول أو بدء التجهيز يُرسل طلب للمراجعة ويستمر الطلب حتى تأكيد الإلغاء.',
            style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showCancelDialog(),
              icon: const Icon(Icons.cancel, size: 18),
              label: const Text('إلغاء الطلب'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController reasonController = TextEditingController();
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إلغاء الطلب'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'هل تريد إرسال طلب الإلغاء؟ إذا لم يقبل المطعم الطلب بعد، يُلغى دون رسوم. بعد القبول يحتاج الإلغاء إلى تأكيد، ولا يتوقف الطلب بمجرد إرسال الطلب.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Text(
                  'سبب الإلغاء (اختياري):',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'مثال: تغيير الرأي، لا أحتاج الطلب الآن...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('العودة'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  final reason = reasonController.text.trim();
                  _cancelOrder(
                    reason.isEmpty ? 'Order cancelled by user' : reason,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: readableForeground(Colors.red),
                ),
                child: const Text('تأكيد طلب الإلغاء'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelOrder(String reason) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('جاري إلغاء الطلب...'),
                ],
              ),
            ),
          );
        },
      );

      // Cancel the order using OrderCancellationService
      final result = await _cancellationService.cancelOrder(
        widget.orderId,
        reason.isNotEmpty ? reason : 'Order cancelled by user',
      );

      // Close loading dialog
      Navigator.of(context).pop();

      if (result.success && !result.cancelled) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
        _initializeOrderTracking();
        return;
      }
      if (result.success) {
        // Show success message and close tracking screen after 1.5 seconds
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء الطلب بنجاح ✅'),
            backgroundColor: Colors.green,
            duration: Duration(milliseconds: 1500),
          ),
        );

        // 🔧 NEW: Close order tracking screen immediately after successful cancellation
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            // Close the tracking screen and go back to orders list or home
            Navigator.of(context).pop();

            // Show a brief message about the order being moved to cancelled section
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم نقل الطلب إلى قسم الطلبات الملغاة 📋'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            });
          }
        });

        // Also refresh order data in the background to ensure consistency
        _initializeOrderTracking();
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إلغاء الطلب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildDeliveredActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CustomerOrderComplaintScreen(
                  orderId: widget.orderId,
                ),
              ),
            ),
            icon: const Icon(Icons.support_agent, color: Color(0xFF00296B)),
            label: const Text(
              'مساعدة أو شكوى بخصوص الطلب',
              style: TextStyle(color: Color(0xFF00296B)),
            ),
          ),
          const SizedBox(height:16),
          const Icon(Icons.check_circle, color: Colors.green, size: 60),
          const SizedBox(height: 16),
          const Text(
            'تم توصيل طلبك بنجاح! 🎉',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'نشكرك لاختيارك تطبيق زاد',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => OrderRatingScreen(orderId: widget.orderId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.star),
                  label: const Text('تقييم الطلب'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Navigate back to home
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('العودة للرئيسية'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (_order!.status) {
      case OrderStatus.returning:
      case OrderStatus.returnArrived:
        return Colors.orange;
      case OrderStatus.returned:
        return Colors.blueGrey;
      case OrderStatus.pending:
        return AppColors.primary;
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
      case OrderStatus.ready:
      case OrderStatus.readyForPickup:
      case OrderStatus.reassigning:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.headingToStore:
      case OrderStatus.arrivedAtStore:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
      case OrderStatus.headingToCustomer:
      case OrderStatus.arrivedAtCustomer:
        return AppColors.primary;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
      case OrderStatus.failed:
      case OrderStatus.expired:
      case OrderStatus.rejected:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (_order!.status) {
      case OrderStatus.returning:
        return Icons.assignment_return;
      case OrderStatus.returnArrived:
        return Icons.store;
      case OrderStatus.returned:
        return Icons.assignment_turned_in;
      case OrderStatus.pending:
        return Icons.schedule;
      case OrderStatus.confirmed:
        return Icons.check_circle;
      case OrderStatus.preparing:
        return Icons.restaurant;
      case OrderStatus.ready:
      case OrderStatus.readyForPickup:
        return Icons.done_all;
      case OrderStatus.reassigning:
        return Icons.search;
      case OrderStatus.assigned:
      case OrderStatus.accepted:
        return Icons.check_circle_outline;
      case OrderStatus.headingToStore:
        return Icons.directions_car;
      case OrderStatus.arrivedAtStore:
        return Icons.store;
      case OrderStatus.pickedUp:
        return Icons.shopping_bag;
      case OrderStatus.onTheWay:
      case OrderStatus.headingToCustomer:
        return Icons.delivery_dining;
      case OrderStatus.arrivedAtCustomer:
        return Icons.location_on;
      case OrderStatus.delivered:
        return Icons.check_circle;
      case OrderStatus.cancelled:
        return Icons.cancel;
      case OrderStatus.failed:
        return Icons.error;
      case OrderStatus.expired:
        return Icons.schedule_outlined;
      case OrderStatus.rejected:
        return Icons.block;
    }
  }

  String _getStatusText() {
    if (_order!.driverSearchUnavailable)
      return 'تعذر العثور على سائق؛ الطلب بانتظار متابعة المنصة';
    if (_order!.driverReplacementSearch) return 'الطلب جاهز؛ نبحث عن سائق بديل';
    switch (_order!.status) {
      case OrderStatus.returning:
        return _order?.returnStatus == 'REQUESTED'
            ? 'تعذر التسليم؛ نراجع معالجة طلبك'
            : 'السائق يعيد الطلب للمطعم';
      case OrderStatus.returnArrived:
        return 'بانتظار تأكيد استلام المطعم';
      case OrderStatus.returned:
        return 'تم إرجاع الطلب للمطعم';
      case OrderStatus.pending:
        return 'في انتظار تأكيد المطعم';
      case OrderStatus.confirmed:
        return 'تم تأكيد الطلب من المطعم';
      case OrderStatus.preparing:
        return 'يتم تحضير الطلب';
      case OrderStatus.ready:
      case OrderStatus.readyForPickup:
        return 'الطلب جاهز للشحن';
      case OrderStatus.reassigning:
        return 'جاري البحث عن سائق بديل...';
      case OrderStatus.assigned:
        return 'تم تعيين سائق';
      case OrderStatus.accepted:
        return 'تم قبول الطلب من السائق';
      case OrderStatus.headingToStore:
        return 'السائق في الطريق للمطعم';
      case OrderStatus.arrivedAtStore:
        return 'السائق وصل للمطعم';
      case OrderStatus.pickedUp:
        return 'تم استلام الطلب من المطعم';
      case OrderStatus.onTheWay:
      case OrderStatus.headingToCustomer:
        return 'في الطريق إليك';
      case OrderStatus.arrivedAtCustomer:
        return 'السائق وصل إليك';
      case OrderStatus.delivered:
        return 'تم التوصيل بنجاح';
      case OrderStatus.cancelled:
        return 'تم إلغاء الطلب';
      case OrderStatus.failed:
        return 'حدث خطأ في معالجة الطلب';
      case OrderStatus.expired:
        return 'عذراً، لم يتم تأكيد الطلب من المطعم';
      case OrderStatus.rejected:
        return 'عذراً، رفض المطعم تأكيد الطلب';
    }
  }

  String _getStatusDisplayText(OrderStatus status) {
    switch (status) {
      case OrderStatus.returning:
        return _order?.returnStatus == 'REQUESTED'
            ? 'تعذر التسليم؛ نراجع معالجة طلبك'
            : 'السائق يعيد الطلب للمطعم';
      case OrderStatus.returnArrived:
        return 'بانتظار تأكيد استلام المطعم';
      case OrderStatus.returned:
        return 'تم إرجاع الطلب للمطعم';
      case OrderStatus.pending:
        return 'تم استلام الطلب';
      case OrderStatus.confirmed:
        return 'تأكيد الطلب من المطعم';
      case OrderStatus.preparing:
        return 'تحضير الطلب في المطعم';
      case OrderStatus.ready:
      case OrderStatus.readyForPickup:
        return 'الطلب جاهز للشحن';
      case OrderStatus.reassigning:
        return 'البحث عن سائق بديل';
      case OrderStatus.assigned:
        return 'تعيين سائق';
      case OrderStatus.accepted:
        return 'قبول من السائق';
      case OrderStatus.headingToStore:
        return 'التوجه للمطعم';
      case OrderStatus.arrivedAtStore:
        return 'الوصول للمطعم';
      case OrderStatus.pickedUp:
        return 'استلام الطلب';
      case OrderStatus.onTheWay:
      case OrderStatus.headingToCustomer:
        return 'في الطريق للتوصيل';
      case OrderStatus.arrivedAtCustomer:
        return 'الوصول للعميل';
      case OrderStatus.delivered:
        return 'تم التوصيل بنجاح';
      case OrderStatus.cancelled:
        return 'تم إلغاء الطلب';
      case OrderStatus.failed:
        return 'حدث خطأ في المعالجة';
      case OrderStatus.expired:
        return 'انتهت مهلة التأكيد';
      case OrderStatus.rejected:
        return 'رفض المطعم الطلب';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'منذ لحظات';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
