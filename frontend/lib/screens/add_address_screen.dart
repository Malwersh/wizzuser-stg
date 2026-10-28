import '../services/iraqi_delivery_details.dart';
// lib/screens/add_address_screen.dart

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';

import '../models/address_model.dart';
import '../widgets/loading_widget.dart';
import '../widgets/location_picker_screen.dart';
import '../services/address_service.dart';
import '../services/region_resolver_service.dart';

class AddAddressScreen extends StatefulWidget {
  const AddAddressScreen({super.key});

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  // 🔥 النظام الجديد: حقلان فقط
  final _fullAddressController = TextEditingController(); // العنوان الكامل من Google
  final _neighborhoodController = TextEditingController();
  final _landmarkController = TextEditingController(); // الوصف الإجباري

  // 🔥 GPS & Region System
  double? _latitude;
  double? _longitude;
  RegionResolveResult? _regionData;

  String _selectedType = AddressType.home;
  bool _isDefault = false;
  bool _isLoading = false;

  final String _country = 'العراق';

  @override
  void dispose() {
    _nameController.dispose();
    _fullAddressController.dispose();
    _neighborhoodController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'إضافة عنوان جديد',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionCard(
                title: 'معلومات العنوان الأساسية',
                icon: Icons.info_outline,
                children: [
                  // حقل البلد (العراق فقط) مع العلم
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      value: _country,
                      items: [
                        DropdownMenuItem(
                          value: 'العراق',
                          child: Row(
                            children: [
                              Text(
                                '🇮🇶',
                                style: TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              const Text('العراق'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: null, // غير قابل للتعديل
                      decoration: InputDecoration(
                        labelText: 'البلد *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                  // Address type selector first
                  _buildAddressTypeSelector(),
                  const SizedBox(height: 16),
                  // Only show name field if type is 'other'
                  if (_selectedType == AddressType.other)
                    _buildTextField(
                      controller: _nameController,
                      label: 'اسم العنوان',
                      hint: 'مثال: منزل الأصدقاء، بيت العائلة',
                      icon: Icons.label,
                      isRequired: true,
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _isDefault,
                        onChanged: (value) {
                          setState(() {
                            _isDefault = value ?? false;
                          });
                        },
                        activeColor: AppColors.primary,
                      ),
                      const Text(
                        'جعل هذا العنوان افتراضي',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // 🔥 زر اختيار من الخريطة - جديد
              _buildMapPickerButton(),
              
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'تفاصيل العنوان',
                icon: Icons.location_on,
                children: [
                  _buildTextField(
                    controller: _fullAddressController,
                    label: 'العنوان الكامل *',
                    hint: 'سيتم ملؤه تلقائياً من الخريطة',
                    icon: Icons.location_on,
                    isRequired: true,
                    maxLines: 3,
                    readOnly: false, // للقراءة فقط - يتم ملؤه من الخريطة
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _neighborhoodController,
                    label: 'اسم الحي أو المحلة *',
                    hint: 'اكتب اسم الحي',icon: Icons.location_city,isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _landmarkController,
                    label: 'وصف أقرب نقطة دالة *',
                    hint: 'مثل: بجانب الجامعة، مقابل المستشفى، قرب مول...',
                    icon: Icons.place,
                    isRequired: true,
                    maxLines: 2,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSaveButton(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool readOnly = false, // إضافة خاصية القراءة فقط
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      textDirection: TextDirection.rtl, // ✅ RTL للنصوص العربية
      decoration: InputDecoration(
        labelText: label + (isRequired ? ' *' : ''),
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        filled: true,
        fillColor: readOnly ? Colors.grey[100] : Colors.white, // لون مختلف للقراءة فقط
      ),
      validator: (label == 'رقم الهاتف')
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              final phone = value.trim();
              if (!phone.startsWith('+964') || phone.length < 13) {
                return 'يرجى إدخال رقم عراقي صحيح يبدأ بـ +964';
              }
              return null;
            }
          : (isRequired
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'هذا الحقل مطلوب';
                  }
                  return null;
                }
              : null),
    );
  }

  Widget _buildAddressTypeSelector() {
    final types = [
      {'type': AddressType.home, 'name': 'المنزل', 'icon': Icons.home, 'color': Colors.green},
      {'type': AddressType.work, 'name': 'العمل', 'icon': Icons.work, 'color': Colors.blue},
      {'type': AddressType.other, 'name': 'أخرى', 'icon': Icons.location_on, 'color': AppColors.primary},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'نوع العنوان',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: types.map((type) {
            final isSelected = _selectedType == type['type'];
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedType = type['type'] as String;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        type['icon'] as IconData,
                        color: isSelected
                            ? AppColors.primary
                            : Colors.grey[600],
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type['name'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? AppColors.primary
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveAddress,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SmallLoadingWidget(color: Colors.white)
            : const Text(
                'حفظ العنوان',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _saveAddress() async {
    if(!IraqiDeliveryDetails.meaningful(_neighborhoodController.text)||!IraqiDeliveryDetails.meaningful(_landmarkController.text)){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أكمل اسم الحي وأقرب نقطة دالة.')));return;
    }
    if (!_formKey.currentState!.validate()) return;
    
    // 🔥 تحقق من وجود العنوان والموقع
    if (_fullAddressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ يرجى اختيار الموقع من الخريطة أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ يجب تحديد موقع GPS من الخريطة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final addressService = context.read<EnhancedAddressService>();
      
      // تحديد الاسم حسب النوع
      String displayName;
      if (_selectedType == AddressType.home) {
        displayName = 'المنزل';
      } else if (_selectedType == AddressType.work) {
        displayName = 'العمل';
      } else {
        displayName = _nameController.text.trim();
      }
      
      // 🔥 استخراج المحافظة من العنوان الكامل
      String? extractedProvince;
      final fullAddress = _fullAddressController.text.trim();
      if (fullAddress.contains('،')) {
        final parts = fullAddress.split('،');
        // أول جزء عادة هو المحافظة في نتائج Google
        extractedProvince = parts.first.trim();
      }
      
      final request = AddressCreateRequest(
        name: displayName,
        // 🔥 العنوان الكامل من Google Places
        province: extractedProvince ?? 'غير محدد',
        district: '-', // placeholder - سيتم تحديثه في Backend
        neighborhood: _neighborhoodController.text.trim(),
        landmark: _landmarkController.text.trim(), // الوصف الإجباري من المستخدم
        detailedAddress: fullAddress, // العنوان الكامل
        // 🔥 GPS Data - إجباري الآن
        latitude: _latitude!,
        longitude: _longitude!,
        addressType: _selectedType,
        isDefault: _isDefault,
        // لم تعد هناك حاجة لحقول المبنى
        buildingNumber: null,
        floorNumber: null,
        apartmentNumber: null,
        // 🔥 Region System Data - من service.delivery (القيم الحقيقية)
        regionId: _regionData?.region.id,
        regionName: _regionData?.region.name,
        regionNameAr: _regionData?.region.nameAr,
        regionLevel: _regionData?.region.level,
        regionIsActive: _regionData?.effective.isActive,
        deliveryFee: _regionData?.effective.service?.delivery?.baseFee,
        minimumOrder: _regionData?.effective.service?.delivery?.minimumOrder,
        maxDistanceKm: _regionData?.effective.limits?.maxDeliveryDistanceKm.toDouble(),
        pricePerKm: null, // لم نعد نستخدمه
      );
      
      // 🔥 Log بيانات المنطقة للتحقق
      print('📍 حفظ عنوان جديد:');
      print('   - الاسم: $displayName');
      print('   - العنوان الكامل: $fullAddress');
      print('   - الوصف: ${_landmarkController.text}');
      print('   - GPS: ${_latitude}, ${_longitude}');
      if (_regionData != null) {
        print('   - المنطقة: ${_regionData!.region.nameAr}');
        print('   - Region ID: ${_regionData!.region.id}');
        print('   - رسوم التوصيل: ${_regionData!.effective.service?.delivery?.baseFee}');
        print('   - الحد الأدنى: ${_regionData!.effective.service?.delivery?.minimumOrder}');
        print('   - نشطة: ${_regionData!.effective.isActive}');
      } else {
        print('   ⚠️ لا توجد بيانات منطقة');
      }

      final newAddress = await addressService.createAddress(request);
      
      if (newAddress != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة العنوان بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        print('❌ فشل في إنشاء العنوان في الشاشة');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(addressService.error ?? 'فشل في إضافة العنوان'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ العنوان: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  // 🔥 زر اختيار من الخريطة
  Widget _buildMapPickerButton() {
    return Card(
      elevation: _regionData != null ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _regionData != null 
              ? Colors.green.withValues(alpha: 0.5) 
              : AppColors.primary.withValues(alpha: 0.2),
          width: _regionData != null ? 2 : 1,
        ),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: _openMapPicker,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_regionData != null ? Colors.green : AppColors.primary)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _regionData != null ? Icons.check_circle : Icons.map,
                      color: _regionData != null ? Colors.green : AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _regionData != null 
                              ? '✅ تم اختيار الموقع من الخريطة'
                              : '🗺️ اختيار الموقع من الخريطة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _regionData != null ? Colors.green : AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _regionData != null
                              ? _fullAddressController.text.isNotEmpty 
                                ? _fullAddressController.text
                                : 'تم تحديد الموقع'
                              : 'بحث ذكي + GPS دقيق + رسوم التوصيل',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ],
              ),
              
              // عرض معلومات المنطقة إذا تم الاختيار
              if (_regionData != null) ...[
                const Divider(height: 24),
                _buildRegionInfoRow(
                  '📍 المنطقة',
                  _regionData!.region.nameAr,
                  Colors.blue,
                ),
                if (_regionData!.effective.service?.delivery?.baseFee != null)
                  _buildRegionInfoRow(
                    '💰 رسوم التوصيل',
                    '${_regionData!.effective.service!.delivery!.baseFee!.toStringAsFixed(0)} د.ع',
                    Colors.green,
                  ),
                if (_regionData!.effective.service?.delivery?.minimumOrder != null)
                  _buildRegionInfoRow(
                    '🛒 الحد الأدنى للطلب',
                    '${_regionData!.effective.service!.delivery!.minimumOrder!.toStringAsFixed(0)} د.ع',
                    Colors.orange,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildRegionInfoRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  // 🔥 فتح LocationPickerScreen
  Future<void> _openMapPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialPosition: _latitude != null && _longitude != null
              ? LatLng(_latitude!, _longitude!)
              : null,
          initialAddress: _fullAddressController.text,
        ),
      ),
    );
    
    if (result != null && mounted) {
      setState(() {
        final position = result['position'] as LatLng?;
        _latitude = position?.latitude;
        _longitude = position?.longitude;
        final selectedAddress = result['address'] as String?;
        _regionData = result['region'] as RegionResolveResult?;
        
        // 🔥 ملء حقل العنوان الكامل تلقائياً
        if (selectedAddress != null && selectedAddress.isNotEmpty) {
          _fullAddressController.text = selectedAddress;
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم تحديد الموقع: ${_regionData?.region.nameAr ?? "غير معروف"}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
