// lib/widgets/address_search_delegate.dart

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/address_service.dart';
import '../models/address_model.dart';

class AddressSearchDelegate extends SearchDelegate<DetailedAddress?> {
  final EnhancedAddressService addressService;
  final Function(DetailedAddress) onAddressSelected;

  AddressSearchDelegate({
    required this.addressService,
    required this.onAddressSelected,
  });

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          query = '';
        },
        icon: const Icon(Icons.clear),
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () {
        close(context, null);
      },
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.isEmpty) {
      return const Center(
        child: Text('ابحث عن عنوان...'),
      );
    }

    final results = addressService.detailedAddresses
        .where((address) =>
            address.name.toLowerCase().contains(query.toLowerCase()) ||
            address.fullAddress.toLowerCase().contains(query.toLowerCase()))
        .toList();

    if (results.isEmpty) {
      return const Center(
        child: Text('لا توجد نتائج'),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final address = results[index];
        return _buildAddressListItem(context, address);
      },
    );
  }

  Widget _buildAddressListItem(BuildContext context, DetailedAddress address) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _getAddressTypeColor(address.addressType),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getAddressTypeIcon(address.addressType),
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Text(address.name),
      subtitle: Text(
        address.fullAddress,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        close(context, address);
        onAddressSelected(address);
      },
    );
  }

  Color _getAddressTypeColor(String type) {
    switch (type) {
      case 'home':
        return Colors.green;
      case 'work':
        return Colors.blue;
      case 'other':
        return AppColors.primary;
      case 'current':
        return Colors.purple;
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
