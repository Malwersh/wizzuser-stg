import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/store.dart';
import '../models/favorites_model.dart';
import '../services/restaurant_availability_service.dart';
import '../services/business_status_cache.dart';
import '../services/subscription_manager.dart';

/// Enhanced Restaurant Card with Real-time Availability Status
/// Updates restaurant status based on working hours and accepting orders
class EnhancedRestaurantCard extends StatefulWidget {
  final Store store;
  final Function()? onTap;
  final bool isCompact;
  final bool showFavoriteButton;
  final bool showStatusBadge;

  const EnhancedRestaurantCard({
    super.key,
    required this.store,
    this.onTap,
    this.isCompact = false,
    this.showFavoriteButton = true,
    this.showStatusBadge = true,
  });

  @override
  State<EnhancedRestaurantCard> createState() => _EnhancedRestaurantCardState();
}

class _EnhancedRestaurantCardState extends State<EnhancedRestaurantCard> {
  final RestaurantAvailabilityService _availabilityService = 
      RestaurantAvailabilityService.instance;
  late final SubscriptionManager _subscriptionManager;
  String _subscriberId = '';
  RestaurantAvailabilityStatus? _availabilityStatus;
  bool _isLoadingStatus = true;
  StreamSubscription<Map<String, dynamic>>? _businessStatusSubscription;
  Timer? _statusRefreshTimer; // تحديث صامت دوري من الكاش
  DateTime? _lastUpdateTime; // لمنع التحديثات المتكررة (debouncing)

