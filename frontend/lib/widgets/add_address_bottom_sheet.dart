// lib/widgets/add_address_bottom_sheet.dart
import '../constants/app_colors.dart';

import 'package:flutter/material.dart';
import '../services/address_service.dart';
import '../models/address_model.dart';

class AddAddressBottomSheet extends StatefulWidget {
  final EnhancedAddressService addressService;
  final DetailedAddress? editAddress;
  final Function(DetailedAddress) onAddressSaved;

  const AddAddressBottomSheet({
    super.key,
    required this.addressService,
    this.editAddress,
    required this.onAddressSaved,
  });

  @override
  State<AddAddressBottomSheet> createState() => _AddAddressBottomSheetState();
}

class _AddAddressBottomSheetState extends State<AddAddressBottomSheet> {
  final _nameController = TextEditingController();
  final _provinceController = TextEditingController();
  final _districtController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _detailedAddressController = TextEditingController();
  final _buildingNumberController = TextEditingController();
  final _floorNumberController = TextEditingController();
  final _apartmentNumberController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  
  String _selectedType = 'home';
  bool _isDefault = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    if (widget.editAddress != null) {
      final address = widget.editAddress!;
      _nameController.text = address.name;
      _provinceController.text = address.province;
      _districtController.text = address.district;
      _neighborhoodController.text = address.neighborhood;
      _landmarkController.text = address.landmark;
      _detailedAddressController.text = address.detailedAddress ?? '';
      _buildingNumberController.text = address.buildingNumber ?? '';
      _floorNumberController.text = address.floorNumber ?? '';
      _apartmentNumberController.text = address.apartmentNumber ?? '';
      _phoneNumberController.text = address.phoneNumber ?? '';
      _selectedType = address.addressType;
      _isDefault = address.isDefault;
      _latitude = address.latitude;
      _longitude = address.longitude;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _provinceController.dispose();
    _districtController.dispose();
    _neighborhoodController.dispose();
    _landmarkController.dispose();
    _detailedAddressController.dispose();
    _buildingNumberController.dispose();
    _floorNumberController.dispose();
    _apartmentNumberController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  widget.editAddress != null ? 'تعديل العنوان' : 'إضافة عنوان جديد',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          
          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField(
                    controller: _nameController,
                    label: 'اسم العنوان',
                    hint: 'مثال: المنزل، العمل، الشقة',
                    icon: Icons.label,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildAddressTypeSelector(),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _provinceController,
                          label: 'المحافظة',
                          hint: 'بغداد',
                          icon: Icons.location_city,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _districtController,
                          label: 'المنطقة/القضاء',
                          hint: 'الكرخ',
                          icon: Icons.location_on,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _neighborhoodController,
                          label: 'الحي',
                          hint: 'حي الجامعة',
                          icon: Icons.home_filled,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _landmarkController,
                          label: 'أقرب نقطة دالة',
                          hint: 'قرب الجامعة',
                          icon: Icons.place,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _detailedAddressController,
                    label: 'تفاصيل العنوان (اختياري)',
                    hint: 'تفاصيل إضافية عن الموقع',
                    icon: Icons.description,
                    maxLines: 2,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  const Text(
                    'معلومات المبنى (اختياري)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _buildingNumberController,
                          label: 'رقم المبنى',
                          hint: '123',
                          icon: Icons.business,
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _floorNumberController,
                          label: 'رقم الطابق',
                          hint: '2',
                          icon: Icons.layers,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _apartmentNumberController,
                          label: 'رقم الشقة',
                          hint: '4A',
                          icon: Icons.door_front_door,
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _phoneNumberController,
                          label: 'رقم الهاتف',
                          hint: '07xxxxxxxxx',
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Get Current Location Button
                  _buildCurrentLocationButton(),
                  
                  const SizedBox(height: 16),
                  
                  // Set as Default Checkbox
                  CheckboxListTile(
                    value: _isDefault,
                    onChanged: (value) {
                      setState(() {
                        _isDefault = value ?? false;
                      });
                    },
                    title: const Text('تعيين كعنوان افتراضي'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          
          // Save Button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveAddress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.editAddress != null ? 'حفظ التعديلات' : 'حفظ العنوان',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'نوع العنوان',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildTypeOption('home', 'المنزل', Icons.home),
            const SizedBox(width: 12),
            _buildTypeOption('work', 'العمل', Icons.work),
            const SizedBox(width: 12),
            _buildTypeOption('other', 'أخرى', Icons.location_on),
          ],
        ),
      ],
    );
  }

