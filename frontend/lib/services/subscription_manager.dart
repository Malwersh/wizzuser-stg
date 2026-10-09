import 'dart:async';
import 'package:flutter/foundation.dart';
import 'websocket_service.dart';
import 'status_polling_service.dart';

/// مدير الاشتراكات الذكي - يحافظ على الاشتراكات النشطة ويمنع الإلغاء غير الضروري
class SubscriptionManager extends ChangeNotifier {
  static final SubscriptionManager _instance = SubscriptionManager._internal();
  static SubscriptionManager get instance => _instance;
  factory SubscriptionManager() => _instance;
  SubscriptionManager._internal() {
    _initializePollingListener();
  }

  final WebSocketService _webSocketService = WebSocketService.instance;
  final Map<String, Set<String>> _businessSubscribers = {}; // businessId -> Set of subscriberIds
  final Map<String, StreamSubscription<Map<String, dynamic>>> _businessStreams = {};
  final Map<String, StreamController<Map<String, dynamic>>> _businessControllers = {};
  int _subscriberCounter = 0;
  StreamSubscription<Map<String, dynamic>>? _pollingSubscription;
  
  /// الاستماع لتحديثات polling وإعادة بثها للمشتركين
  void _initializePollingListener() {
    _pollingSubscription = StatusPollingService.instance.statusUpdates.listen(
      (update) {
        final businessId = update['businessId'] as String?;
        debugPrint('🔔 SubscriptionManager: استلام حدث polling - businessId=$businessId, data=$update');
        if (businessId != null && _businessControllers.containsKey(businessId)) {
          debugPrint('📡 SubscriptionManager: إعادة بث تحديث polling للمطعم $businessId - عدد المشتركين: ${_businessSubscribers[businessId]?.length ?? 0}');
          if (!_businessControllers[businessId]!.isClosed) {
            _businessControllers[businessId]!.add(update);
            debugPrint('✅ SubscriptionManager: تم البث بنجاح للمطعم $businessId');
          } else {
            debugPrint('⚠️ SubscriptionManager: controller مغلق للمطعم $businessId');
          }
        } else {
          debugPrint('⚠️ SubscriptionManager: لا يوجد مشتركون للمطعم $businessId - المطاعم المتابعة: ${_businessControllers.keys.toList()}');
        }
      },
      onError: (error) {
        debugPrint('❌ SubscriptionManager: خطأ في استقبال polling updates: $error');
      },
    );
    debugPrint('✅ SubscriptionManager: تم الاشتراك في polling updates');
  }

  /// الاشتراك في تحديثات مطعم مع معرف فريد للمشترك
  Stream<Map<String, dynamic>> subscribeToBusinessStatus(String businessId, String subscriberId) {
    debugPrint('🔄 SubscriptionManager: طلب اشتراك - مطعم: $businessId، مشترك: $subscriberId');

    // إضافة المشترك للقائمة
    _businessSubscribers.putIfAbsent(businessId, () => <String>{});
    _businessSubscribers[businessId]!.add(subscriberId);

    // إنشاء stream controller إذا لم يكن موجوداً
    if (!_businessControllers.containsKey(businessId)) {
      _businessControllers[businessId] = StreamController<Map<String, dynamic>>.broadcast();
      debugPrint('✅ SubscriptionManager: إنشاء stream controller جديد للمطعم: $businessId');
    }

    // بدء الاشتراك الفعلي إذا لم يكن موجوداً
    if (!_businessStreams.containsKey(businessId)) {
      _startActualSubscription(businessId);
    }

    debugPrint('📊 SubscriptionManager: عدد المشتركين للمطعم $businessId: ${_businessSubscribers[businessId]!.length}');
    
    return _businessControllers[businessId]!.stream;
  }

  /// الاشتراك المبسط في تحديثات مطعم (ينشئ معرف تلقائياً)
  Stream<Map<String, dynamic>> subscribeToRestaurantStatus(String businessId) {
    final subscriberId = generateSubscriberId('restaurant_card');
    return subscribeToBusinessStatus(businessId, subscriberId);
  }