  @override
  void initState() {
    super.initState();
    _subscriptionManager = SubscriptionManager.instance;
    _subscriberId = _subscriptionManager.generateSubscriberId('restaurant_card_${widget.store.id}');
    _loadAvailabilityStatus();
    _setupManagedSubscription();
    // 🔥 تحسين: تحديث صامت من الكاش كل 2 ثانية (كان 5 ثوانٍ)
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshFromCacheSilently());
  }

  @override
  void didUpdateWidget(EnhancedRestaurantCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload status if store ID changed
    if (oldWidget.store.id != widget.store.id) {
      _businessStatusSubscription?.cancel();
      _subscriberId = _subscriptionManager.generateSubscriberId('restaurant_card_${widget.store.id}');
      _loadAvailabilityStatus();
      _setupManagedSubscription();
    }
  }

  @override
  void dispose() {
    _businessStatusSubscription?.cancel();
    // إلغاء الاشتراك من SubscriptionManager
    _subscriptionManager.unsubscribeFromBusinessStatus(widget.store.id, _subscriberId);
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  /// تحديث الحالة من الكاش بصمت بدون طلبات شبكة أو مؤشرات تحميل
  Future<void> _refreshFromCacheSilently({bool force = false}) async {
    if (!mounted) return;
    
    // Debouncing: منع التحديث إذا تم التحديث خلال آخر ثانية
    final now = DateTime.now();
    if (!force && _lastUpdateTime != null && 
        now.difference(_lastUpdateTime!).inMilliseconds < 1000) {
      return;
    }
    
    try {
      final cached = await BusinessStatusCache.getCachedBusinessStatus(widget.store.id);
      if (cached == null) return;
      final newStatus = RestaurantAvailabilityStatus.fromJson(cached);
      final old = _availabilityStatus;
      final changed = old == null ||
          old.isAvailable != newStatus.isAvailable ||
          old.acceptingOrders != newStatus.acceptingOrders ||
          old.isWithinWorkingHours != newStatus.isWithinWorkingHours ||
          old.reasonUnavailable != newStatus.reasonUnavailable;
      if (changed && mounted) {
        setState(() {
          _availabilityStatus = newStatus;
          _isLoadingStatus = false;
          _lastUpdateTime = now; // تسجيل وقت التحديث
        });
      }
    } catch (_) {}
  }

  /// إعداد الاستماع لتحديثات WebSocket باستخدام SubscriptionManager
  void _setupManagedSubscription() {
    try {
      // إلغاء الاشتراك السابق إذا وُجد
      _businessStatusSubscription?.cancel();
      
      debugPrint('🚀 إعداد اشتراك جديد للمطعم ${widget.store.id}');
      
      // الاشتراك في تحديثات حالة هذا المطعم باستخدام SubscriptionManager
      _businessStatusSubscription = _subscriptionManager
          .subscribeToRestaurantStatus(widget.store.id)
          .listen(
        (updateData) {
          if (mounted) {
            debugPrint('🎯 CARD: استلم تحديث للمطعم ${widget.store.id} - source: ${updateData['source']}, isAvailable: ${updateData['isAvailable']}, acceptingOrders: ${updateData['acceptingOrders']}');
            debugPrint('📋 CARD: بيانات كاملة: $updateData');
            _handleBusinessStatusUpdate(updateData);
          } else {
            debugPrint('⚠️ Widget غير mounted - تجاهل التحديث للمطعم ${widget.store.id}');
          }
        },
        onError: (error) {
          debugPrint('❌ خطأ في الاستماع لتحديثات المطعم ${widget.store.id}: $error');
          // إعادة المحاولة بعد فترة قصيرة
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              debugPrint('🔄 إعادة محاولة الاشتراك للمطعم ${widget.store.id}');
              _setupManagedSubscription();
            }
          });
        },
        onDone: () {
          debugPrint('⚠️ تم إغلاق stream للمطعم ${widget.store.id}');
          // إعادة الاشتراك إذا كان الـ widget ما زال mounted
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              debugPrint('🔄 إعادة الاشتراك التلقائي للمطعم ${widget.store.id}');
              _setupManagedSubscription();
            }
          });
        },
      );
      
      debugPrint('✅ تم إعداد الاستماع لتحديثات المطعم عبر SubscriptionManager: ${widget.store.id}');
    } catch (e) {
      debugPrint('❌ خطأ في إعداد الاستماع لتحديثات المطعم: $e');
      // محاولة مرة أخرى بعد فترة
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _setupManagedSubscription();
        }
      });
    }
  }

  /// معالجة التحديث الفوري لحالة المطعم
  void _handleBusinessStatusUpdate(Map<String, dynamic> updateData) async {
    debugPrint('⚙️ CARD: بدء معالجة التحديث للمطعم ${widget.store.id}');
    try {
      final businessId = updateData['businessId'] as String?;
      // توحيد المفاتيح القادمة من WebSocket أو polling
      final canAcceptOrders = (updateData['canAcceptOrders'] as bool?) ?? (updateData['acceptingOrders'] as bool?);
      final isBusy = updateData['isBusy'] as bool?;
      final status = updateData['status'] as String?;
      final statusMessage = updateData['statusMessage'] as String?;
      final isAvailableDirect = updateData['isAvailable'] as bool?; // من polling
      final source = updateData['source'] as String?; // 'polling' أو 'websocket'
      
      // معالجة تحديثات ساعات العمل الجديدة
      final workingHours = updateData['workingHours'] as Map<String, dynamic>?;
      final workingHoursUpdated = updateData['workingHoursUpdated'] as bool?;
      final forceStatusRecheck = updateData['forceStatusRecheck'] as bool?;
      final dayUpdated = updateData['dayUpdated'] as String?;
      final isClosedToday = updateData['isClosed'] as bool?;
      final isDayClosed = updateData['isDayClosed'] as bool?;

      if (businessId == widget.store.id && mounted) {
        debugPrint('🔄 تحديث فوري لحالة المطعم ${widget.store.id} في البطاقة');
        debugPrint('   - canAcceptOrders: $canAcceptOrders');
        debugPrint('   - isBusy: $isBusy');
        debugPrint('   - status: $status');
        debugPrint('   - statusMessage: $statusMessage');
        debugPrint('   - workingHoursUpdated: $workingHoursUpdated');
        debugPrint('   - workingHours: $workingHours');
        debugPrint('   - forceStatusRecheck: $forceStatusRecheck');
        debugPrint('   - dayUpdated: $dayUpdated');
        debugPrint('   - isClosedToday: $isClosedToday');
        debugPrint('   - isDayClosed: $isDayClosed');
        debugPrint('   - Current state: ${_availabilityStatus?.isAvailable} -> $canAcceptOrders');

        // تجنب مسح الكاش إذا كان التحديث من polling لأنه يحتوي على أحدث القيم بالفعل
        if (source != 'polling') {
          await BusinessStatusCache.forceInvalidateBusinessStatus(widget.store.id);
        }

        // تحديد ساعات العمل الجديدة أو الحالية
        Map<String, dynamic> newWorkingHours = {};
        
        // 🔥 أولوية للساعات القادمة من التحديث
        if (workingHours != null && workingHours.isNotEmpty) {
          newWorkingHours = Map<String, dynamic>.from(workingHours);
          debugPrint('⏰ استخدام ساعات العمل من التحديث: $newWorkingHours');
        } else if (_availabilityStatus?.workingHours != null) {
          newWorkingHours = _availabilityStatus!.workingHours;
          debugPrint('⏰ استخدام ساعات العمل المحفوظة: $newWorkingHours');
        } else {
          debugPrint('⚠️ لا توجد ساعات عمل متاحة');
        }

        // 🔥 فحص خاص للحالة عند تحديث ساعات العمل
        bool newIsWithinWorkingHours = true;
        
        // 🔥 استخدام القيمة من API كأولوية (محسوبة بـ timezone المطعم)
        final isWithinWorkingHoursFromAPI = updateData['isWithinWorkingHours'] as bool?;
        
        if (isWithinWorkingHoursFromAPI != null) {
          // استخدام القيمة من Backend (أدق لأنها تستخدم timezone المطعم)
          newIsWithinWorkingHours = isWithinWorkingHoursFromAPI;
          debugPrint('✅ استخدام isWithinWorkingHours من API: $newIsWithinWorkingHours');
        } else if (forceStatusRecheck == true || workingHoursUpdated == true) {
          // إعادة فحص شاملة لساعات العمل (fallback فقط)
          newIsWithinWorkingHours = _checkIsWithinWorkingHours(newWorkingHours);
          
          // 🚨 إذا كان اليوم المحدث هو اليوم الحالي وتم إغلاقه، فالمطعم مغلق فوراً
          if (dayUpdated != null && (isClosedToday == true || isDayClosed == true)) {
            final now = DateTime.now();
            final currentDayName = _getDayName(now.weekday);
            if (dayUpdated.toLowerCase() == currentDayName.toLowerCase()) {
              newIsWithinWorkingHours = false;
              debugPrint('🚫 تم إغلاق المطعم فوراً لليوم الحالي: $dayUpdated');
            }
          }
          
          debugPrint('⚡ إعادة فحص ساعات العمل (local): $newIsWithinWorkingHours');
        } else {
          // fallback: حساب محلي فقط إذا لم تتوفر قيمة من API
          newIsWithinWorkingHours = _checkIsWithinWorkingHours(newWorkingHours);
          debugPrint('⚠️ حساب محلي (قد يكون غير دقيق بسبب timezone): $newIsWithinWorkingHours');
        }
        
        // إنشاء حالة جديدة مع ضمان التغيير
        final previousAvailable = _availabilityStatus?.isAvailable ?? true;
        final previousWorkingHours = _availabilityStatus?.isWithinWorkingHours ?? true;
        final newAvailable = (canAcceptOrders ?? (_availabilityStatus?.acceptingOrders ?? true));
        
        // تحويل Map<String, dynamic> إلى Map<String, WorkingHours?>
        final Map<String, WorkingHours?> convertedWorkingHours = {};
        
        if (newWorkingHours.isNotEmpty) {
          newWorkingHours.forEach((day, hoursData) {
            if (hoursData is Map<String, dynamic> && 
                hoursData.containsKey('open') && 
                hoursData.containsKey('close')) {
              convertedWorkingHours[day] = WorkingHours(
                opening: hoursData['open']?.toString() ?? '',
                closing: hoursData['close']?.toString() ?? '',
                isClosed: hoursData['isClosed'] == true, // 🔥 تمرير isClosed من البيانات
              );
            } else {
              convertedWorkingHours[day] = null;
            }
          });
        }
        
        // 🔥 FIX: استخدام isAvailableDirect من Backend مباشرة
        // isAvailableDirect يتضمن بالفعل فحص working hours بـ timezone صحيح
        // لا نحتاج لإعادة فحص working hours محلياً
        final effectiveIsAvailable = (isAvailableDirect != null)
            ? isAvailableDirect  // 🎯 استخدام قيمة Backend مباشرة (تتضمن all checks)
            : (newAvailable && newIsWithinWorkingHours); // fallback للحساب المحلي

        debugPrint('🎯 CARD: حساب effectiveIsAvailable:');
        debugPrint('   - isAvailableDirect (from Backend): $isAvailableDirect');
        debugPrint('   - newIsWithinWorkingHours (local calc): $newIsWithinWorkingHours');
        debugPrint('   - effectiveIsAvailable (final): $effectiveIsAvailable');

        final updatedStatus = RestaurantAvailabilityStatus(
          businessId: widget.store.id,
          isAvailable: effectiveIsAvailable,  // يعتمد على الحساب المحلي لساعات العمل
          acceptingOrders: newAvailable,
          isWithinWorkingHours: newIsWithinWorkingHours, // 🔥 استخدام الحساب المحلي فقط (أدق من API)
          workingHours: convertedWorkingHours,
          checkedAt: DateTime.now(),
          reasonUnavailable: _getReasonFromStatus(isBusy, canAcceptOrders, statusMessage),
        );
        
        // التحديث الفوري مع إجبار rebuild
        if (mounted) {
          setState(() {
            _availabilityStatus = updatedStatus;
            _isLoadingStatus = false; // التأكد من عدم وجود حالة تحميل
          });
          
          debugPrint('⚡ تم تحديث فوري للحالة:');
          debugPrint('   - من: $previousAvailable إلى: $newAvailable');
          debugPrint('   - ساعات العمل من: $previousWorkingHours إلى: $newIsWithinWorkingHours');
          debugPrint('   - السبب: ${updatedStatus.reasonUnavailable}');
          debugPrint('   - Widget mounted: $mounted');
          
          // 🔥 قراءة فورية من Cache بعد التحديث لضمان الدقة
          debugPrint('✅ CARD: تم تحديث الحالة setState - isAvailable: ${updatedStatus.isAvailable}, mounted: $mounted');
          // قراءة فورية من الكاش بعد التحديث لضمان مزامنة أي تغييرات خارجية (force لتجاوز الـ debounce)
          debugPrint('🔄 CARD: استدعاء _refreshFromCacheSilently مع force=true');
          _refreshFromCacheSilently(force: true);
          
          // إجبار rebuild إضافي بعد فترة قصيرة للتأكد
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              setState(() {});
              debugPrint('🔄 إعادة build إضافية للتأكد من التحديث');
            }
          });
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تحديث حالة المطعم: $e');
    }
  }

  /// تحديد سبب عدم التوفر بناءً على حالة المطعم
  String _getReasonFromStatus(bool? isBusy, bool? canAcceptOrders, String? statusMessage) {
    if (isBusy == true) {
      return 'مشغول';
    }
    if (canAcceptOrders == false) {
      return 'لا يستقبل طلبات';
    }
    if (statusMessage != null && statusMessage.isNotEmpty) {
      return statusMessage;
    }
    return '';
  }

  /// فحص ما إذا كان المطعم مفتوح حسب ساعات العمل الحالية
  bool _checkIsWithinWorkingHours(Map<String, dynamic> workingHours) {
    // 🔍 Debug: طباعة workingHours المُمرّرة
    debugPrint('🔍 _checkIsWithinWorkingHours called with: $workingHours');
    debugPrint('🔍 workingHours.keys: ${workingHours.keys.toList()}');
    debugPrint('🔍 workingHours.isEmpty: ${workingHours.isEmpty}');
    
    if (workingHours.isEmpty) {
      debugPrint('⚠️ workingHours فارغ - افتراض مفتوح');
      return true; // إذا لم توجد ساعات عمل، افتراضياً مفتوح
    }
    
    try {
      final now = DateTime.now();
      final weekday = now.weekday; // 1 = Monday, 7 = Sunday
      
      // 🔥 FIX: Get day name using simple switch statement (capitalized to match API)
      String getDayName(int weekday) {
        switch (weekday) {
          case DateTime.monday: return 'Monday';
          case DateTime.tuesday: return 'Tuesday';
          case DateTime.wednesday: return 'Wednesday';
          case DateTime.thursday: return 'Thursday';
          case DateTime.friday: return 'Friday';
          case DateTime.saturday: return 'Saturday';
          case DateTime.sunday: return 'Sunday';
          default: return 'Monday';
        }
      }
      
      final dayName = getDayName(weekday);
      
      // 🔍 البحث بأسماء الأيام المختلفة: بالأحرف الصغيرة والكبيرة والإنجليزية
      Map<String, dynamic>? todayHours;
      
      // 🔥 FIX: Normalize working hours keys to lowercase for case-insensitive search
      final normalizedWorkingHours = <String, dynamic>{};
      workingHours.forEach((key, value) {
        final normalizedKey = key.toLowerCase();
        
        // 🔥 تحويل WorkingHours object إلى Map قبل التخزين
        if (value is Map) {
          normalizedWorkingHours[normalizedKey] = value;
        } else if (value != null) {
          // تحويل WorkingHours object إلى Map باستخدام regex
          try {
            final valueString = value.toString();
            final openingMatch = RegExp(r'opening:\s*([^,\)]+)').firstMatch(valueString);
            final closingMatch = RegExp(r'closing:\s*([^,\)]+)').firstMatch(valueString);
            final isClosedMatch = RegExp(r'isClosed:\s*(true|false)').firstMatch(valueString);
            
            normalizedWorkingHours[normalizedKey] = {
              'opening': openingMatch?.group(1)?.trim() ?? '09:00',
              'closing': closingMatch?.group(1)?.trim() ?? '23:58',
              'isClosed': isClosedMatch?.group(1) == 'true',
            };
          } catch (e) {
            debugPrint('❌ فشل تحويل WorkingHours لـ "$key": $e');
          }
        }
      });
      
      // قائمة بجميع الاحتمالات لاسم اليوم (كلها lowercase بعد التطبيع)
      final possibleDayNames = [
        dayName.toLowerCase(),  // Convert to lowercase for normalized search
      ];
      
      // البحث بجميع الاحتمالات (case-insensitive)
      for (final possibleName in possibleDayNames) {
        if (normalizedWorkingHours.containsKey(possibleName)) {
          final hours = normalizedWorkingHours[possibleName];
          if (hours is Map) {
            todayHours = Map<String, dynamic>.from(hours);
            debugPrint('✅ تم العثور على ساعات عمل لليوم: $possibleName');
            break;
          }
        }
      }
      
      // إذا لم توجد ساعات عمل لهذا اليوم، افتراضياً مغلق
      if (todayHours == null) {
        debugPrint('⚠️ لا توجد ساعات عمل لليوم $dayName - افتراض مغلق');
        return false;
      }
      
      // 🔥 أولوية عالية: فحص إذا كان المطعم مغلق اليوم (isClosed=true)
      final isClosed = todayHours['isClosed'] as bool?;
      if (isClosed == true) {
        debugPrint('🚫 المطعم مغلق بالكامل اليوم: $dayName (isClosed=true)');
        return false;
      }
      
      // فحص ساعات الفتح والإغلاق فقط إذا كان المطعم غير مغلق
      final openTime = todayHours['open'] as String? ?? todayHours['opening'] as String?;
      final closeTime = todayHours['close'] as String? ?? todayHours['closing'] as String?;
      
      // إذا كان isClosed=false ولكن لا توجد ساعات محددة، افتراضياً مفتوح
      if (openTime == null || closeTime == null || 
          openTime.isEmpty || closeTime.isEmpty ||
          openTime == 'none' || closeTime == 'none') {
        debugPrint('⚠️ ساعات العمل غير محددة لليوم $dayName ولكن المطعم غير مغلق - افتراض مفتوح');
        return true;
      }
      
      final currentTime = TimeOfDay.fromDateTime(now);
      final parsedOpenTime = _parseTimeString(openTime);
      final parsedCloseTime = _parseTimeString(closeTime);
      
      if (parsedOpenTime == null || parsedCloseTime == null) {
        debugPrint('⚠️ خطأ في تحليل ساعات العمل - افتراض مفتوح');
        return true;
      }
      
      // تحويل الأوقات إلى دقائق للمقارنة
      final currentMinutes = currentTime.hour * 60 + currentTime.minute;
      final openMinutes = parsedOpenTime.hour * 60 + parsedOpenTime.minute;
      final closeMinutes = parsedCloseTime.hour * 60 + parsedCloseTime.minute;
      
      bool isOpen;
      if (closeMinutes < openMinutes) {
        // المطعم مفتوح خلال منتصف الليل (مثل: 22:00 - 02:00)
        isOpen = currentMinutes >= openMinutes || currentMinutes <= closeMinutes;
      } else {
        // ساعات عمل عادية (مثل: 09:00 - 22:00)
        isOpen = currentMinutes >= openMinutes && currentMinutes <= closeMinutes;
      }
      
      debugPrint('⏰ فحص ساعات العمل للمطعم:');
      debugPrint('   - اليوم: $dayName');
      debugPrint('   - الوقت الحالي: ${currentTime.format(context)}');
      debugPrint('   - ساعات العمل: $openTime - $closeTime');
      debugPrint('   - مفتوح: $isOpen');
      
      return isOpen;
    } catch (e) {
      debugPrint('❌ خطأ في فحص ساعات العمل: $e');
      return true; // افتراض مفتوح عند الخطأ
    }
  }

  /// تحويل رقم اليوم إلى اسم اليوم بالإنجليزية (بأحرف كبيرة تطابق تنسيق API)
  String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }

  /// تحليل نص الوقت إلى TimeOfDay
  TimeOfDay? _parseTimeString(String timeString) {
    try {
      final parts = timeString.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحليل الوقت: $timeString - $e');
    }
    return null;
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
          // Default to available status on error - يفضل إظهار المطعم كمتاح بدلاً من مغلق عند فشل التحميل
          _availabilityStatus = RestaurantAvailabilityStatus(
            businessId: widget.store.id,
            isAvailable: true, // افتراضياً متاح
            acceptingOrders: true, // افتراضياً يقبل طلبات
            isWithinWorkingHours: true, // افتراضياً مفتوح
            workingHours: {},
            checkedAt: DateTime.now(),
            reasonUnavailable: '', // لا يوجد سبب لعدم التوفر
          );
        });
        debugPrint('⚠️ فشل تحميل حالة المطعم ${widget.store.id}، استخدام حالة افتراضية متاحة: $e');
      }
    }
  }

  Widget _buildStatusBadge() {
    if (!widget.showStatusBadge) return SizedBox.shrink();
    
    if (_isLoadingStatus) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 4),
            Text(
              'يحدث...',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final isWithinWorkingHours = _availabilityStatus?.isWithinWorkingHours ?? false;
    final isAvailable = _availabilityStatus?.isAvailable ?? false;
    final reasonUnavailable = _availabilityStatus?.reasonUnavailable;
    
    debugPrint('🔍 BADGE: isAvailable=$isAvailable, isWithinWorkingHours=$isWithinWorkingHours');
    
    // تطبيق منطق الأولويات:
    // 1. أولوية عالية: مغلق بسبب ساعات العمل
    if (!isWithinWorkingHours) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800).withOpacity(0.1), // برتقالي
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF9800).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.access_time,
              size: 10,
              color: const Color(0xFFFF9800),
            ),
            const SizedBox(width: 4),
            Text(
              'مغلق',
              style: TextStyle(
                fontSize: 10,
                color: const Color(0xFFFF9800),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    // 2. أولوية متوسطة: مفتوح + متاح → لا يظهر شيء
    
    // 3. أولوية منخفضة: مفتوح + مشغول
    if (reasonUnavailable == 'مشغول') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5722).withOpacity(0.1), // Deep orange/red
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF5722).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block,
              size: 10,
              color: const Color(0xFFFF5722),
            ),
            const SizedBox(width: 4),
            Text(
              'مشغول',
              style: TextStyle(
                fontSize: 10,
                color: const Color(0xFFFF5722),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    // Don't show any status badge for other states to avoid redundancy
    return SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCompact) {
      return _buildCompactCard();
    } else {
      return _buildFullCard();
    }
  }

  Widget _buildCompactCard() {
    return Consumer<FavoritesModel>(
      builder: (context, favModel, child) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Restaurant image with favorite button
                Stack(
                  children: [
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        color: Colors.grey[200],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: widget.store.image.isNotEmpty && widget.store.image.contains('://')
                            ? Image.network(
                                widget.store.image,
                                width: double.infinity,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.restaurant, size: 40, color: Colors.grey),
                                  );
                                },
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.restaurant, size: 40, color: Colors.grey),
                              ),
                      ),
                    ),
                    // Favorite button
                    if (widget.showFavoriteButton)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            try {
                              await favModel.toggleStoreFavorite(
                                widget.store.id,
                                widget.store.name,
                                storeImage: widget.store.image,
                                storeCategory: widget.store.category,
                              );
                            } catch (e) {
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
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 3,
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
                // Restaurant details
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.store.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.black, // نص أسود واضح
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.store.category ?? 'مطعم',
                                style: const TextStyle(
                                  color: Color(0xFF666666), // لون ثابت بدلاً من Colors.grey[600]
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _buildStatusBadge(),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // التقييم والوقت والمسافة على خط واحد
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 13),
                            const SizedBox(width: 2),
                            Text(
                              widget.store.rating, 
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.access_time, color: Color(0xFF666666), size: 13),
                            const SizedBox(width: 2),
                            Text(
                              widget.store.time,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF666666),
                              ),
                            ),
                            if (widget.store.distance.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.location_on, color: Color(0xFF666666), size: 13),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  widget.store.distance,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF666666),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // رسوم التوصيل
                        if (widget.store.fee.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                'رسوم التوصيل: ',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF666666),
                                ),
                              ),
                              Text(
                                widget.store.fee,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF666666),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
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

  Widget _buildFullCard() {
    return Consumer<FavoritesModel>(
      builder: (context, favModel, child) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Restaurant image
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[200],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: widget.store.image.isNotEmpty && widget.store.image.contains('://')
                          ? Image.network(
                              widget.store.image,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.restaurant, size: 30, color: Colors.grey),
                                );
                              },
                            )
                          : Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.restaurant, size: 30, color: Colors.grey),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Restaurant details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.store.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black, // نص أسود على الخلفية البيضاء
                                ),
                              ),
                            ),
                            _buildStatusBadge(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.store.category ?? 'مطعم',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF666666), // رمادي ثابت أكثر وضوحاً
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              widget.store.rating,
                              style: const TextStyle(
                                color: Colors.black, // نص أسود واضح للتقييم
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                            const SizedBox(width: 4),
                            Text(
                              widget.store.time,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            if (widget.store.distance.isNotEmpty) ...[
                              const SizedBox(width: 16),
                              Icon(Icons.location_on, color: Colors.grey[600], size: 16),
                              const SizedBox(width: 4),
                              Text(
                                widget.store.distance,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Favorite button
                  if (widget.showFavoriteButton)
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        try {
                          await favModel.toggleStoreFavorite(
                            widget.store.id,
                            widget.store.name,
                            storeImage: widget.store.image,
                            storeCategory: widget.store.category,
                          );
                        } catch (e) {
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
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          favModel.isStoreFavorite(widget.store.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: favModel.isStoreFavorite(widget.store.id)
                              ? Colors.red
                              : Colors.grey,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
