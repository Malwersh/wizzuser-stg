import '../utils/readable_colors.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/order_service_v2.dart';
import '../services/session_service.dart';
import '../services/websocket_service.dart';
import '../models/order_model.dart';
import '../widgets/connection_status_widget.dart';
import 'order_tracking_screen.dart';
import 'dart:async';

class OrdersScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const OrdersScreen({super.key, this.onBack});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final OrderServiceV2 _orderService = OrderServiceV2();
  final WebSocketService _wsService = WebSocketService();
  Timer? _refreshTimer;

  // متغيرات حالة الاتصال للتحكم في UI
  bool _isWebSocketConnected = false;
  bool _isInitialized = false;

  // جعل الشاشة تستمع للتغييرات في OrderServiceV2
  List<OrderModel> get _currentOrders {
    final orders = _orderService.getActiveOrdersLocal();
    // طباعة للتأكد من أن الـ getter يتم استدعاؤه
    if (orders.isNotEmpty) {
      // print('📋 _currentOrders getter: ${orders.length} طلب نشط');
    }
    return orders;
  }

  List<OrderModel> get _pastOrders {
    final orders = _orderService.getCompletedOrdersLocal();
    // طباعة للتأكد من أن الـ getter يتم استدعاؤه
    if (orders.isNotEmpty) {
      // print('📋 _pastOrders getter: ${orders.length} طلب مكتمل');
    }
    return orders;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // إضافة observer لمراقبة lifecycle
    WidgetsBinding.instance.addObserver(this);

    // الاستماع للتغييرات في التبويبات
    _tabController.addListener(_onTabChanged);

    // الاستماع للتغييرات في OrderServiceV2
    _orderService.addListener(_onOrdersUpdated);

    // التهيئة التدريجية
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    try {
      // تحميل الطلبات أولاً (أسرع)
      await _loadOrders();

      // إعداد WebSocket في الخلفية (قد يأخذ وقت أطول)
      _setupWebSocket(); // بدون await لتجنب التأخير

      // إعداد التحديث التلقائي
      _setupAutoRefresh();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('❌ خطأ في تهيئة الشاشة: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true; // حتى لو فشلت التهيئة، اعرض الشاشة
        });
      }
    }
  }

  @override
  void dispose() {
    // إزالة observer
    WidgetsBinding.instance.removeObserver(this);

    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _refreshTimer?.cancel();
    _orderService.removeListener(_onOrdersUpdated);

    // إلغاء الاشتراك من جميع الطلبات المراقبة
    for (final subscription in _orderSubscriptions.values) {
      subscription.cancel();
    }
    _orderSubscriptions.clear();

    for (final orderId in _subscribedOrderIds) {
      _wsService.unsubscribeFromOrder(orderId);
    }
    _subscribedOrderIds.clear();

    // إزالة listener من WebSocket بأمان
    try {
      _wsService.removeListener(() {});
    } catch (e) {
      print('⚠️ خطأ في إزالة WebSocket listener: $e');
    }

    // لا نستدعي dispose على WebSocket Service لأنه singleton
    // _wsService.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // عند العودة للتطبيق أو الشاشة
        _refreshOnResume();
        break;
      case AppLifecycleState.paused:
        // عند إخفاء التطبيق أو الشاشة
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// تحديث البيانات عند العودة للشاشة - محسّن للتحديثات الفورية
  Future<void> _refreshOnResume() async {
    if (!mounted) return;

    try {
      print('🔄 تحديث البيانات عند العودة للشاشة...');

      // إعادة تحميل الطلبات
      await _loadOrders();

      // التحقق من حالة WebSocket وإعادة الاتصال إذا لزم الأمر
      if (!_wsService.isConnected) {
        print('🔌 إعادة اتصال WebSocket عند العودة للشاشة');
        await _setupWebSocket();
      } else {
        print('✅ WebSocket متصل، إعادة إعداد المستمعات');
        // إعادة إعداد المستمعات للطلبات الحالية
        _setupOrderUpdatesListener();
      }

      print('✅ تم تحديث البيانات بنجاح عند العودة للشاشة');
    } catch (e) {
      print('❌ خطأ في تحديث البيانات عند العودة: $e');
    }
  }

  // دالة للاستجابة لتغيير التبويب - محسّنة لاستخدام البيانات المحلية الفورية
  void _onTabChanged() {
    if (mounted) {
      print(
        '📑 تغيير التبويب إلى: ${_tabController.index == 0 ? "الحالية" : "السابقة"}',
      );

      // 🚀 FIX: استخدام البيانات المحلية فقط - لا نحتاج API calls
      // البيانات محدثة بالفعل عبر WebSocket real-time updates
      setState(() {
        // تحديث فوري للواجهة باستخدام البيانات المحلية المحدثة
        // لا نحتاج لاستدعاء _loadActiveOrders() أو _loadCompletedOrders()
        // فقط إعادة بناء الواجهة بالبيانات الموجودة
      });

      print('✅ تم تحديث التبويب بالبيانات المحلية الفورية');
      print('   - الطلبات النشطة المتاحة: ${_currentOrders.length}');
      print('   - الطلبات المكتملة المتاحة: ${_pastOrders.length}');
    }
  }

  // دالة للاستجابة لتحديثات الطلبات - محسّنة للتحديث الفوري
  void _onOrdersUpdated() {
    if (mounted) {
      print('🔔 _onOrdersUpdated: تلقي إشعار تحديث من OrderServiceV2');

      // 🚀 ENHANCED: تحديث فوري مع تحديث البيانات والواجهة
      Future.microtask(() {
        if (mounted) {
          setState(() {
            // تحديث فوري للبيانات من OrderService
            _refreshOrdersFromService();
          });
          print('⚡ تم تحديث الواجهة والبيانات فورياً بدون تأخير');

          print('   - الطلبات النشطة: ${_currentOrders.length}');
          print('   - الطلبات المكتملة: ${_pastOrders.length}');

          // إعادة إعداد WebSocket listeners للطلبات الجديدة أو المحدثة
          if (_wsService.isConnected) {
            _setupOrderUpdatesListener();
          }
        }
      });
    }
  }

  // تحديث البيانات من OrderService بدون استدعاء API
  void _refreshOrdersFromService() {
    // البيانات محدثة بالفعل في OrderService, الـ getters ستسحب البيانات المحدثة
    print(
      '📊 تحديث البيانات المحلية - الطلبات النشطة: ${_currentOrders.length}, المكتملة: ${_pastOrders.length}',
    );
  }

  void _setupAutoRefresh() {
    // 🔥 REAL-TIME FIRST: WebSocket أولاً، polling احتياطي نادر كل 2 دقيقة فقط للطوارئ
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (!mounted) return;

      print('🔍 فحص حالة النظام الدوري...');

      // التحقق من حالة WebSocket أولاً
      if (!_wsService.isConnected) {
        print('🚨 WebSocket منقطع - محاولة إعادة الاتصال فورية');
        _setupWebSocket();

        // polling احتياطي فقط إذا كان WebSocket منقطع لفترة طويلة
        if (_currentOrders.isNotEmpty) {
          print('🔄 Polling احتياطي للطلبات النشطة بسبب انقطاع WebSocket');
          // تحميل كامل للطلبات فقط في حالة الطوارئ
          _loadOrders();
        }
      } else {
        print('✅ WebSocket متصل - فحص المستمعات');

        // التحقق من المستمعات وإعادة إعدادها إذا لزم الأمر
        bool needsListenerRefresh = false;

        for (final order in _currentOrders) {
          if (!_subscribedOrderIds.contains(order.id)) {
            needsListenerRefresh = true;
            break;
          }
        }

        if (needsListenerRefresh) {
          print('🔄 إعادة إعداد مستمعات WebSocket للطلبات الجديدة');
          _setupOrderUpdatesListener();
        } else {
          print('✅ جميع المستمعات تعمل بشكل صحيح');
        }
      }
    });
  }

  Future<void> _setupWebSocket() async {
    try {
      // ✅ فقط إعداد المستمعات إذا كان هناك اتصال موجود بالفعل
      // لا نقوم بإنشاء اتصال جديد هنا - الاتصالات تتم فقط عبر connectForOrder(orderId)
      if (_wsService.isConnected) {
        print('✅ WebSocket: متصل بالفعل - إعداد المستمعات للطلبات الموجودة');
        setState(() {
          _isWebSocketConnected = true;
        });
        _setupOrderUpdatesListener();
        return;
      }

      // ✅ إذا لم يكن هناك اتصال، نسجل فقط ولا نقوم بإنشاء اتصال
      print('ℹ️ WebSocket: غير متصل - المستمعات ستُفعّل عند الاتصال لطلب محدد');

      // انتظار قصير لأي عمليات قيد التنفيذ
      await Future.delayed(const Duration(milliseconds: 100));

      // الاستماع لتغييرات حالة الاتصال - بنفس منطق شاشة التتبع
      _wsService.connectionStream.listen((isConnected) {
        print(
          'OrdersScreen: WebSocket connection status changed: $isConnected',
        );
        if (mounted) {
          setState(() {
            _isWebSocketConnected = isConnected;
            if (isConnected) {
              print('✅ WebSocket: متصل - تفعيل التحديثات الفورية');
              // إعادة إعداد المستمعات عند إعادة الاتصال - فوري وبدون تأخير
              Future.microtask(() {
                _setupOrderUpdatesListener();
              });
            } else {
              print('⚠️ WebSocket: غير متصل - استخدام Polling كل 30 ثانية');
              // تنظيف الاشتراكات عند انقطاع الاتصال
              for (final subscription in _orderSubscriptions.values) {
                subscription.cancel();
              }
              _orderSubscriptions.clear();
              _subscribedOrderIds.clear();
            }
          });
        }
      });

      // تحديث الحالة الأولية وإعداد المستمع
      if (mounted) {
        setState(() {
          _isWebSocketConnected = _wsService.isConnected;
        });
        if (_wsService.isConnected) {
          // إعداد المستمعات فورياً
          Future.microtask(() {
            _setupOrderUpdatesListener();
          });
        }
      }
    } catch (e) {
      print('❌ خطأ في إعداد WebSocket: $e');
      if (mounted) {
        setState(() {
          _isWebSocketConnected = false;
        });
      }
      // لا نريد إيقاف التطبيق بسبب مشكلة WebSocket
    }
  }

  // تتبع الطلبات التي تم إعداد مستمعات لها
  final Set<String> _subscribedOrderIds = <String>{};
  final Map<String, StreamSubscription<OrderModel>> _orderSubscriptions = {};

  // إعداد مستمع التحديثات الفورية للطلبات - محسّن للتحديث الفوري
  void _setupOrderUpdatesListener() {
    if (!_wsService.isConnected) {
      print('⚠️ WebSocket غير متصل - تأجيل إعداد المستمعات');
      return;
    }

    print('🎧 إعداد مستمع التحديثات الفورية للطلبات...');

    // 🚀 NEW FIX: بدلاً من الاشتراك في طلبات محددة فقط، نشترك في جميع تحديثات المستخدم
    // هذا يضمن استلام تحديثات أي طلب للمستخدم حتى لو لم يكن في القائمة المحلية
    final userId = SessionService.getUserIdStatic();
    final guestToken = _orderService.guestToken;

    if (userId != null && userId.isNotEmpty && userId != 'guest') {
      // المستخدم مسجل - اشتراك في جميع طلباته
      print('👤 إعداد اشتراك شامل لجميع طلبات المستخدم: $userId');
      _setupUserOrdersListener(userId);
    } else if (guestToken != null && guestToken.isNotEmpty) {
      // المستخدم ضيف - اشتراك في طلبات الضيف
      print('🎭 إعداد اشتراك شامل لطلبات الضيف: $guestToken');
      _setupGuestOrdersListener(guestToken);
    } else {
      print('⚠️ لا يمكن تحديد المستخدم - استخدام الطريقة التقليدية');
      _setupIndividualOrderListeners();
    }
  }

  // إعداد اشتراك شامل لجميع طلبات المستخدم المسجل
  void _setupUserOrdersListener(String userId) {
    print('🎯 إعداد مستمع شامل لطلبات المستخدم: $userId');

    // إلغاء الاشتراكات الفردية القديمة
    _cancelAllSubscriptions();

    // الاشتراك في جميع تحديثات طلبات المستخدم
    final userOrdersStream = _wsService.subscribeToUserOrders(userId);

    final subscription = userOrdersStream.listen(
      (updatedOrder) {
        print(
          '🎉 🔄 OrdersScreen: استلام تحديث WebSocket لطلب المستخدم ${updatedOrder.id}',
        );
        print('   - رقم الطلب: ${updatedOrder.orderNumber}');
        print('   - الحالة الجديدة: ${updatedOrder.status.arabicName}');

        if (mounted) {
          Future.microtask(() {
            if (mounted) {
              _handleRealtimeOrderUpdate(updatedOrder);
            }
          });
        }
      },
      onError: (error) {
        print('❌ خطأ في اشتراك طلبات المستخدم: $error');
        // إعادة المحاولة بعد تأخير
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _wsService.isConnected) {
            _setupUserOrdersListener(userId);
          }
        });
      },
      onDone: () {
        print('🔚 انتهى stream تحديثات طلبات المستخدم');
      },
    );

    // حفظ الاشتراك الرئيسي
    _orderSubscriptions['user_orders_$userId'] = subscription;
    print('✅ تم إعداد اشتراك شامل لطلبات المستخدم');
  }

  // إعداد اشتراك شامل لطلبات المستخدم الضيف
  void _setupGuestOrdersListener(String guestToken) {
    print('🎯 إعداد مستمع شامل لطلبات الضيف: $guestToken');

    // إلغاء الاشتراكات الفردية القديمة
    _cancelAllSubscriptions();

    // الاشتراك في جميع تحديثات طلبات الضيف
    final guestOrdersStream = _wsService.subscribeToGuestOrders(guestToken);

    final subscription = guestOrdersStream.listen(
      (updatedOrder) {
        print(
          '🎉 🔄 OrdersScreen: استلام تحديث WebSocket لطلب الضيف ${updatedOrder.id}',
        );
        print('   - رقم الطلب: ${updatedOrder.orderNumber}');
        print('   - الحالة الجديدة: ${updatedOrder.status.arabicName}');

        if (mounted) {
          Future.microtask(() {
            if (mounted) {
              _handleRealtimeOrderUpdate(updatedOrder);
            }
          });
        }
      },
      onError: (error) {
        print('❌ خطأ في اشتراك طلبات الضيف: $error');
        // إعادة المحاولة بعد تأخير
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _wsService.isConnected) {
            _setupGuestOrdersListener(guestToken);
          }
        });
      },
      onDone: () {
        print('🔚 انتهى stream تحديثات طلبات الضيف');
      },
    );

    // حفظ الاشتراك الرئيسي
    _orderSubscriptions['guest_orders_$guestToken'] = subscription;
    print('✅ تم إعداد اشتراك شامل لطلبات الضيف');
  }

  // الطريقة التقليدية للاشتراك في طلبات فردية (fallback)
  void _setupIndividualOrderListeners() {
    print('🔄 استخدام الطريقة التقليدية للاشتراك في طلبات فردية');

    // الاستماع لتحديثات جميع الطلبات المحلية
    final currentOrders = _orderService.orders;
    final currentOrderIds = currentOrders.map((order) => order.id).toSet();

    print('📋 عدد الطلبات للاستماع إليها: ${currentOrders.length}');

    // تنظيف الطلبات التي لم تعد موجودة
    final orderIdsToRemove = _subscribedOrderIds.difference(currentOrderIds);
    for (final orderId in orderIdsToRemove) {
      print('🗑️ إزالة مستمع للطلب المحذوف: $orderId');
      _orderSubscriptions[orderId]?.cancel();
      _orderSubscriptions.remove(orderId);
      _subscribedOrderIds.remove(orderId);
    }

    if (currentOrders.isEmpty) {
      print('⚠️ لا توجد طلبات للاستماع إليها');
      return;
    }

    int newSubscriptions = 0;

    for (final order in currentOrders) {
      if (order.id.isNotEmpty && !_subscribedOrderIds.contains(order.id)) {
        print('🔔 إضافة مستمع للطلب: ${order.orderNumber} (${order.id})');

        // إضافة إلى قائمة المراقبة
        _subscribedOrderIds.add(order.id);
        newSubscriptions++;

        // 🔧 نفس المنطق المستخدم في شاشة التتبع
        print('🎧 بدء الاشتراك في تحديثات الطلب ${order.id}...');
        print('   - حالة الطلب الحالية: ${order.status.arabicName}');
        print('   - رقم الطلب: ${order.orderNumber}');
        final orderStream = _wsService.subscribeToOrder(order.id);
        print('📡 تم إنشاء stream تحديثات الطلب ${order.id}');

        final subscription = orderStream.listen(
          (updatedOrder) {
            print(
              '🎉 🔄 OrdersScreen: استلام تحديث WebSocket للطلب ${updatedOrder.id}',
            );
            print('   - رقم الطلب: ${updatedOrder.orderNumber}');
            print('   - الحالة الجديدة: ${updatedOrder.status.arabicName}');
            print('   - الحالة الجديدة (value): ${updatedOrder.status.value}');

            if (mounted) {
              // 🚀 CRITICAL FIX: التحديث الفوري والمباشر مع إعطاء أولوية للتحديث
              Future.microtask(() {
                if (mounted) {
                  _handleRealtimeOrderUpdate(updatedOrder);
                }
              });
            } else {
              print('⚠️ OrdersScreen: الشاشة غير مفعلة - تجاهل التحديث');
            }
          },
          onError: (error) {
            print(
              '❌ خطأ في اشتراك WebSocket للطلب ${order.orderNumber}: $error',
            );
            // إعادة إعداد الاشتراك في حالة الخطأ
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && _wsService.isConnected) {
                print(
                  '🔄 إعادة محاولة إعداد مستمع WebSocket للطلب ${order.orderNumber}',
                );
                _setupOrderUpdatesListener();
              }
            });
          },
          onDone: () {
            print('🔚 انتهى stream تحديثات الطلب ${order.id}');
          },
        );

        _orderSubscriptions[order.id] = subscription;
      }
    }

    print(
      '✅ تم إعداد $newSubscriptions مستمع جديد للطلبات (إجمالي: ${_subscribedOrderIds.length})',
    );
  }

  // إلغاء جميع الاشتراكات
  void _cancelAllSubscriptions() {
    print('🧹 إلغاء جميع اشتراكات WebSocket الحالية');
    for (final subscription in _orderSubscriptions.values) {
      subscription.cancel();
    }
    _orderSubscriptions.clear();
    _subscribedOrderIds.clear();
  }

  // 🚀 دالة جديدة للتعامل مع التحديثات الفورية بشكل أكثر كفاءة
  void _handleRealtimeOrderUpdate(OrderModel updatedOrder) {
    print(
      '🔥 REALTIME UPDATE: معالجة تحديث فوري للطلب ${updatedOrder.orderNumber}',
    );

    // البحث عن الطلب في القائمة المحلية
    final orderIndex = _orderService.orders.indexWhere(
      (o) => o.id == updatedOrder.id,
    );

    if (orderIndex != -1) {
      final oldOrder = _orderService.orders[orderIndex];
      print('📝 تحديث الطلب في الموضع $orderIndex');
      print('   - الحالة القديمة: ${oldOrder.status.arabicName}');
      print('   - الحالة الجديدة: ${updatedOrder.status.arabicName}');

      // ✅ 1. تحديث فوري في OrderService
      _orderService.updateOrderInList(updatedOrder);

      // ✅ 2. تحديث فوري للواجهة - استخدام microtask للتحديث الفوري
      if (mounted) {
        // استخدام microtask للتحديث الفوري بدون تأخير
        Future.microtask(() {
          if (mounted) {
            setState(() {
              // تحديث فوري - البيانات محدثة بالفعل في OrderService
            });
            print(
              '🎯 INSTANT UI UPDATE: تم تحديث الواجهة فورياً للطلب ${updatedOrder.orderNumber}',
            );
          }
        });
      }

      // ✅ 3. إشعار المستخدم بالتحديث
      _showOrderStatusUpdate(updatedOrder);

      print(
        '🎉 REALTIME UPDATE COMPLETE: التحديث الفوري مكتمل للطلب ${updatedOrder.orderNumber}',
      );
    } else {
      print(
        '⚠️ OrdersScreen: لم يتم العثور على الطلب ${updatedOrder.id} في القائمة المحلية',
      );

      // محاولة إضافة الطلب إذا لم يكن موجود (طلب جديد)
      if (updatedOrder.status != OrderStatus.delivered &&
          updatedOrder.status != OrderStatus.cancelled) {
        print('➕ إضافة طلب جديد للقائمة');
        _orderService.addOrderToLocal(updatedOrder);
        if (mounted) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                // إضافة الطلب الجديد - OrderService يدير البيانات
              });
              print('✅ تم إضافة طلب جديد وتحديث الواجهة فورياً');
            }
          });
        }
      } else {
        // طلب مكتمل أو ملغى - إضافته للطلبات السابقة
        print('➕ إضافة طلب مكتمل/ملغى للطلبات السابقة');
        _orderService.addOrderToLocal(updatedOrder);
        if (mounted) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                // إضافة الطلب المكتمل - OrderService يدير البيانات
              });
              print('✅ تم إضافة طلب مكتمل وتحديث الواجهة فورياً');
            }
          });
        }
      }
    }
  }

  // إظهار إشعار عند تحديث حالة الطلب - محسّن
  void _showOrderStatusUpdate(OrderModel order) {
    if (!mounted) return;

    print(
      '🔔 إظهار إشعار تحديث حالة الطلب: ${order.orderNumber} -> ${order.status.arabicName}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getStatusIcon(order.status),
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'طلب #${order.orderNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${_getStatusText(order.status)} 🔥',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: _getStatusColor(order.status),
        duration: const Duration(seconds: 4), // مدة أطول للإشعارات المهمة
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'تتبع',
          textColor: Colors.white,
          backgroundColor: Colors.white.withOpacity(0.2),
          onPressed: () => _navigateToTracking(order),
        ),
      ),
    );
  }

  Future<void> _loadOrders() async {
    try {
      // الحصول على معرف المستخدم الحالي
      final currentUserId = await _getCurrentUserId();
      print('🆔 معرف المستخدم المُستخرج: $currentUserId');

      // Ensure OrderServiceV2 is fully initialized before accessing guestToken
      await _orderService.ensureInitialized();

      // Check if this is a guest user with a guest token
      final guestToken = _orderService.guestToken;
      print('🎫 Guest token من OrderService (after init): $guestToken');

      if (currentUserId != null) {
        // Registered user - load normal orders
        print('👤 تحميل طلبات المستخدم المسجل...');
        await _orderService.getUserOrders(currentUserId);
      } else if (guestToken != null && guestToken.isNotEmpty) {
        // Guest user - load guest orders using guestToken
        print('🎭 تحميل طلبات المستخدم الضيف باستخدام guestToken...');
        await _orderService.getGuestOrders(status: 'all');
      } else {
        print('⚠️ لا يوجد مستخدم مسجل دخول ولا guestToken - مسح الطلبات');
        _orderService.clearOrders();
      }

      // طباعة النتائج بعد التحميل
      final allOrders = _orderService.orders;
      final activeOrders = _orderService.getActiveOrdersLocal();
      final completedOrders = _orderService.getCompletedOrdersLocal();

      print('📊 نتائج التحميل:');
      print('   - إجمالي الطلبات: ${allOrders.length}');
      print('   - الطلبات النشطة: ${activeOrders.length}');
      print('   - الطلبات المكتملة: ${completedOrders.length}');

      if (allOrders.isNotEmpty) {
        print('📦 تفاصيل الطلبات المحملة:');
        for (int i = 0; i < allOrders.length; i++) {
          final order = allOrders[i];
          print(
            '   ${i + 1}. ${order.orderNumber} - ${order.status.value} - ${order.createdAt}',
          );
        }
      } else {
        print('⚠️ لا توجد طلبات محملة من الخدمة');
      }

      if (activeOrders.isNotEmpty) {
        print('🔥 الطلبات النشطة التي يجب عرضها:');
        for (final order in activeOrders) {
          print('   - ${order.orderNumber}: ${order.status.name}');
        }
      } else {
        print('⚠️ لا توجد طلبات نشطة لعرضها');
      }

      if (mounted) {
        setState(() {});
        print('🔔 تم تحديث واجهة المستخدم');
      }

      // إعداد مستمع التحديثات الفورية للجميع (مسجلين وضيوف)
      if (allOrders.isNotEmpty) {
        print('🎧 إعداد مستمعات التحديثات الفورية للطلبات المحملة...');

        if (_wsService.isConnected) {
          _setupOrderUpdatesListener();
        } else {
          print('⚠️ WebSocket غير متصل - محاولة إعادة الاتصال...');
          // إعادة إعداد WebSocket للضيوف والمستخدمين المسجلين
          Future.microtask(() {
            _setupWebSocket();
          });
        }
      } else {
        print('ℹ️ لا توجد طلبات - لا حاجة لإعداد WebSocket listeners');
      }

      print('🏁 === انتهى تحميل الطلبات ===');
    } catch (e) {
      print('❌ خطأ في تحميل الطلبات: $e');
    }
  }

  Future<void> _loadActiveOrders() async {
    try {
      print('🔄 _loadActiveOrders: استخدام البيانات المحلية الفورية...');

      // 🚀 FIX: استخدام البيانات المحلية فقط للتحديث السريع
      // البيانات محدثة بالفعل عبر WebSocket real-time
      if (mounted) {
        setState(() {
          // البيانات محدثة في الخلفية عبر WebSocket
        });
      }

      print('✅ تم تحديث الطلبات النشطة من البيانات المحلية');
      print('   - عدد الطلبات النشطة: ${_currentOrders.length}');

      // إعادة إعداد WebSocket listeners إذا لزم الأمر
      if (_wsService.isConnected && _currentOrders.isNotEmpty) {
        _setupOrderUpdatesListener();
      }
    } catch (e) {
      print('❌ خطأ في تحديث الطلبات النشطة: $e');
    }
  }

  Future<void> _loadCompletedOrders() async {
    try {
      print('🔄 _loadCompletedOrders: استخدام البيانات المحلية الفورية...');

      // 🚀 FIX: استخدام البيانات المحلية فقط للتحديث السريع
      // البيانات محدثة بالفعل عبر WebSocket real-time
      if (mounted) {
        setState(() {
          // البيانات محدثة في الخلفية عبر WebSocket
        });
      }

      print('✅ تم تحديث الطلبات المكتملة من البيانات المحلية');
      print('   - عدد الطلبات المكتملة: ${_pastOrders.length}');
    } catch (e) {
      print('❌ خطأ في تحديث الطلبات المكتملة: $e');
    }
  }

  // الحصول على معرف المستخدم الحالي من مصادر متعددة
  Future<String?> _getCurrentUserId() async {
    try {
      // التحقق أولاً إذا كان المستخدم ضيف
      final isGuest = SessionService.instance.isGuest;
      print('🔍 Is guest user: $isGuest');

      if (isGuest) {
        print('🎭 المستخدم ضيف - إرجاع null لاستخدام guestToken');
        return null;
      }

      // محاولة الحصول على المعرف من SessionService للمستخدمين المسجلين
      String? userId = SessionService.getUserIdStatic();
      print('🔍 SessionService userId: $userId');

      // تجاهل "guest" كمعرف مستخدم صالح
      if (userId != null && userId.isNotEmpty && userId != 'guest') {
        return userId;
      }

      // محاولة الحصول على المعرف من SessionManager
      final userData = await SessionService.instance.getUserData();
      print('🔍 SessionManager userData: $userData');
      userId =
          userData?['userId'] ?? userData?['user_id'] ?? userData?['email'];
      print('🔍 Extracted userId from userData: $userId');

      // تجاهل "guest" كمعرف مستخدم صالح
      if (userId != null && userId.isNotEmpty && userId != 'guest') {
        return userId;
      }

      // التحقق من حالة تسجيل الدخول
      final isLoggedIn = await SessionService.instance.isSessionValid();
      print('🔍 Session valid: $isLoggedIn');
      if (!isLoggedIn) {
        return null;
      }

      return null;
    } catch (e) {
      print('❌ خطأ في الحصول على معرف المستخدم: $e');
      return null;
    }
  }

  Widget _buildOrderCard(OrderModel order, {bool isActive = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border:
            isActive && _isUrgentStatus(order.status)
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
      ),
      child: Column(
        children: [
          // Header with order info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStatusColor(order.status).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getStatusIcon(order.status),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'طلب #${order.orderNumber}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusText(order.status),
                        style: TextStyle(
                          fontSize: 14,
                          color: _getStatusColor(order.status),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive && _isUrgentStatus(order.status))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'عاجل',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Order details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.restaurant, color: Colors.grey, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.storeName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_basket_outlined,
                      color: Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${order.items.length} عنصر • ${order.total.toStringAsFixed(0)} د.ع',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.grey, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatOrderTime(order.createdAt),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Action buttons
                Column(
                  children: [
                    Row(
                      children: [
                        if (isActive) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _callRestaurant(order),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[700],
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.phone, size: 18),
                              label: const Text('اتصال'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          flex: isActive ? 2 : 1,
                          child: ElevatedButton.icon(
                            onPressed: () => _navigateToTracking(order),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.secondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: Icon(
                              isActive ? Icons.track_changes : Icons.receipt,
                              size: 18,
                            ),
                            label: Text(
                              isActive ? 'تتبع الطلب' : 'عرض التفاصيل',
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Cancel button for active orders that can be cancelled
                    if (isActive &&
                        order.cancellationStatus == 'REQUESTED') ...[
                      const SizedBox(height: 12),
                      const Text(
                        'طلب الإلغاء قيد المراجعة؛ يظل الطلب نشطًا حتى تأكيد إلغائه.',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (isActive &&
                        order.canBeCancelled &&
                        order.cancellationStatus != 'REQUESTED') ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showCancelOrderDialog(order),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.cancel, size: 18),
                          label: const Text('إلغاء الطلب'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentOrders() {
    if (_orderService.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            SizedBox(height: 16),
            Text(
              'جاري تحميل الطلبات النشطة...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_currentOrders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadActiveOrders,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      size: 80,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'لا توجد طلبات حالية',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اسحب للأسفل للتحديث',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadActiveOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _currentOrders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder:
            (context, index) =>
                _buildOrderCard(_currentOrders[index], isActive: true),
      ),
    );
  }

  Widget _buildPastOrders() {
    if (_orderService.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            SizedBox(height: 16),
            Text(
              'جاري تحميل الطلبات السابقة...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_pastOrders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCompletedOrders,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.history,
                      size: 80,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'لا توجد طلبات سابقة',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ستظهر هنا طلباتك المكتملة والملغية',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اسحب للأسفل للتحديث',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCompletedOrders,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pastOrders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final order = _pastOrders[index];
          return _buildOrderCard(order, isActive: false);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // عرض شاشة تحميل أثناء التهيئة
    if (!_isInitialized) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'الطلبات',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.black),
            automaticallyImplyLeading: false,
          ),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
                SizedBox(height: 16),
                Text(
                  'جاري تحميل الطلبات...',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(
            kToolbarHeight + MediaQuery.of(context).padding.top + 4,
          ),
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 4,
              left: 16,
              right: 16,
            ),
            decoration: const BoxDecoration(color: Colors.white),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              title: const Text(
                'الطلبات',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconTheme: const IconThemeData(color: Colors.black),
              automaticallyImplyLeading: false,
              actions: [
                // مؤشر حالة الاتصال في AppBar
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: () {
                      // التحقق من أن الـ widget ما زال mounted قبل عرض الـ dialog
                      if (!mounted) return;

                      // عرض تفاصيل الاتصال
                      showDialog(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: const Text('حالة الاتصال'),
                              content: const ConnectionStatusWidget(
                                showDetailed: true,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('حسناً'),
                                ),
                              ],
                            ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _isWebSocketConnected
                                ? Colors.green.withOpacity(0.1)
                                : AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              _isWebSocketConnected
                                  ? Colors.green
                                  : AppColors.primary,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isWebSocketConnected ? Icons.wifi : Icons.refresh,
                            size: 16,
                            color:
                                _isWebSocketConnected
                                    ? Colors.green
                                    : AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isWebSocketConnected ? 'مباشر' : 'تلقائي',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  _isWebSocketConnected
                                      ? Colors.green
                                      : AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            // شريط حالة الاتصال
            Container(
              width: double.infinity,
              child: const ConnectionStatusWidget(
                showDetailed: false,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            // التبويبات
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppColors.primary,
                tabs: const [Tab(text: 'الحالية'), Tab(text: 'السابقة')],
              ),
            ),
            // المحتوى
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildCurrentOrders(), _buildPastOrders()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods
  bool _isUrgentStatus(OrderStatus status) {
    return status == OrderStatus.ready ||
        status == OrderStatus.readyForPickup ||
        status == OrderStatus.onTheWay ||
        status == OrderStatus.headingToCustomer;
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.returning:
      case OrderStatus.returnArrived:
        return Colors.orange;
      case OrderStatus.returned:
        return Colors.blueGrey;
      case OrderStatus.pending:
        return AppColors.primary;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.preparing:
        return Colors.purple;
      case OrderStatus.ready:
      case OrderStatus.readyForPickup:
        return Colors.green;
      case OrderStatus.reassigning:
        return Colors.orange;
      case OrderStatus.assigned:
      case OrderStatus.accepted:
        return Colors.blue;
      case OrderStatus.headingToStore:
        return Colors.orange;
      case OrderStatus.arrivedAtStore:
        return Colors.orange;
      case OrderStatus.pickedUp:
        return Colors.teal;
      case OrderStatus.onTheWay:
      case OrderStatus.headingToCustomer:
        return AppColors.primary;
      case OrderStatus.arrivedAtCustomer:
        return Colors.deepPurple;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
      case OrderStatus.failed:
        return Colors.red;
      case OrderStatus.expired:
        return Colors.grey;
      case OrderStatus.rejected:
        return Colors.red;
    }
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.returning:
        return Icons.assignment_return;
      case OrderStatus.returnArrived:
        return Icons.store;
      case OrderStatus.returned:
        return Icons.assignment_turned_in;
      case OrderStatus.pending:
        return Icons.schedule;
      case OrderStatus.confirmed:
        return Icons.check_circle_outline;
      case OrderStatus.preparing:
        return Icons.restaurant;
      case OrderStatus.ready:
      case OrderStatus.readyForPickup:
        return Icons.shopping_bag;
      case OrderStatus.reassigning:
        return Icons.search;
      case OrderStatus.assigned:
      case OrderStatus.accepted:
        return Icons.check_circle;
      case OrderStatus.headingToStore:
        return Icons.directions_car;
      case OrderStatus.arrivedAtStore:
        return Icons.store;
      case OrderStatus.pickedUp:
        return Icons.shopping_bag_outlined;
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
        return Icons.access_time_filled;
      case OrderStatus.rejected:
        return Icons.block;
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.returning:
        return 'السائق يعيد الطلب للمطعم';
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
        return 'جاري البحث عن سائق بديل';
      case OrderStatus.assigned:
        return 'تم تعيين سائق';
      case OrderStatus.accepted:
        return 'تم قبوله من السائق';
      case OrderStatus.headingToStore:
        return 'السائق في الطريق للمطعم';
      case OrderStatus.arrivedAtStore:
        return 'السائق وصل للمطعم';
      case OrderStatus.pickedUp:
        return 'تم استلام الطلب';
      case OrderStatus.onTheWay:
      case OrderStatus.headingToCustomer:
        return 'في الطريق إليك';
      case OrderStatus.arrivedAtCustomer:
        return 'السائق وصل';
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

  String _formatOrderTime(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'الآن';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }

  void _callRestaurant(OrderModel order) {
    // التحقق من أن الـ widget ما زال mounted قبل عرض الـ SnackBar
    if (!mounted) return;

    // يمكن تطبيق الاتصال بالمطعم هنا
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيتم إضافة خاصية الاتصال قريباً'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _navigateToTracking(OrderModel order) {
    // التحقق من أن الـ widget ما زال mounted قبل التنقل
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => OrderTrackingScreen(
              orderId: order.id,
              orderNumber: order.orderNumber,
            ),
      ),
    );
  }

  void _showCancelOrderDialog(OrderModel order) {
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
                Text(
                  'هل أنت متأكد من رغبتك في إلغاء طلب #${order.orderNumber}؟',
                  style: const TextStyle(fontSize: 16),
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
                  _cancelOrderFromOrdersScreen(
                    order.id,
                    reason.isEmpty ? 'Order cancelled by user' : reason,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: readableForeground(Colors.red),
                ),
                child: const Text('إلغاء الطلب'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelOrderFromOrdersScreen(
    String orderId,
    String reason,
  ) async {
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

      // Cancel the order using OrderService
      final success = await _orderService.cancelOrder(
        orderId,
        reason.isEmpty ? 'Order cancelled by user' : reason,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (success) {
        final pending = _orderService.lastCancellationPending;
        final message = _orderService.lastCancellationMessage;
        // The server may have recorded a request without cancelling the order.
        await _loadOrders();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                pending
                    ? (message ??
                        'طلب الإلغاء قيد المراجعة؛ يظل الطلب نشطًا حتى تأكيد إلغائه.')
                    : 'تم إلغاء الطلب بنجاح',
              ),
              backgroundColor: pending ? AppColors.secondary : Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 8),
                  Text('فشل في إلغاء الطلب، يرجى المحاولة مرة أخرى'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if it's still open
      if (mounted) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Text('خطأ: ${e.toString()}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