  /// إلغاء اشتراك مشترك معين
  void unsubscribeFromBusinessStatus(String businessId, String subscriberId) {
    debugPrint('🔄 SubscriptionManager: طلب إلغاء اشتراك - مطعم: $businessId، مشترك: $subscriberId');

    if (_businessSubscribers.containsKey(businessId)) {
      _businessSubscribers[businessId]!.remove(subscriberId);
      
      debugPrint('📊 SubscriptionManager: عدد المشتركين المتبقي للمطعم $businessId: ${_businessSubscribers[businessId]!.length}');

      // إذا لم يعد هناك مشتركون، ألغِ الاشتراك الفعلي
      if (_businessSubscribers[businessId]!.isEmpty) {
        _stopActualSubscription(businessId);
        _businessSubscribers.remove(businessId);
        debugPrint('🛑 SubscriptionManager: تم إلغاء الاشتراك الفعلي للمطعم: $businessId');
      }
    }
  }

  /// بدء الاشتراك الفعلي في WebSocket
  void _startActualSubscription(String businessId) {
    debugPrint('🚀 SubscriptionManager: بدء الاشتراك الفعلي للمطعم: $businessId');
    
    try {
      final stream = _webSocketService.subscribeToBusinessStatus(businessId);
      
      _businessStreams[businessId] = stream.listen(
        (updateData) {
          debugPrint('📡 SubscriptionManager: استلام تحديث للمطعم $businessId');
          
          // إرسال التحديث لجميع المشتركين
          if (_businessControllers.containsKey(businessId) && 
              !_businessControllers[businessId]!.isClosed) {
            _businessControllers[businessId]!.add(updateData);
          }
        },
        onError: (error) {
          debugPrint('❌ SubscriptionManager: خطأ في stream المطعم $businessId: $error');
          
          // إعادة المحاولة بعد فترة
          Future.delayed(const Duration(seconds: 5), () {
            if (_businessSubscribers.containsKey(businessId) && 
                _businessSubscribers[businessId]!.isNotEmpty) {
              debugPrint('🔄 SubscriptionManager: إعادة محاولة الاشتراك للمطعم: $businessId');
              _stopActualSubscription(businessId);
              _startActualSubscription(businessId);
            }
          });
        },
        onDone: () {
          debugPrint('⚠️ SubscriptionManager: تم إغلاق stream للمطعم: $businessId');
          
          // إعادة الاشتراك إذا كان هناك مشتركون
          if (_businessSubscribers.containsKey(businessId) && 
              _businessSubscribers[businessId]!.isNotEmpty) {
            debugPrint('🔄 SubscriptionManager: إعادة إنشاء stream للمطعم: $businessId');
            Future.delayed(const Duration(seconds: 2), () {
              if (_businessSubscribers.containsKey(businessId) && 
                  _businessSubscribers[businessId]!.isNotEmpty) {
                _startActualSubscription(businessId);
              }
            });
          }
        },
      );
      
      debugPrint('✅ SubscriptionManager: تم بدء الاستماع للمطعم: $businessId');
    } catch (e) {
      debugPrint('❌ SubscriptionManager: خطأ في بدء الاشتراك للمطعم $businessId: $e');
    }
  }

  /// إيقاف الاشتراك الفعلي
  void _stopActualSubscription(String businessId) {
    debugPrint('🛑 SubscriptionManager: إيقاف الاشتراك الفعلي للمطعم: $businessId');
    
    // إلغاء stream subscription
    _businessStreams[businessId]?.cancel();
    _businessStreams.remove(businessId);
    
    // إغلاق stream controller
    _businessControllers[businessId]?.close();
    _businessControllers.remove(businessId);
    
    // إلغاء الاشتراك من WebSocket
    _webSocketService.unsubscribeFromBusinessStatus(businessId);
  }

  /// إنشاء معرف فريد للمشترك
  String generateSubscriberId(String prefix) {
    _subscriberCounter++;
    return '${prefix}_$_subscriberCounter';
  }

  /// الحصول على إحصائيات الاشتراكات
  Map<String, dynamic> getSubscriptionStats() {
    return {
      'activeBusinesses': _businessSubscribers.keys.length,
      'totalSubscribers': _businessSubscribers.values
          .map((subscribers) => subscribers.length)
          .fold(0, (sum, count) => sum + count),
      'businessDetails': _businessSubscribers.map(
        (businessId, subscribers) => MapEntry(businessId, subscribers.length),
      ),
    };
  }

  /// تنظيف جميع الاشتراكات
  void cleanup() {
    debugPrint('🧹 SubscriptionManager: تنظيف جميع الاشتراكات');
    
    // إلغاء الاستماع لـ polling updates
    _pollingSubscription?.cancel();
    _pollingSubscription = null;
    
    for (final businessId in _businessStreams.keys.toList()) {
      _stopActualSubscription(businessId);
    }
    
    _businessSubscribers.clear();
    _businessStreams.clear();
    _businessControllers.clear();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
