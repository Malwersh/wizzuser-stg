import '../services/iraqi_delivery_details.dart';
// lib/screens/edit_address_screen.dart

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';

import '../models/address_model.dart';
import '../widgets/loading_widget.dart';
import '../services/address_service.dart';
import '../widgets/location_picker_screen.dart';

class EditAddressScreen extends StatefulWidget {
  final DetailedAddress address;

  const EditAddressScreen({
    super.key,
    required this.address,
  });

  @override
  State<EditAddressScreen> createState() => _EditAddressScreenState();
}

class _EditAddressScreenState extends State<EditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  // 🔥 النظام الجديد: حقلان فقط
  final _detailedAddressController = TextEditingController(); // العنوان الكامل من Google (للقراءة فقط)
  final _neighborhoodController = TextEditingController();
  final _landmarkController = TextEditingController(); // الوصف الإجباري (قابل للتعديل)

  String _selectedType = AddressType.home;
  bool _isDefault = false;
  bool _isLoading = false;
  
  // متغيرات لحفظ البيانات الجديدة من الخريطة
  double? _newLatitude;
  double? _newLongitude;

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    _nameController.text = widget.address.name;
    _detailedAddressController.text = widget.address.detailedAddress ?? widget.address.fullAddress;
    _neighborhoodController.text = widget.address.neighborhood=='-'?'':widget.address.neighborhood;
    _landmarkController.text = IraqiDeliveryDetails.meaningful(widget.address.landmark)?widget.address.landmark:'';
    _selectedType = widget.address.addressType;
    _isDefault = widget.address.isDefault;
  }

  Future<void> _openMapToSelectLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const LocationPickerScreen(),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        final newAddress = result['address'] ?? '';
        if (newAddress.isNotEmpty) {
          _detailedAddressController.text = newAddress;
        }

        final position = result['position'];
        if (position != null) {
          _newLatitude = position.latitude;
          _newLongitude = position.longitude;
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _detailedAddressController.dispose();
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
          'تعديل العنوان',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showDeleteConfirmation,
            icon: const Icon(Icons.delete),
            tooltip: 'حذف العنوان',
          ),
        ],
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
                        onChanged: widget.address.isDefault ? null : (value) {
                          setState(() {
                            _isDefault = value ?? false;
                          });
                        },
                        activeColor: AppColors.primary,
                      ),
                      Expanded(child: Text(
                        widget.address.isDefault ? 'عنوانك الافتراضي — يمكنك تعيين عنوان آخر من عناوينك' : 'جعل هذا العنوان افتراضي',
                        style: const TextStyle(fontSize: 14),
                      )),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'تفاصيل العنوان',
                icon: Icons.location_on,
                children: [
                  _buildTextField(
                    controller: _detailedAddressController,
                    label: 'العنوان الكامل *',
                    hint: 'تم تحديده من الخريطة',
                    icon: Icons.location_on,
                    isRequired: true,
                    maxLines: 3,
                    readOnly: false,
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
                  const SizedBox(height: 16),
                  // زر تغيير الموقع من الخريطة
                  OutlinedButton.icon(
                    onPressed: _openMapToSelectLocation,
                    icon: const Icon(Icons.map),
                    label: const Text(
                      'تغيير الموقع من الخريطة',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 24),
              _buildActionButtons(),
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
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      textDirection: TextDirection.rtl,
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
        fillColor: readOnly ? Colors.grey[100] : Colors.white,
      ),
      validator: isRequired
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              return null;
            }
          : null,
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



  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveChanges,
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
                    'حفظ التعديلات',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showDeleteConfirmation,
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text(
              'حذف العنوان',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }





  Future<void> _saveChanges() async {
    if(!IraqiDeliveryDetails.meaningful(_neighborhoodController.text)||!IraqiDeliveryDetails.meaningful(_landmarkController.text)){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أكمل اسم الحي وأقرب نقطة دالة.')));return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final addressService = context.read<EnhancedAddressService>();
      String name;
      if (_selectedType == AddressType.home) {
        name = 'المنزل';
      } else if (_selectedType == AddressType.work) {
        name = 'العمل';
      } else {
        name = _nameController.text.trim();
      }
      // استخدام البيانات الجديدة من الخريطة إذا كانت متوفرة، وإلا استخدام القديمة
      // عند تحديث من الخريطة، نضع province = "-" لكي يستخدم البيكاند detailed_address فقط
      final request = AddressUpdateRequest(
        name: name,
        province: _newLatitude != null ? "-" : widget.address.province,
        district: widget.address.district,
        neighborhood: _neighborhoodController.text.trim(),
        landmark: _landmarkController.text.trim(),
        detailedAddress: _detailedAddressController.text.trim(),
        latitude: _newLatitude ?? widget.address.latitude,
        longitude: _newLongitude ?? widget.address.longitude,
        addressType: _selectedType,
        isDefault: _isDefault,
        buildingNumber: null,
        floorNumber: null,
        apartmentNumber: null,
      );

      final updatedAddress = await addressService.updateAddress(widget.address.id, request);
      
      if (updatedAddress != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث العنوان بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(addressService.error ?? 'فشل في تحديث العنوان'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث العنوان: $e'),
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

  void _showDeleteConfirmation() {
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
              'هل أنت متأكد من حذف عنوان "${widget.address.name}"؟',
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
                      _deleteAddress();
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

  Future<void> _deleteAddress() async {
    setState(() => _isLoading = true);

    try {
      final addressService = context.read<EnhancedAddressService>();
      final success = await addressService.deleteAddress(widget.address.id);
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف العنوان بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(addressService.error ?? 'فشل في حذف العنوان'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حذف العنوان: $e'),
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
}
