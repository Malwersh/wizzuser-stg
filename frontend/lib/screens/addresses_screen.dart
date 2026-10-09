// lib/screens/addresses_screen.dart
import '../constants/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/address_model.dart';
import '../services/address_service.dart';
import '../services/session_service.dart';
import '../widgets/loading_widget.dart';
import '../widgets/error_widget.dart';
import 'add_address_screen.dart';
import 'edit_address_screen.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  late EnhancedAddressService _addressService;

  @override
  void initState() {
    super.initState();
    _addressService = context.read<EnhancedAddressService>();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    
    try {
      await _addressService.fetchAddresses();
      
      // إجبار إعادة بناء الـ UI
      if (mounted) {
        setState(() {});
        
        // تأخير إضافي وإعادة setState مرة أخرى لضمان التحديث
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      print('❌ خطأ في تحميل العناوين: $e');
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'عناويني',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _loadAddresses,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Consumer<EnhancedAddressService>(
        builder: (context, addressService, child) {
          if (addressService.isLoading && addressService.detailedAddresses.isEmpty) {
            return const Center(child: LoadingWidget());
          }

          if (addressService.error != null && addressService.detailedAddresses.isEmpty) {
            return Center(
              child: ErrorDisplayWidget(
                error: addressService.error!,
                onRetry: _loadAddresses,
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadAddresses,
            child: Column(
              children: [
                // قائمة العناوين المحفوظة
                Expanded(
                  child: addressService.detailedAddresses.isEmpty
                      ? _buildEmptyState()
                      : _buildAddressesList(addressService.detailedAddresses),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddAddress(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        icon: const Icon(Icons.add_location),
        label: const Text('إضافة عنوان'),
      ),
    );
  }

  Widget _buildAddressesList(List<DetailedAddress> addresses) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20, // إضافة مسافة علوية
        bottom: 80, // مسافة سفلية لزر الإضافة
      ),
      itemCount: addresses.length,
      itemBuilder: (context, index) {
        final address = addresses[index];
        return _buildAddressCard(address);
      },
    );
  }

  Widget _buildAddressCard(DetailedAddress address) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: () => _showAddressOptions(address),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس البطاقة
              Row(
                children: [
                  // أيقونة ونوع العنوان
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getAddressTypeColor(address.addressType),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      address.typeIcon,
                      style: const TextStyle(fontSize: 16),
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
                                fontWeight: FontWeight.bold,
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
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'افتراضي',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          address.typeDisplayName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      onPressed: () => _showAddressOptions(address),
                      icon: const Icon(Icons.more_vert),
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // العنوان الكامل - عرض على 3 أسطر
              _buildFormattedAddress(address),
              
              // معلومات إضافية
              if (address.phoneNumber != null || 
                  address.buildingNumber != null ||
                  address.apartmentNumber != null) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  children: [
                    if (address.buildingNumber != null)
                      _buildInfoChip('المبنى', address.buildingNumber!),
                    if (address.apartmentNumber != null)
                      _buildInfoChip('الشقة', address.apartmentNumber!),
                    if (address.phoneNumber != null)
                      _buildInfoChip('الهاتف', address.phoneNumber!),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// بناء عرض العنوان على 3 أسطر
  /// السطر 1: العراق، المحافظة (البلد أولاً)
  /// السطر 2: الناحية/القضاء، الحي
  /// السطر 3: أقرب نقطة دالة
  Widget _buildFormattedAddress(DetailedAddress address) {
    // تقسيم العنوان الكامل إلى أجزاء
    final fullAddress = address.fullAddress;
    final parts = fullAddress.split('، ').map((p) => p.trim()).toList();
    
    // استخراج أقرب نقطة دالة إذا وجدت
    String? landmarkPart;
    final landmarkIndex = parts.indexWhere((p) => p.startsWith('قرب '));
    if (landmarkIndex != -1) {
      landmarkPart = parts[landmarkIndex];
      parts.removeAt(landmarkIndex);
    }
    
    // تجميع الأجزاء المتبقية
    // السطر الأول: البلد والمحافظة (آخر جزئين - لكن بترتيب معكوس)
    String line1 = '';
    // السطر الثاني: الناحية والحي والباقي
    String line2 = '';
    
    if (parts.length >= 2) {
      // آخر عنصر هو البلد (العراق)
      final country = parts.last;
      
      // قبل الأخير هو المحافظة
      String province = '';
      if (parts.length >= 2) {
        province = parts[parts.length - 2];
      }
      
      // السطر الأول: البلد، المحافظة (بهذا الترتيب)
      line1 = '$country، $province';
      
      // السطر الثاني: الباقي (الناحية/القضاء، الحي)
      if (parts.length > 2) {
        final remaining = parts.sublist(0, parts.length - 2);
        line2 = remaining.join('، ');
      }
    } else if (parts.length == 1) {
      line1 = parts[0];
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // السطر 1: البلد، المحافظة
        if (line1.isNotEmpty)
          Text(
            line1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
              height: 1.4,
            ),
            textDirection: TextDirection.rtl,
          ),
        
        // السطر 2: القضاء والحي
        if (line2.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            line2,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              height: 1.4,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
        
        // السطر 3: أقرب نقطة دالة
        if (landmarkPart != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.place,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  landmarkPart,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Color _getAddressTypeColor(String type) {
    switch (type) {
      case AddressType.home:
        return AppColors.primary.withValues(alpha: 0.1);
      case AddressType.work:
        return AppColors.secondary.withValues(alpha: 0.1);
      case AddressType.current:
        return Colors.green.withValues(alpha: 0.1);
      default:
        return Colors.grey[100]!;
    }
  }

  Widget _buildEmptyState() {
    return Consumer<EnhancedAddressService>(
      builder: (context, addressService, child) {
        // التحقق إذا كان المستخدم ضيف
        final isGuest = SessionService.isGuestStatic();
        final hasError = addressService.error != null;
        
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasError 
                  ? Icons.error_outline 
                  : isGuest 
                    ? Icons.person_outline 
                    : Icons.location_off,
                size: 80,
                color: hasError 
                  ? Colors.red[400] 
                  : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                hasError 
                  ? 'حدث خطأ في تحميل العناوين'
                  : isGuest 
                    ? 'قم بتسجيل الدخول' 
                    : 'لا توجد عناوين محفوظة بعد',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: hasError ? Colors.red[600] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasError 
                  ? addressService.error!
                  : isGuest 
                    ? 'سجل دخولك لحفظ عناوينك المفضلة'
                    : 'اضغط على الزر أدناه لإضافة أول عنوان لك',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (hasError) ...[
                // زر إعادة المحاولة في حالة الخطأ
                ElevatedButton.icon(
                  onPressed: _loadAddresses,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
                const SizedBox(height: 12),
                // زر إعادة تسجيل الدخول إذا كانت المشكلة في الجلسة
                if (addressService.error?.contains('تسجيل الدخول') == true)
                  TextButton(
                    onPressed: () {
                      if (!mounted) return;
                      Navigator.pushNamed(context, '/login');
                    },
                    child: const Text(
                      'إعادة تسجيل الدخول',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ] else if (isGuest) ...[
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/login');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text('تسجيل الدخول'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showAddressOptions(DetailedAddress address) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildAddressOptionsSheet(address),
    );
  }

  Widget _buildAddressOptionsSheet(DetailedAddress address) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان البطاقة
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  address.typeIcon,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      address.shortAddress,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey[200]),
          
          // الخيارات
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit, color: AppColors.secondary, size: 20),
                  ),
                  title: const Text('تعديل العنوان'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToEditAddress(address);
                  },
                ),
                
                if (!address.isDefault) ...[
                  Divider(height: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.star, color: Colors.amber, size: 20),
                    ),
                    title: const Text('جعل افتراضي'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () {
                      Navigator.pop(context);
                      _setAsDefault(address);
                    },
                  ),
                ],
                
                Divider(height: 1, color: Colors.grey[200]),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete, color: Colors.red, size: 20),
                  ),
                  title: const Text('حذف العنوان', style: TextStyle(color: Colors.red)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(address);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToAddAddress() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddAddressScreen(),
      ),
    ).then((result) {
      // 🔧 إصلاح: إعادة تحميل العناوين بعد إضافة عنوان جديد
      if (result == true) {
        
        // إعادة تحميل فورية
        _loadAddresses();
        
        // إضافة تأخير قصير لضمان انتهاء العملية على الخادم
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadAddresses();
          }
        });
        
        // إضافة تحديث إضافي لضمان الاستجابة
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _loadAddresses();
          }
        });
      }
    });
  }

  void _navigateToEditAddress(DetailedAddress address) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditAddressScreen(address: address),
      ),
    ).then((result) {
      // 🔧 إصلاح: إعادة تحميل العناوين بعد تعديل عنوان
      if (result == true) {
        // إعادة تحميل فورية
        _loadAddresses();
        
        // إضافة تأخير قصير لضمان انتهاء العملية على الخادم
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadAddresses();
          }
        });
      }
    });
  }

  Future<void> _setAsDefault(DetailedAddress address) async {
    final success = await _addressService.setDefaultAddress(address.id);
    
    if (!mounted) return;
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تعيين "${address.name}" كعنوان افتراضي'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_addressService.error ?? 'فشل في تعيين العنوان الافتراضي'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmDelete(DetailedAddress address) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => Container(
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
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteAddress(address);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
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

  Future<void> _deleteAddress(DetailedAddress address) async {
    final success = await _addressService.deleteAddress(address.id);
    
    if (!mounted) return;
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حذف عنوان "${address.name}"'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_addressService.error ?? 'فشل في حذف العنوان'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
