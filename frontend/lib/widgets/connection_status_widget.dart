// lib/widgets/connection_status_widget.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/app_colors.dart';
import '../services/websocket_service.dart';
import 'dart:async';
import '../config/api_config.dart';

class ConnectionStatusWidget extends StatefulWidget {
  final bool showDetailed;
  final bool compact;
  final EdgeInsets? padding;

  const ConnectionStatusWidget({
    super.key,
    this.showDetailed = false,
    this.compact = false,
    this.padding,
  });

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget> {
  final WebSocketService _wsService = WebSocketService();
  late Timer _updateTimer;
  late StreamSubscription _connectionSubscription;
  DateTime _lastUpdate = DateTime.now();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    
    // إعداد الحالة الأولية بناءً على حالة الشبكة وليس WebSocket فقط
    _checkNetworkConnection();
    
    // الاستماع لتغييرات حالة الاتصال
    _connectionSubscription = _wsService.connectionStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
          _lastUpdate = DateTime.now();
        });
      }
    });
    
    // تحديث كل ثانية لعرض آخر وقت تحديث
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // إذا كان WebSocket غير متصل، تحقق من حالة الشبكة
          if (!_wsService.isConnected) {
            _checkNetworkConnection();
          } else {
            _isConnected = _wsService.isConnected;
          }
          _lastUpdate = DateTime.now();
        });
      }
    });
  }

  // دالة للتحقق من حالة الشبكة
  void _checkNetworkConnection() async {
    try {
      // التحقق من إمكانية الوصول للباك إند عبر health endpoint
      final response = await http.get(
        Uri.parse(ApiConfig.buildUrl(ApiConfig.healthEndpoint)),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (mounted) {
        setState(() {
          // إذا كان health endpoint يعمل، فالاتصال جيد
          _isConnected = response.statusCode == 200;
          _lastUpdate = DateTime.now();
        });
      }
    } catch (e) {
      // إذا فشل health endpoint، جرب endpoint آخر موجود
      try {
        final fallbackResponse = await http.get(
          Uri.parse(ApiConfig.buildUrl(ApiConfig.businessesEndpoint)),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 3));
        
        if (mounted) {
          setState(() {
            _isConnected = fallbackResponse.statusCode == 200 || fallbackResponse.statusCode == 401;
            _lastUpdate = DateTime.now();
          });
        }
      } catch (e2) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _lastUpdate = DateTime.now();
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _updateTimer.cancel();
    _connectionSubscription.cancel();
    super.dispose();
  }

  String _formatTimeSince(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}ث';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}د';
    } else {
      return '${difference.inHours}س';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showDetailed) {
      return _buildDetailedStatus();
    } else if (widget.compact) {
      return _buildCompactStatus();
    } else {
      return _buildSimpleStatus();
    }
  }

  Widget _buildSimpleStatus() {
    return Container(
      padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isConnected 
            ? Colors.green.withValues(alpha: 0.1)
            : AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected ? Colors.green : AppColors.primary,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected ? Icons.wifi : Icons.refresh,
            size: 16,
            color: _isConnected ? Colors.green : AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            _isConnected ? 'متصل' : 'يعمل',
            style: TextStyle(
              fontSize: 12,
              color: _isConnected ? Colors.green : AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStatus() {
    return Container(
      padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isConnected ? 'متصل' : 'يعمل',
            style: TextStyle(
              fontSize: 11,
              color: _isConnected ? Colors.green : AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStatus() {
    return Container(
      padding: widget.padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _isConnected ? Icons.cloud_done : Icons.cloud_off,
                size: 20,
                color: _isConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                _isConnected ? 'متصل بالخادم' : 'التطبيق يعمل بشكل طبيعي',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _isConnected ? Colors.green : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isConnected 
                ? '🟢 التحديثات مباشرة من الخادم'
                : '🟡 البيانات تتحدث تلقائياً كل 30 ثانية',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            'آخر تحديث: ${_formatTimeSince(_lastUpdate)} مضت',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// Widget للاستخدام في AppBar
class ConnectionStatusIcon extends StatefulWidget {
  const ConnectionStatusIcon({super.key});

  @override
  State<ConnectionStatusIcon> createState() => _ConnectionStatusIconState();
}

class _ConnectionStatusIconState extends State<ConnectionStatusIcon> {
  final WebSocketService _wsService = WebSocketService();
  late StreamSubscription _connectionSubscription;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    
    // إعداد الحالة الأولية
    _isConnected = _wsService.isConnected;
    
    // الاستماع لتغييرات حالة الاتصال
    _connectionSubscription = _wsService.connectionStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // التحقق من أن الـ widget ما زال mounted قبل عرض الـ dialog
        if (!mounted) return;
        
        // عرض dialog مع تفاصيل الاتصال
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حالة الاتصال'),
            content: ConnectionStatusWidget(showDetailed: true),
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
        padding: const EdgeInsets.all(8),
        child: Icon(
          _isConnected ? Icons.wifi : Icons.wifi_off,
          color: _isConnected ? AppColors.primary : AppColors.primaryDark,
          size: 20,
        ),
      ),
    );
  }
}

// Widget للاستخدام كشريط في الأسفل
class ConnectionStatusBar extends StatefulWidget {
  const ConnectionStatusBar({super.key});

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar> {
  final WebSocketService _wsService = WebSocketService();
  late StreamSubscription _connectionSubscription;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    
    // إعداد الحالة الأولية
    _isConnected = _wsService.isConnected;
    
    // الاستماع لتغييرات حالة الاتصال
    _connectionSubscription = _wsService.connectionStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: _isConnected 
          ? Colors.green.withValues(alpha: 0.1)
          : AppColors.primary.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isConnected ? Icons.signal_wifi_4_bar : Icons.refresh,
            size: 16,
            color: _isConnected ? Colors.green : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected 
                ? 'تحديثات مباشرة نشطة'
                : 'تحديثات تلقائية كل 30 ثانية',
            style: TextStyle(
              fontSize: 12,
              color: _isConnected ? Colors.green : AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// Extension لإضافة الـ widget بسهولة
extension ConnectionStatusExtension on Widget {
  Widget withConnectionStatus({bool showDetailed = false}) {
    return Column(
      children: [
        ConnectionStatusWidget(showDetailed: showDetailed),
        const SizedBox(height: 8),
        Expanded(child: this),
      ],
    );
  }
}
