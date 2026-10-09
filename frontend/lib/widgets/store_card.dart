import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/store_model.dart';
import '../models/favorites_model.dart';
import '../services/restaurant_availability_service.dart';
import '../services/websocket_service.dart';

class StoreCard extends StatefulWidget {
  final StoreModel store;
  final Function()? onTap;
  final bool isCompact;
  final bool showFavoriteButton;

  const StoreCard({
    super.key,
    required this.store,
    this.onTap,
    this.isCompact = false,
    this.showFavoriteButton = true,
  });

  @override
  State<StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<StoreCard> {
  final RestaurantAvailabilityService _availabilityService = 
      RestaurantAvailabilityService.instance;
  final WebSocketService _webSocketService = WebSocketService.instance;
  RestaurantAvailabilityStatus? _availabilityStatus;
  bool _isLoadingStatus = true;
  StreamSubscription<Map<String, dynamic>>? _businessStatusSubscription;

  @override
  void initState() {
    super.initState();
    _loadAvailabilityStatus();
    _setupWebSocketListener();
  }

  @override
  void didUpdateWidget(StoreCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload status if store ID changed
    if (oldWidget.store.id != widget.store.id) {
      _businessStatusSubscription?.cancel();
      _loadAvailabilityStatus();
      _setupWebSocketListener();
    }
  }

  @override
  void dispose() {
    _businessStatusSubscription?.cancel();
    _webSocketService.unsubscribeFromBusinessStatus(widget.store.id);
    super.dispose();
  }

  /// إعداد الاستماع لتحديثات WebSocket
  void _setupWebSocketListener() {
    try {
      // إلغاء الاشتراك السابق قبل إنشاء جديد
      _businessStatusSubscription?.cancel();
      
      // 🔧 إصلاح: لا نستدعي connect() هنا - سيتم الاتصال تلقائياً عند الحاجة
      // WebSocket يتصل فقط عند إنشاء طلب عبر connectForOrder()

      // انتظار قصير لضمان استقرار الاتصال
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        
        // الاشتراك في تحديثات حالة هذا المطعم
        _businessStatusSubscription = _webSocketService
            .subscribeToBusinessStatus(widget.store.id)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: (sink) {
                debugPrint('⏰ انتهت مهلة الاشتراك للمطعم ${widget.store.id} في StoreCard - إعادة المحاولة');
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) {
                    _setupWebSocketListener();
                  }
                });
              },
            )
            .listen(
          (updateData) {
            if (mounted) {
              debugPrint('🔄 استلم تحديث حالة للمطعم ${widget.store.id} في StoreCard');
              _handleBusinessStatusUpdate(updateData);
              
              // التأكد من أن الاشتراك ما زال نشطاً
              _ensureSubscriptionActive();
            }
          },
          onError: (error) {
            debugPrint('❌ خطأ في الاستماع لتحديثات المطعم ${widget.store.id}: $error');
            // إعادة المحاولة بعد فترة
            Future.delayed(const Duration(seconds: 8), () {
              if (mounted) {
                debugPrint('🔄 إعادة محاولة إعداد WebSocket listener للمطعم: ${widget.store.id}');
                _setupWebSocketListener();
              }
            });
          },
          onDone: () {
            debugPrint('⚠️ تم إغلاق stream للمطعم ${widget.store.id} في StoreCard - إعادة إعداد');
            if (mounted) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  _setupWebSocketListener();
                }
              });
            }
          },
        );
        
        debugPrint('✅ تم إعداد الاستماع لتحديثات المطعم في StoreCard: ${widget.store.id}');
      });
      
    } catch (e) {
      debugPrint('❌ خطأ في إعداد الاستماع لتحديثات المطعم في StoreCard: $e');
      // إعادة المحاولة بعد فترة
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _setupWebSocketListener();
        }
      });
    }
  }

  /// التأكد من أن الاشتراك ما زال نشطاً
  void _ensureSubscriptionActive() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        // التحقق من حالة الاشتراك
        if (_businessStatusSubscription == null || 
            _businessStatusSubscription!.isPaused ||
            !_webSocketService.isConnected) {
          debugPrint('⚠️ اشتراك WebSocket غير نشط للمطعم ${widget.store.id} في StoreCard - إعادة إعداد');
          _setupWebSocketListener();
        }
      }
    });
  }

  /// معالجة التحديث الفوري لحالة المطعم
  void _handleBusinessStatusUpdate(Map<String, dynamic> updateData) async {
    try {
      final businessId = updateData['businessId'] as String?;
      final canAcceptOrders = updateData['canAcceptOrders'] as bool?;
      final isBusy = updateData['isBusy'] as bool?;
      final workingHoursUpdated = updateData['workingHoursUpdated'] as bool?;
      final forceStatusRecheck = updateData['forceStatusRecheck'] as bool?;
      final eventType = updateData['eventType'] as String?;

      if (businessId == widget.store.id && mounted) {
        // تحديد نوع التحديث
        String updateType = 'status';
        if (workingHoursUpdated == true || eventType == 'working_hours_update') {
          updateType = 'working_hours';
        }

        debugPrint('🔄 تحديث فوري لحالة المطعم ${widget.store.id} في StoreCard (نوع: $updateType)');
        debugPrint('   - canAcceptOrders: $canAcceptOrders');
        debugPrint('   - isBusy: $isBusy');
        debugPrint('   - workingHoursUpdated: $workingHoursUpdated');
        debugPrint('   - eventType: $eventType');
        debugPrint('   - forceStatusRecheck: $forceStatusRecheck');

        // إعادة تحميل حالة المطعم مع تجاهل الـ cache
        try {
          final newStatus = await _availabilityService.checkRestaurantAvailability(
            widget.store.id, 
            skipCache: true // دائماً تجاهل الـ cache للتحديثات الفورية
          );

          if (mounted) {
            setState(() {
              _availabilityStatus = newStatus;
            });
            
            debugPrint('✅ تم تحديث حالة المطعم ${widget.store.id} فورياً في StoreCard');
            debugPrint('   - متاح: ${_availabilityStatus?.isAvailable}');
            debugPrint('   - ضمن ساعات العمل: ${_availabilityStatus?.isWithinWorkingHours}');
            debugPrint('   - يقبل طلبات: ${_availabilityStatus?.acceptingOrders}');
            debugPrint('   - سبب عدم التوفر: ${_availabilityStatus?.reasonUnavailable}');
          }
        } catch (e) {
          debugPrint('❌ خطأ في إعادة تحميل حالة المطعم: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تحديث حالة المطعم في StoreCard: $e');
    }
  }

  Future<void> _loadAvailabilityStatus() async {
    try {
      final status = await _availabilityService.checkRestaurantAvailability(widget.store.id);
      if (mounted) {
        setState(() {
          _availabilityStatus = status;
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStatus = false;
          // Default to closed/busy status on error
          _availabilityStatus = RestaurantAvailabilityStatus(
            businessId: widget.store.id,
            isAvailable: false,
            acceptingOrders: false,
            isWithinWorkingHours: false,
            workingHours: {},
            checkedAt: DateTime.now(),
            reasonUnavailable: 'مشغول',
          );
        });
      }
    }
  }

  Widget _buildStatusIndicator() {
    if (_isLoadingStatus) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Colors.grey,
          shape: BoxShape.circle,
        ),
      );
    }

    final isWithinWorkingHours = _availabilityStatus?.isWithinWorkingHours ?? true;
    final reasonUnavailable = _availabilityStatus?.reasonUnavailable ?? '';
    
    // نظام الأولويات:
    // 1. مغلق بسبب ساعات العمل (أولوية عالية) → عرض "مغلق"
    if (!isWithinWorkingHours) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4),
          Text(
            'مغلق',
            style: TextStyle(
              fontSize: 11,
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    
    // 2. مفتوح + مشغول → عرض "مشغول"
    if (reasonUnavailable == 'مشغول') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4),
          Text(
            'مشغول',
            style: TextStyle(
              fontSize: 11,
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    
    // 3. مفتوح + متاح → لا نعرض شيء
    return SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesModel>(
      builder: (context, favModel, child) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Stack(
              children: [
                ListTile(
                  title: Text(
                    widget.store.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Location: ${widget.store.location}'),
                      SizedBox(height: 4),
                      _buildStatusIndicator(),
                    ],
                  ),
                  trailing: widget.isCompact ? null : Icon(Icons.info_outline),
                ),
                if (widget.showFavoriteButton)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () async {
                        // ردود فعل حسية فورية
                        HapticFeedback.lightImpact();
                        
                        try {
                          await favModel.toggleStoreFavorite(
                            widget.store.id,
                            widget.store.name,
                            storeImage: '', // StoreModel doesn't have image field
                            storeCategory: 'مطعم', // StoreModel doesn't have category field
                          );
                        } catch (e) {
                          // عرض رسالة خطأ إذا فشلت العملية
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('حدث خطأ في تحديث المفضلة'),
                                backgroundColor: Colors.red,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(
                          favModel.isStoreFavorite(widget.store.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: favModel.isStoreFavorite(widget.store.id)
                              ? Colors.red
                              : Colors.grey,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
