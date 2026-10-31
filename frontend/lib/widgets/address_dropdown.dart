// lib/widgets/address_dropdown.dart
import '../constants/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/address_service.dart';
import '../services/session_service.dart';
import '../services/region_resolver_service.dart';
import '../models/address_model.dart';
import '../screens/add_address_screen.dart';
import '../screens/edit_address_screen.dart';

class AddressDropdown extends StatefulWidget {
  final Function(DetailedAddress)? onAddressChanged;
  final DetailedAddress? selectedAddress;
  final Color? iconColor;
  final Color? textColor;
  final double? fontSize;
  final int? maxLines;

  const AddressDropdown({
    super.key,
    this.onAddressChanged,
    this.selectedAddress,
    this.iconColor,
    this.textColor,
    this.fontSize,
    this.maxLines,
  });

  @override
  State<AddressDropdown> createState() => _AddressDropdownState();
}

class _AddressDropdownState extends State<AddressDropdown> {
  OverlayEntry? _warningOverlay;
  final GlobalKey _dropdownKey = GlobalKey();
  bool _isWarningDismissed = false;
  bool _isGuest = false;
  final RegionResolverService _regionResolver = RegionResolverService();
  String? _serviceWarningMessage; // رسالة التحذير المحددة

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAddressSystem();
    });
    // تحديث حالة الضيف بشكل متزامن
    _isGuest = !SessionService.instance.isLoggedIn;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _removeWarningOverlay();
    super.dispose();
  }

  Future<void> _initializeAddressSystem() async {
    if (!mounted) return;

    final addressService = context.read<EnhancedAddressService>();
    await addressService.fetchAddresses();

    if (!mounted) return;

    // إذا لم يكن هناك عنوان افتراضي أو المستخدم ضيف، شغل GPS تلقائياً
    final isGuest = !SessionService.instance.isLoggedIn;
    final hasDefaultAddress = addressService.defaultAddress != null;

    if (!mounted) return;

    if (isGuest || !hasDefaultAddress) {
      // تشغيل GPS تلقائياً
      print(
        '🌍 تشغيل GPS تلقائياً للمستخدم ${isGuest ? "الضيف" : "بدون عناوين"}',
      );
      await addressService.getCurrentLocationAddress();
    }

    if (!mounted) return;

    // فحص فوري للموقع عبر Region API وإظهار التحذير إذا لزم الأمر
    DetailedAddress? addressToCheck;

    // تحديد العنوان المناسب للفحص
    if (addressService.defaultAddress != null) {
      addressToCheck = addressService.defaultAddress;
      print('📍 فحص العنوان الافتراضي');
    } else if (addressService.currentLocationAddress != null) {
      addressToCheck = addressService.currentLocationAddress;
      print('📍 فحص الموقع الحالي');
    }

    // فحص العنوان وإظهار التحذير إن وجد
    if (addressToCheck != null && mounted) {
      final isAvailable = await _checkRegionAvailability(addressToCheck);

      if (!isAvailable && !_isWarningDismissed && mounted) {
        // تأخير بسيط للتأكد من اكتمال بناء الواجهة
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _warningOverlay == null) {
            _showWarningTooltip();
          }
        });
      }
    }
  }

  void _removeWarningOverlay() {
    if (_warningOverlay != null) {
      _warningOverlay!.remove();
      _warningOverlay = null;
    }
  }

  void _showWarningTooltip() {
    // تحقق من أن الـ widget ما زال mounted قبل المتابعة
    if (!mounted) return;

    _removeWarningOverlay();

    final RenderBox? renderBox =
        _dropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !mounted) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _warningOverlay = OverlayEntry(
      builder:
          (context) => Positioned(
            left: offset.dx + 10,
            top: offset.dy + size.height + 5, // أسفل شريط العنوان مباشرة
            child: Material(
              color: Colors.transparent,
              child: CustomPaint(
                painter: TooltipPainter(),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: size.width - 20,
                    minWidth: 250,
                  ),
                  padding: const EdgeInsets.only(
                    top: 20, // مساحة للسهم
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: const Color(0xFF00296B),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _serviceWarningMessage ??
                              'موقعك بعيد عن نطاق خدماتنا.\nيرجى اختيار عنوان داخل العراق.',
                          style: const TextStyle(
                            color: const Color(0xFF00296B),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (mounted) {
                            setState(() {
                              _isWarningDismissed = true;
                            });
                            _removeWarningOverlay();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );

    // تحقق مرة أخرى من أن الـ widget ما زال mounted قبل إدراج الـ overlay
    if (mounted && _dropdownKey.currentContext != null) {
      Overlay.of(_dropdownKey.currentContext!).insert(_warningOverlay!);
    }
  }

  bool _isOutsideIraq(String? address) {
    if (address == null) return false;
    return !(address.contains('العراق') ||
        address.contains('Iraq') ||
        address.contains('بغداد') ||
        address.contains('Baghdad') ||
        address.contains('البصرة') ||
        address.contains('Basra') ||
        address.contains('أربيل') ||
        address.contains('Erbil') ||
        address.contains('النجف') ||
        address.contains('Najaf') ||
        address.contains('كربلاء') ||
        address.contains('Karbala') ||
        address.contains('الموصل') ||
        address.contains('Mosul'));
  }

  /// فحص توفر الخدمة في المنطقة عبر Region API
  /// يتحقق من: المنطقة موجودة + نشطة + التوصيل متوفر
  Future<bool> _checkRegionAvailability(DetailedAddress? address) async {
    if (address == null) {
      _serviceWarningMessage = 'لم يتم تحديد عنوان';
      return false;
    }

    // فحص أولي: هل العنوان في العراق؟
    if (_isOutsideIraq(address.fullAddress)) {
      _serviceWarningMessage =
          'موقعك بعيد عن نطاق خدماتنا.\nيرجى اختيار عنوان داخل العراق.';
      return false;
    }

    // إذا لم يكن هناك GPS coordinates، نفترض أنه صحيح
    if (address.latitude == null || address.longitude == null) {
      _serviceWarningMessage =
          'حدد نقطة العنوان على الخريطة للتحقق من التوصيل.';
      return false;
    }

    try {
      // استدعاء Region API
      final result = await _regionResolver.resolvePoint(
        lat: address.latitude!,
        lng: address.longitude!,
      );

      if (result == null) {
        // المنطقة غير موجودة في النظام
        _serviceWarningMessage =
            'عذراً، هذه المنطقة غير مخدومة حالياً.\nيرجى اختيار عنوان آخر.';
        return false;
      }

      // فحص حالة المنطقة
      if (!result.effective.isActive) {
        _serviceWarningMessage =
            'هذه المنطقة غير نشطة مؤقتاً.\nيرجى اختيار عنوان آخر.';
        return false;
      }

      // فحص توفر خدمة التوصيل
      if (!result.effective.hasDelivery) {
        _serviceWarningMessage =
            'خدمة التوصيل غير متوفرة في هذه المنطقة.\nيرجى اختيار عنوان آخر.';
        return false;
      }

      // كل شيء تمام!
      print('✅ المنطقة محددة: ${result.region.nameAr} (${result.region.name})');
      print('✅ خدمة التوصيل متوفرة');
      _serviceWarningMessage = null;
      return true;
    } catch (e) {
      print('❌ Error checking region availability: $e');
      _serviceWarningMessage = 'تعذر التحقق من تغطية العنوان. أعد المحاولة.';
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnhancedAddressService>(
      builder: (context, addressService, child) {
        String addressText = '';
        DetailedAddress? addressToCheck;

        // أولوية العرض: العنوان المختار من المستخدم > العنوان الافتراضي > الموقع الحالي
        if (widget.selectedAddress != null) {
          // عرض العنوان المختار من المستخدم (له الأولوية القصوى)
          addressText = widget.selectedAddress!.fullAddress;
          addressToCheck = widget.selectedAddress;
          print('📍 عرض العنوان المختار: ${addressText}');
        } else if (addressService.defaultAddress != null && !_isGuest) {
          // عرض العنوان الافتراضي وإشعار الـ parent
          addressText = addressService.defaultAddress!.fullAddress;
          addressToCheck = addressService.defaultAddress;
          print('📍 عرض العنوان الافتراضي: ${addressText}');

          // إشعار الشاشة الرئيسية بالعنوان الافتراضي تلقائياً
          Future.microtask(() {
            if (mounted &&
                widget.onAddressChanged != null &&
                widget.selectedAddress?.id !=
                    addressService.defaultAddress?.id) {
              widget.onAddressChanged!(addressService.defaultAddress!);
            }
          });
        } else if (addressService.currentLocationAddress != null) {
          // عرض الموقع الحالي (GPS) وإشعار الـ parent
          addressText = addressService.currentLocationAddress!.fullAddress;
          addressToCheck = addressService.currentLocationAddress;
          print('📍 عرض الموقع الحالي (GPS): ${addressText}');

          // إشعار الشاشة الرئيسية بالموقع الحالي
          Future.microtask(() {
            if (mounted &&
                widget.onAddressChanged != null &&
                widget.selectedAddress?.id !=
                    addressService.currentLocationAddress?.id) {
              widget.onAddressChanged!(addressService.currentLocationAddress!);
            }
          });
        } else if (addressService.isLoadingLocation) {
          addressText = 'جاري تحديد الموقع...';
        } else {
          addressText = 'اختر العنوان';
        }

        // فحص توفر الخدمة في المنطقة (async)
        if (addressToCheck != null &&
            !_isWarningDismissed &&
            _warningOverlay == null) {
          Future.microtask(() async {
            if (mounted) {
              final isAvailable = await _checkRegionAvailability(
                addressToCheck,
              );
              if (!isAvailable && mounted) {
                _showWarningTooltip();
              }
            }
          });
        } else if (addressToCheck == null && _warningOverlay != null) {
          Future.microtask(() {
            if (mounted) {
              _removeWarningOverlay();
            }
          });
        }
        return GestureDetector(
          key: _dropdownKey,
          onTap: () => _showAddressBottomSheet(addressService),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: widget.iconColor ?? AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'توصيل إلى',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        addressText,
                        style: TextStyle(
                          fontSize: widget.fontSize ?? 14,
                          fontWeight: FontWeight.w500,
                          color: widget.textColor ?? Colors.black87,
                        ),
                        maxLines: widget.maxLines ?? 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: widget.textColor ?? Colors.black87,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddressBottomSheet(EnhancedAddressService addressService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => AddressBottomSheet(
            addressService: addressService,
            onAddressSelected: (address) {
              print('✅ تم اختيار عنوان: ${address.fullAddress}');
              // إشعار الشاشة الرئيسية بالعنوان الجديد
              if (widget.onAddressChanged != null) {
                widget.onAddressChanged!(address);
              }
              Navigator.pop(context);
            },
          ),
    );
  }
}

class AddressBottomSheet extends StatelessWidget {
  final EnhancedAddressService addressService;
  final Function(DetailedAddress) onAddressSelected;

  const AddressBottomSheet({
    super.key,
    required this.addressService,
    required this.onAddressSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle indicator
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
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
                        Icons.location_on,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'اختر العنوان',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.grey),
                        iconSize: 20,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Consumer<EnhancedAddressService>(
                  builder: (context, addressService, child) {
                    if (addressService.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (addressService.error != null) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              addressService.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => addressService.fetchAddresses(),
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView(
                      controller: scrollController,
                      children: [
                        // Current Location Button
                        _buildCurrentLocationButton(context, addressService),

                        const Divider(),

                        // Saved Addresses
                        if (addressService.detailedAddresses.isNotEmpty)
                          ...addressService.detailedAddresses.map(
                            (address) => _buildAddressItem(context, address),
                          ),

                        // Add New Address Button
                        _buildAddAddressButton(context),

                        const SizedBox(height: 20),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentLocationButton(
    BuildContext context,
    EnhancedAddressService addressService,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap:
            addressService.isLoadingLocation
                ? null
                : () async {
                  print('🎯 النقر على زر الموقع الحالي...');
                  await addressService.getCurrentLocationAddress();
                  print(
                    '📍 نتيجة GPS: ${addressService.currentLocationAddress?.fullAddress}',
                  );
                  print('❌ خطأ GPS: ${addressService.locationError}');

                  if (addressService.currentLocationAddress != null &&
                      addressService.locationError == null) {
                    print('✅ إرسال الموقع الحالي إلى الشاشة الرئيسية');
                    onAddressSelected(addressService.currentLocationAddress!);
                  } else if (addressService.locationError != null) {
                    print(
                      '⚠️ فشل الحصول على الموقع: ${addressService.locationError}',
                    );
                    // عرض رسالة خطأ للمستخدم
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(addressService.locationError!),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
            color: AppColors.primary.withValues(alpha: 0.05),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.my_location,
                  color: const Color(0xFF00296B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'استخدام الموقع الحالي',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // منطق عرض النصوص بناءً على حالة الموقع
                    if (addressService.isLoadingLocation) ...[
                      const Text(
                        'جاري تحديد الموقع...',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ] else if (addressService.locationError != null) ...[
                      Text(
                        addressService.locationError!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ] else if (addressService.currentLocationAddress !=
                        null) ...[
                      Text(
                        addressService.currentLocationAddress!.fullAddress,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      const Text(
                        'اضغط لتحديد موقعك',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
              // مؤشر التحميل بجانب العمود
              if (addressService.isLoadingLocation)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressItem(BuildContext context, DetailedAddress address) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => onAddressSelected(address),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  address.isDefault
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : AppColors.primary.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(12),
            color:
                address.isDefault
                    ? AppColors.primary.withValues(alpha: 0.05)
                    : Colors.white,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getAddressTypeColor(
                    address.addressType,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getAddressTypeColor(address.addressType),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _getAddressTypeIcon(address.addressType),
                  color: _getAddressTypeColor(address.addressType),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          address.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (address.isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'افتراضي',
                              style: TextStyle(
                                color: const Color(0xFF00296B),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address.fullAddress,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: PopupMenuButton<String>(
                  onSelected:
                      (value) => _handleAddressAction(context, value, address),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: Colors.white,
                  elevation: 8,
                  itemBuilder:
                      (context) => [
                        if (!address.isDefault)
                          PopupMenuItem(
                            value: 'set_default',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.star,
                                      size: 18,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('تعيين كافتراضي'),
                                ],
                              ),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text('تعديل'),
                              ],
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'حذف',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: Colors.grey,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddAddressButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: InkWell(
        onTap: () => _showAddAddressScreen(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
            color: AppColors.primary.withValues(alpha: 0.05),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add,
                  color: const Color(0xFF00296B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'إضافة عنوان جديد',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAddressAction(
    BuildContext context,
    String action,
    DetailedAddress address,
  ) {
    final addressService = context.read<EnhancedAddressService>();

    switch (action) {
      case 'set_default':
        addressService.setDefaultAddress(address.id).then((success) {
          if (success) {
            // إشعار الشاشة الرئيسية بالعنوان الافتراضي الجديد
            onAddressSelected(address);
          }
        });
        break;
      case 'edit':
        _showEditAddressScreen(context, address);
        break;
      case 'delete':
        _showDeleteConfirmation(context, address);
        break;
    }
  }

  void _showDeleteConfirmation(BuildContext context, DetailedAddress address) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle indicator
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Icon and title
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'تأكيد الحذف',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'هل أنت متأكد من حذف عنوان "${address.name}"؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'لا يمكن التراجع عن هذا الإجراء.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 32),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await addressService.deleteAddress(address.id);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.secondary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'حذف',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  void _showAddAddressScreen(BuildContext context) {
    Navigator.pop(context);
    final addressService = context.read<EnhancedAddressService>();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddAddressScreen()),
    ).then((result) {
      // إذا تم إضافة عنوان جديد بنجاح، حدث الشاشة الرئيسية
      if (result == true) {
        addressService.fetchAddresses().then((_) {
          // إذا كان هذا أول عنوان أو العنوان الافتراضي الجديد، حدث الشاشة الرئيسية
          if (addressService.defaultAddress != null) {
            onAddressSelected(addressService.defaultAddress!);
          }
        });
      }
    });
  }

  void _showEditAddressScreen(BuildContext context, DetailedAddress address) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditAddressScreen(address: address),
      ),
    );
  }

  Color _getAddressTypeColor(String type) {
    switch (type) {
      case 'home':
        return AppColors.primary;
      case 'work':
        return Colors.blue;
      case 'other':
        return AppColors.primary;
      case 'current':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getAddressTypeIcon(String type) {
    switch (type) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'other':
        return Icons.location_on;
      case 'current':
        return Icons.my_location;
      default:
        return Icons.location_on;
    }
  }
}

// كلاس لرسم السهم المؤشر للـ tooltip
class TooltipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.fill;

    // رسم مثلث صغير في الأعلى (السهم المؤشر)
    final path = Path();
    const arrowWidth = 16.0;
    const arrowHeight = 10.0;
    const arrowOffset = 24.0; // مسافة من اليسار

    path.moveTo(arrowOffset, arrowHeight);
    path.lineTo(arrowOffset + arrowWidth / 2, 0);
    path.lineTo(arrowOffset + arrowWidth, arrowHeight);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
