import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'business_status_batch_service.dart';
import 'business_status_cache.dart';

/// خدمة polling صامتة لتحديث حالات المطاعم في الخلفية بدون إظهار أي مؤشرات تحميل
class StatusPollingService {
  StatusPollingService._();
  static final StatusPollingService instance = StatusPollingService._();

  final Set<String> _watchedIds = <String>{};
  Timer? _timer;
  
  // Stream للإشعار بتحديثات الحالة بعد كل polling ناجح
  final StreamController<Map<String, dynamic>> _statusUpdateController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  /// الاستماع لأحداث تحديث الحالة من polling
  Stream<Map<String, dynamic>> get statusUpdates => _statusUpdateController.stream;

  // الإعدادات
  Duration baseInterval = const Duration(seconds: 15); // 🔥 تحسين: تقليل من 30 إلى 15 ثانية
  int jitterSeconds = 5; // 0..5 ثواني
  bool _running = false;
  int _consecutiveErrors = 0;

  void updateWatchedIds(Iterable<String> ids) {
    _watchedIds
      ..clear()
      ..addAll(ids.where((e) => e.isNotEmpty));
    debugPrint('👀 StatusPolling: updateWatchedIds called - IDs count: ${_watchedIds.length}');
    debugPrint('📝 StatusPolling: Watched IDs: ${_watchedIds.take(5).toList()}... (showing first 5)');
    debugPrint('👀 Watching ${_watchedIds.length} businesses for status polling');
    // تنفيذ جلب فوري بعد تحديث القائمة إذا كانت الخدمة تعمل
    if (_running && _watchedIds.isNotEmpty) {
      debugPrint('⚡ StatusPolling: Triggering immediate fetch since service is running');
      _forceImmediateFetch();
    } else {
      debugPrint('⚠️ StatusPolling: NOT triggering fetch - running=$_running, ids.length=${_watchedIds.length}');
    }
  }

  void start() {
    if (_running) {
      debugPrint('⚠️ StatusPolling: start() called but already running');
      return;
    }
    _running = true;
    debugPrint('🚀 StatusPolling: start() called - _running set to true');
    debugPrint('📊 StatusPolling: Current watched IDs count: ${_watchedIds.length}');
    // تنظيف الكاش القديم (تنسيق قديم غير متوافق) مرة واحدة عند البدء
    BusinessStatusCache.clearAllBusinessStatusCache();
    // تنفيذ جلب فوري عند البدء لضمان تحديث خلال < 30-45 ثانية
    debugPrint('⚡ StatusPolling: immediate fetch on start');
    _forceImmediateFetch();
    _scheduleNextTick();
    debugPrint('🜢 Status polling started - next tick scheduled');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    debugPrint('⏹️ Status polling stopped');
  }
  
  void dispose() {
    stop();
    _statusUpdateController.close();
  }

  void _scheduleNextTick() {
    final rand = Random();
    final jitter = Duration(seconds: rand.nextInt(jitterSeconds + 1));
    // backoff بسيط عند الأخطاء المتتالية (حد أقصى 4x)
    final backoffSteps = _consecutiveErrors.clamp(0, 2);
    final backoffFactor = 1 << backoffSteps;
    final interval = Duration(milliseconds: baseInterval.inMilliseconds * backoffFactor) + jitter;

    _timer?.cancel();
    _timer = Timer(interval, _tick);
  }

