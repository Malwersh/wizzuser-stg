// lib/screens/address_selection_screen.dart
import '../constants/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/address_model.dart';
import '../services/address_service.dart';

class AddressSelectionScreen extends StatefulWidget {
  final DetailedAddress? currentAddress;
  final String? regionId;
  final bool savedOnly;

  const AddressSelectionScreen({
    super.key,
    this.currentAddress,
    this.regionId,
    this.savedOnly=false,
  });

  @override
  State<AddressSelectionScreen> createState() => _AddressSelectionScreenState();
}

class _AddressSelectionScreenState extends State<AddressSelectionScreen> {
  late EnhancedAddressService _addressService;
  DetailedAddress? _selectedAddress;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedAddress = widget.currentAddress;
    _initializeAddressService();
  }

  void _initializeAddressService() {
    _addressService = Provider.of<EnhancedAddressService>(context, listen: false);
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      await _addressService.fetchAddresses();
      
      // If no address is selected but there's a default address, select it
      if (_selectedAddress == null && _addressService.defaultAddress != null && (widget.regionId==null||_addressService.defaultAddress!.regionId==widget.regionId)) {
        _selectedAddress = _addressService.defaultAddress;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل العناوين: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('اختيار العنوان'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            TextButton(
              onPressed: _selectedAddress != null
                  ? () => Navigator.pop(context, _selectedAddress)
                  : null,
              child: Text(
                'تأكيد',
                style: TextStyle(
                  color: _selectedAddress != null
                      ? AppColors.primary
                      : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? _buildLoadingState()
            : Consumer<EnhancedAddressService>(
                builder: (context, addressService, child) {
                  return _buildAddressList(addressService);
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddAddressDialog(),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          icon: const Icon(Icons.add),
          label: const Text('إضافة عنوان جديد'),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          SizedBox(height: 16),
          Text(
            'جاري تحميل العناوين...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressList(EnhancedAddressService addressService) {
    final addresses = addressService.detailedAddresses.where((a)=>widget.regionId==null||a.regionId==widget.regionId).toList();

    if (addresses.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: addresses.length + (widget.savedOnly?0:1), // +1 for current location option
      itemBuilder: (context, index) {
        if (!widget.savedOnly && index == 0) {
          return _buildCurrentLocationTile();
        }
        
        final address = addresses[index - (widget.savedOnly?0:1)];
        return _buildAddressTile(address);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد عناوين محفوظة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'أضف عنواناً جديداً للمتابعة',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddAddressDialog(),
            icon: const Icon(Icons.add),
            label: const Text('إضافة عنوان جديد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLocationTile() {
    return Consumer<EnhancedAddressService>(
      builder: (context, addressService, child) {
        final currentLocation = addressService.currentLocationAddress;
        final isSelected = _selectedAddress?.addressType == AddressType.current;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected 
                  ? AppColors.primary 
                  : Colors.grey.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.my_location,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            title: const Text(
              'الموقع الحالي',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  currentLocation?.fullAddress ?? 'جاري تحديد الموقع...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (addressService.isLoadingLocation) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ],
              ],
            ),
            trailing: Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: addressService.isLoadingLocation 
                  ? null 
                  : (value) {
                      if (currentLocation != null) {
                        setState(() {
                          _selectedAddress = currentLocation;
                        });
                      } else {
                        _requestCurrentLocation();
                      }
                    },
              activeColor: AppColors.primary,
            ),
            onTap: addressService.isLoadingLocation 
                ? null 
                : () {
                    if (currentLocation != null) {
                      setState(() {
                        _selectedAddress = currentLocation;
                      });
                    } else {
                      _requestCurrentLocation();
                    }
                  },
          ),
        );
      },
    );
  }

  Widget _buildAddressTile(DetailedAddress address) {
    final isSelected = _selectedAddress?.id == address.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected 
              ? AppColors.primary 
              : Colors.grey.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getAddressTypeColor(address.addressType).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            _getAddressTypeIcon(address.addressType),
            color: _getAddressTypeColor(address.addressType),
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Text(
              address.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (address.isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'افتراضي',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              address.fullAddress,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (address.landmark.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'قرب ${address.landmark}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        trailing: Radio<String>(
          value: address.id,
          groupValue: _selectedAddress?.id,
          onChanged: (value) {
            setState(() {
              _selectedAddress = address;
            });
          },
          activeColor: AppColors.primary,
        ),
        onTap: () {
          setState(() {
            _selectedAddress = address;
          });
        },
      ),
    );
  }

  void _requestCurrentLocation() async {
    try {
      await _addressService.getCurrentLocationAddress();
      setState(() {
        _selectedAddress = _addressService.currentLocationAddress;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحديد الموقع الحالي: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddAddressDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ميزة إضافة عنوان جديد ستكون متاحة قريباً'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Color _getAddressTypeColor(String addressType) {
    switch (addressType) {
      case AddressType.home:
        return Colors.blue;
      case AddressType.work:
        return AppColors.primary;
      case AddressType.current:
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  IconData _getAddressTypeIcon(String addressType) {
    switch (addressType) {
      case AddressType.home:
        return Icons.home;
      case AddressType.work:
        return Icons.work;
      case AddressType.current:
        return Icons.my_location;
      default:
        return Icons.location_on;
    }
  }
}