  Widget _buildTypeOption(String type, String label, IconData icon) {
    final isSelected = _selectedType == type;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedType = type;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentLocationButton() {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: _getCurrentLocation,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue.shade300),
            borderRadius: BorderRadius.circular(12),
            color: Colors.blue.shade50,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.my_location,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'استخدام الموقع الحالي',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ),
              if (widget.addressService.isLoadingLocation)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _getCurrentLocation() async {
    await widget.addressService.getCurrentLocationAddress();
    
    if (widget.addressService.currentLocationAddress != null) {
      final currentAddress = widget.addressService.currentLocationAddress!;
      setState(() {
        _provinceController.text = currentAddress.province;
        _districtController.text = currentAddress.district;
        _neighborhoodController.text = currentAddress.neighborhood;
        _landmarkController.text = currentAddress.landmark;
        _latitude = currentAddress.latitude;
        _longitude = currentAddress.longitude;
      });
    }
  }

  void _saveAddress() async {
    if (!_validateForm()) return;

    if (widget.editAddress != null) {
      // Update existing address
      final updateRequest = AddressUpdateRequest(
        name: _nameController.text.trim(),
        province: _provinceController.text.trim(),
        district: _districtController.text.trim(),
        neighborhood: _neighborhoodController.text.trim(),
        landmark: _landmarkController.text.trim(),
        detailedAddress: _detailedAddressController.text.trim(),
        addressType: _selectedType,
        isDefault: _isDefault,
        buildingNumber: _buildingNumberController.text.trim(),
        floorNumber: _floorNumberController.text.trim(),
        apartmentNumber: _apartmentNumberController.text.trim(),
        phoneNumber: _phoneNumberController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
      );

      final updatedAddress = await widget.addressService.updateAddress(
        widget.editAddress!.id,
        updateRequest,
      );

      if (updatedAddress != null && mounted) {
        widget.onAddressSaved(updatedAddress);
        Navigator.pop(context);
      }
    } else {
      // Create new address
      final createRequest = AddressCreateRequest(
        name: _nameController.text.trim(),
        province: _provinceController.text.trim(),
        district: _districtController.text.trim(),
        neighborhood: _neighborhoodController.text.trim(),
        landmark: _landmarkController.text.trim(),
        detailedAddress: _detailedAddressController.text.trim(),
        addressType: _selectedType,
        isDefault: _isDefault,
        buildingNumber: _buildingNumberController.text.trim(),
        floorNumber: _floorNumberController.text.trim(),
        apartmentNumber: _apartmentNumberController.text.trim(),
        phoneNumber: _phoneNumberController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
      );

      final newAddress = await widget.addressService.createAddress(createRequest);

      if (newAddress != null && mounted) {
        widget.onAddressSaved(newAddress);
        Navigator.pop(context);
      }
    }
  }

  bool _validateForm() {
    if (_nameController.text.trim().isEmpty ||
        _provinceController.text.trim().isEmpty ||
        _districtController.text.trim().isEmpty ||
        _neighborhoodController.text.trim().isEmpty ||
        _landmarkController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ملء جميع الحقول المطلوبة'),
          backgroundColor: AppColors.primaryDark,
        ),
      );
      return false;
    }
    return true;
  }
}
