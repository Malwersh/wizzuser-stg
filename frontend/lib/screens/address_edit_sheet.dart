import '../utils/readable_colors.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AddressEditSheet extends StatefulWidget {
  final String city;
  final String area;
  final String district;
  final String landmark;
  final void Function(String, String, String, String) onSave;
  const AddressEditSheet({
    super.key,
    required this.city,
    required this.area,
    required this.district,
    required this.landmark,
    required this.onSave,
  });

  @override
  State<AddressEditSheet> createState() => _AddressEditSheetState();
}

class _AddressEditSheetState extends State<AddressEditSheet> {
  late TextEditingController _cityController;
  late TextEditingController _areaController;
  late TextEditingController _districtController;
  late TextEditingController _landmarkController;

  @override
  void initState() {
    super.initState();
    _cityController = TextEditingController(text: widget.city);
    _areaController = TextEditingController(text: widget.area);
    _districtController = TextEditingController(text: widget.district);
    _landmarkController = TextEditingController(text: widget.landmark);
  }

  @override
  void dispose() {
    _cityController.dispose();
    _areaController.dispose();
    _districtController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(labelText: 'المحافظة'),
            ),
            TextField(
              controller: _areaController,
              decoration: const InputDecoration(labelText: 'القضاء أو الناحية'),
            ),
            TextField(
              controller: _districtController,
              decoration: const InputDecoration(labelText: 'الحي'),
            ),
            TextField(
              controller: _landmarkController,
              decoration: const InputDecoration(
                labelText: 'أقرب نقطة دالة للسائق',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: readableForeground(AppColors.primary),
                backgroundColor: AppColors.primary,
              ),
              onPressed: () {
                widget.onSave(
                  _cityController.text,
                  _areaController.text,
                  _districtController.text,
                  _landmarkController.text,
                );
                Navigator.pop(context);
              },
              child: const Text(
                'حفظ',
                style: TextStyle(
                  color: const Color(0xFF00296B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