  Future<void> _tick() async {
    debugPrint('🔔 StatusPolling: _tick() called - _watchedIds.length=${_watchedIds.length}');
    if (_watchedIds.isEmpty) {
      debugPrint('⚠️ StatusPolling: Skipping tick - no watched IDs yet');
      _scheduleNextTick();
      return;
    }

    try {
      // تقسيم إلى دفعات صغيرة لتقليل الحمل (حد أقصى 50 معرف في الدفعة)
      const batchSize = 50;
      final ids = _watchedIds.toList();
      debugPrint('📡 Polling tick: totalIds=${ids.length}, batchSize=$batchSize');
      for (var i = 0; i < ids.length; i += batchSize) {
        final end = (i + batchSize) > ids.length ? ids.length : (i + batchSize);
        final chunk = ids.sublist(i, end);
        debugPrint('📦 Fetching batch ${i ~/ batchSize + 1} IDs=${chunk.length}');
        final map = await BusinessStatusBatchService.fetchStatuses(chunk);
        debugPrint('✅ Batch received statuses=${map.length}');
        // حفظ النتائج في الكاش المحلي
        for (final entry in map.entries) {
          final id = entry.key;
          final status = (entry.value as Map).cast<String, dynamic>();
          // تحويل workingHoursToday (قد تكون null أو Map) إلى خريطة متوافقة مع RestaurantAvailabilityStatus
          
          // 🔥 FIX: استخدام اليوم من Backend بدلاً من وقت الجهاز المحلي
          final currentWeekday = status['currentWeekday'] as String?; // اليوم الحالي من Backend
          final weekdayName = currentWeekday ?? _englishWeekday(DateTime.now().weekday); // fallback للوقت المحلي فقط إذا لم يُرسل Backend
          
          Map<String, dynamic> workingHoursToday = {};
          if (status['workingHoursToday'] is Map) {
            final raw = status['workingHoursToday'] as Map;
            // توقع وجود مفاتيح open/close/isClosed أو opening/closing
            final open = raw['open'] ?? raw['opening'] ?? '';
            final close = raw['close'] ?? raw['closing'] ?? '';
            final isClosed = raw['isClosed'] == true || raw['closed'] == true;
            workingHoursToday = {
              'opening': open?.toString() ?? '',
              'closing': close?.toString() ?? '',
              'isClosed': isClosed,
            };
          }

          final isClosedFlag = status['isClosed'] == true;
          final acceptingOrders = status['acceptingOrders'] == true;
          final isAvailableNow = status['isAvailableNow'] == true;
          final isWithinWorkingHours = status['isWithinWorkingHours'] == true; // 🔥 من Backend
          final currentStatus = status['currentStatus'] ?? '';

          await BusinessStatusCache.cacheBusinessStatus(id, {
            'businessId': id,
            'isAvailable': isAvailableNow, // 🔥 استخدام isAvailableNow مباشرة (يحتوي على كل الشروط)
            'acceptingOrders': acceptingOrders,
            'isWithinWorkingHours': isWithinWorkingHours, // 🔥 من Backend (محسوب بـ timezone المطعم)
            'isAvailableNow': isAvailableNow,
            'isClosed': isClosedFlag,
            'currentStatus': currentStatus,
            'currentWeekday': currentWeekday, // 🔥 اليوم الحالي (Tuesday, Monday, etc)
            'workingHours': { weekdayName: workingHoursToday.isNotEmpty ? workingHoursToday : null },
            'checkedAt': DateTime.now().millisecondsSinceEpoch,
            'reasonUnavailable': _reasonFromStatus(status, isClosedFlag, acceptingOrders),
          });
          
          // 📡 بث حدث التحديث للمشتركين (بدون WebSocket)
          if (!_statusUpdateController.isClosed) {
            final eventData = {
              'businessId': id,
              'isAvailable': isAvailableNow, // 🔥 استخدام isAvailableNow مباشرة
              'acceptingOrders': acceptingOrders,
              'isWithinWorkingHours': isWithinWorkingHours, // 🔥 من Backend
              'isAvailableNow': isAvailableNow,
              'isClosed': isClosedFlag,
              'currentStatus': currentStatus,
              'currentWeekday': currentWeekday, // 🔥 اليوم الحالي من Backend
              // تضمين ساعات اليوم الحالية في حدث البث لكي تصل للبطاقة مباشرة
              'workingHours': {
                weekdayName: workingHoursToday.isNotEmpty ? workingHoursToday : null
              },
              'timestamp': DateTime.now().toIso8601String(),
              'source': 'polling',
            };
            if (workingHoursToday.isNotEmpty) {
              debugPrint('🕒 StatusPolling: تضمين workingHours في الحدث للمطعم $id - اليوم=$weekdayName مفاتيح=${workingHoursToday.keys.toList()}');
            } else {
              debugPrint('⚠️ StatusPolling: لا توجد workingHoursToday صالحة للمطعم $id - اليوم=$weekdayName سيتم إرسال null');
            }
            debugPrint('🔊 StatusPolling: بث حدث للمطعم $id - isAvailableNow=$isAvailableNow, isClosed=$isClosedFlag, currentStatus=$currentStatus, acceptingOrders=$acceptingOrders');
            _statusUpdateController.add(eventData);
          } else {
            debugPrint('⚠️ StatusPolling: stream controller مغلق للمطعم $id');
          }
        }
      }

      _consecutiveErrors = 0;
    } catch (e) {
      debugPrint('❌ Status polling error: $e');
      _consecutiveErrors += 1;
    } finally {
      if (_running) _scheduleNextTick();
    }
  }
  String _reasonFromStatus(Map<String, dynamic> status, bool isClosedFlag, bool acceptingOrders) {
    if (isClosedFlag) return 'مغلق';
    if (!acceptingOrders) return 'مشغول';
    return '';
  }

  String _englishWeekday(int weekday) {
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

  void _forceImmediateFetch() {
    // تنفيذ جلب فوري بدون انتظار المؤقت الحالي
    _timer?.cancel();
    Future.microtask(() => _tick());
  }

  /// واجهة عامة لاستدعاء جلب فوري من خارج الخدمة
  void forceImmediateFetch() => _forceImmediateFetch();
}
