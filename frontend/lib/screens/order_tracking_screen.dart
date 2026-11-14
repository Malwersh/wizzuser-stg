import 'customer_support_chat_screen.dart';
import '../services/customer_support_chat.dart';
import 'dart:ui' show FontFeature;
import '../widgets/tracking_cancellation.dart';
import '../utils/iraqi_phone.dart';
import '../widgets/live_order_map.dart';
import '../widgets/tracking_progress_card.dart';
import 'customer_order_complaint_screen.dart';
import 'order_rating_screen.dart';
import 'customer_cash_review_screen.dart';
import '../services/customer_cash_review_service.dart';
import 'package:intl/intl.dart' show NumberFormat;
import '../services/live_activity_service.dart';
// lib/screens/order_tracking_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../models/order_model.dart';
import '../services/order_service_v2.dart';
import '../services/websocket_service.dart';
import '../services/order_cancellation_service.dart';

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
    with WidgetsBindingObserver {
  final OrderServiceV2 _orderService = OrderServiceV2();
  final WebSocketService _wsService = WebSocketService();
  final OrderCancellationService _cancellationService =
      OrderCancellationService();

  bool _openingSupport = false;

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
  VoidCallback? _wsListener;

  @override
  void initState() {
    super.initState();
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
      final Uri phoneUri = Uri(
        scheme: 'tel',
        path: IraqiPhone.display(phoneNumber),
      );
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
          title: const Text(
            'تتبع الطلب',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
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
    final order = _order;
    if (order == null) return const SizedBox.shrink();
    final terminal = LiveActivityService.isTerminal(order.status);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!terminal) ...[
            LiveOrderMap(key: ValueKey(order.id), order: order),
            const SizedBox(height: 14),
          ],
          if (order.status == OrderStatus.delivered)
            _buildDeliverySuccess()
          else
            TrackingProgressCard(order: order),
          if (order.driverSearchUnavailable)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'نبحث عن سائق متاح. طلبك ما زال قائمًا وتتابعه المنصة.',
              ),
            ),
          if (_shouldShowDriverInfo) ...[
            const SizedBox(height: 14),
            _buildCompactDriver(),
          ],
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: ExpansionTile(
              title: const Text(
                'تفاصيل الطلب',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryDark,
                ),
              ),
              iconColor: AppColors.secondaryDark,
              collapsedIconColor: AppColors.secondaryDark,
              subtitle: Text(
                '${order.storeName} • ${_money(order.total)}',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Color(0xff65728a),
                ),
              ),
              children: [_buildDeliveryInfo(), _buildOrderItems()],
            ),
          ),
          const SizedBox(height: 14),
          _buildSupportEntry(),
          if (order.canBeCancelled) ...[
            const SizedBox(height: 14),
            _buildCancelOrderSection(),
          ],
          if (order.status == OrderStatus.delivered) ...[
            const SizedBox(height: 14),
            _buildDeliveredActions(),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactDriver() {
    final o = _order!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFEEF2F8),
            child: Icon(Icons.delivery_dining, color: Color(0xFF00296B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.driverName ?? 'سائق التوصيل',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00296B),
                  ),
                ),
                if (_vehicleDescription(o).isNotEmpty)
                  Text(
                    _vehicleDescription(o),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF647184),
                    ),
                  ),
              ],
            ),
          ),
          if (o.driverPhone?.trim().isNotEmpty == true)
            IconButton(
              tooltip: 'الاتصال بالسائق',
              onPressed: () => _makePhoneCall(o.driverPhone!),
              icon: const Icon(Icons.call_outlined, color: Color(0xFF00296B)),
            ),
        ],
      ),
    );
  }

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
  Widget _buildDeliveryInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                  color: AppColors.secondaryDark.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.secondaryDark,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'معلومات التوصيل',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryDark,
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
                      color: AppColors.secondaryDark,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'عنوان التوصيل',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _order!.deliveryAddress.fullAddress,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.secondaryDark,
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
                        color: AppColors.secondaryDark,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'معلومات الاتصال',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryDark,
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
                            color: AppColors.secondaryDark,
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
                            IraqiPhone.display(_order!.customerPhone!),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.secondaryDark,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _makePhoneCall(_order!.customerPhone!),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryDark.withValues(
                                alpha: 0.06,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.call,
                              color: AppColors.secondaryDark,
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
                    color: AppColors.secondaryDark.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    color: AppColors.secondaryDark,
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
                          color: AppColors.secondaryDark,
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
                color: const Color(0xfff1f4fa),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffdfe6f0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    color: AppColors.secondaryDark,
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
                            color: AppColors.secondaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _order!.deliveryInstructions!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.secondaryDark,
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
                  color: AppColors.secondaryDark,
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
                          color: AppColors.secondaryDark,
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondaryDark.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.secondaryDark,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'تفاصيل الطلب',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryDark,
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
                          color: AppColors.secondaryDark.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.restaurant_menu,
                          color: AppColors.secondaryDark,
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
                                color: AppColors.secondaryDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xffeaf0f8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _money(item.unitPrice * item.quantity),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                  color: AppColors.secondaryDark,
                                ),
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
                                    color: AppColors.secondaryDark.withValues(
                                      alpha: 0.06,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'الكمية: ${item.quantity}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.secondaryDark,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
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
                                      color: AppColors.secondaryDark,
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
                        color: const Color(0xfff1f4fa),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xffdfe6f0)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.note_outlined,
                            size: 16,
                            color: AppColors.secondaryDark,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.specialInstructions!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.secondaryDark,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'الإجمالي',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _money(_order!.total),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
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
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xff65728a)),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: valueColor ?? AppColors.secondaryDark,
          ),
        ),
      ],
    );
  }

  Widget _buildCancelOrderSection() => TrackingCancellationCard(
    pending: _order?.cancellationStatus == 'REQUESTED',
    onCancel: _showCancelDialog,
  );

  Future<void> _showCancelDialog() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const TrackingCancellationSheet(),
    );
    if (!mounted || reason == null) return;
    await _cancelOrder(reason.isEmpty ? 'Order cancelled by user' : reason);
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

  String _vehicleDescription(OrderModel o) {
    final kind = switch (o.vehicleType?.toLowerCase()) {
      'car' => 'سيارة',
      'motorcycle' || 'motorbike' || 'bike' => 'دراجة نارية',
      _ => null,
    };
    final plate = o.vehiclePlate?.trim();
    return [
      kind,
      if (plate != null &&
          plate.isNotEmpty &&
          !{'PENDING', 'UNKNOWN', 'NULL', 'N/A'}.contains(plate.toUpperCase()))
        plate,
    ].whereType<String>().join(' • ');
  }

  Widget _buildDeliverySuccess() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFE6EAF0)),
    ),
    child: const Column(
      children: [
        CircleAvatar(
          radius: 38,
          backgroundColor: Color(0xFFEDF6F0),
          child: Icon(Icons.check_rounded, size: 48, color: Color(0xFF23744D)),
        ),
        SizedBox(height: 18),
        Text(
          'بالعافية عليك!',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: Color(0xFF00296B),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'وصل طلبك بنجاح. نتمنى لك تجربة طيبة مع ويز.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF647184)),
        ),
      ],
    ),
  );

  Widget _buildDeliveredActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OrderRatingScreen(orderId: widget.orderId),
              ),
            ),
        icon: const Icon(Icons.star_rounded, size: 21),
        label: const Text('كيف كانت تجربتك؟ قيّم الطلب'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFDC500),
          foregroundColor: const Color(0xFF00296B),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF00296B),
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: Color(0xFFDCE3EE)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text('العودة للرئيسية'),
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) =>
                        CustomerOrderComplaintScreen(orderId: widget.orderId),
              ),
            ),
        icon: const Icon(Icons.support_agent, size: 19),
        label: const Text('تقديم شكوى بخصوص الطلب'),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF00296B)),
      ),
    ],
  );

  Future<void> _openOrderSupport() async {
    if (_openingSupport) return;
    setState(() => _openingSupport = true);
    try {
      final sessionId = await CustomerSupportChat.orderSessionId(
        widget.orderId,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => CustomerSupportChatScreen(
                orderId: widget.orderId,
                sessionId: sessionId,
              ),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح محادثة الدعم. أعد المحاولة.')),
        );
    } finally {
      if (mounted) setState(() => _openingSupport = false);
    }
  }

  Widget _buildSupportEntry() => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEEF2F9),
        child: Icon(Icons.support_agent, color: AppColors.secondaryDark),
      ),
      title: const Text(
        'تواصل مع الدعم',
        style: TextStyle(
          color: AppColors.secondaryDark,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text(
        'محادثة بخصوص هذا الطلب',
        style: TextStyle(color: Color(0xFF65728A), fontSize: 12),
      ),
      trailing:
          _openingSupport
              ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(
                Icons.chevron_left,
                textDirection: TextDirection.ltr,
                color: AppColors.secondaryDark,
              ),
      onTap: _openingSupport ? null : _openOrderSupport,
    ),
  );

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
}
