import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class CountrySettingsScreen extends StatefulWidget {
  const CountrySettingsScreen({super.key});

  @override
  State<CountrySettingsScreen> createState() => _CountrySettingsScreenState();
}

class _CountrySettingsScreenState extends State<CountrySettingsScreen> {
  String _selectedCountry = 'IQ'; // العراق كافتراضي
  bool _isLoading = false;

  final Map<String, Map<String, String>> _countries = {
    'IQ': {
      'name': 'العراق',
      'nativeName': 'العراق',
      'flag': '🇮🇶',
      'available': 'true',
    },
    'SA': {
      'name': 'السعودية',
      'nativeName': 'المملكة العربية السعودية',
      'flag': '🇸🇦',
      'available': 'false',
    },
    'AE': {
      'name': 'الإمارات',
      'nativeName': 'دولة الإمارات العربية المتحدة',
      'flag': '🇦🇪',
      'available': 'false',
    },
    'KW': {
      'name': 'الكويت',
      'nativeName': 'دولة الكويت',
      'flag': '🇰🇼',
      'available': 'false',
    },
    'QA': {
      'name': 'قطر',
      'nativeName': 'دولة قطر',
      'flag': '🇶🇦',
      'available': 'false',
    },
    'BH': {
      'name': 'البحرين',
      'nativeName': 'مملكة البحرين',
      'flag': '🇧🇭',
      'available': 'false',
    },
    'OM': {
      'name': 'عُمان',
      'nativeName': 'سلطنة عُمان',
      'flag': '🇴🇲',
      'available': 'false',
    },
    'JO': {
      'name': 'الأردن',
      'nativeName': 'المملكة الأردنية الهاشمية',
      'flag': '🇯🇴',
      'available': 'false',
    },
    'LB': {
      'name': 'لبنان',
      'nativeName': 'الجمهورية اللبنانية',
      'flag': '🇱🇧',
      'available': 'false',
    },
    'SY': {
      'name': 'سوريا',
      'nativeName': 'الجمهورية العربية السورية',
      'flag': '🇸🇾',
      'available': 'false',
    },
    'EG': {
      'name': 'مصر',
      'nativeName': 'جمهورية مصر العربية',
      'flag': '🇪🇬',
      'available': 'false',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentCountry();
  }

  Future<void> _loadCurrentCountry() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: تحميل الدولة الحالية من الإعدادات المحفوظة
      await Future.delayed(const Duration(seconds: 1));

      // بيانات تجريبية - يجب استبدالها بالبيانات الحقيقية
      setState(() {
        _selectedCountry = 'IQ'; // العراق كافتراضي
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل إعدادات الدولة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _changeCountry(String countryCode) async {
    // التحقق من توفر الخدمة في هذه الدولة
    if (_countries[countryCode]!['available'] == 'false') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خدماتنا غير متوفرة حالياً في ${_countries[countryCode]!['name']}',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    if (_selectedCountry == countryCode) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: حفظ الدولة الجديدة
      await Future.delayed(const Duration(seconds: 1));

      setState(() {
        _selectedCountry = countryCode;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تغيير الدولة إلى ${_countries[countryCode]!['name']}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تغيير الدولة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'إعدادات الدولة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        elevation: 0,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildCountrySelectionCard(),
                    const SizedBox(height: 20),
                    _buildInfoCard(),
                  ],
                ),
              ),
    );
  }

  Widget _buildCountrySelectionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'اختر دولتك',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          ..._countries.entries.map(
            (entry) => _buildCountryTile(
              countryCode: entry.key,
              countryData: entry.value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountryTile({
    required String countryCode,
    required Map<String, String> countryData,
  }) {
    final isSelected = _selectedCountry == countryCode;
    final isAvailable = countryData['available'] == 'true';

    return InkWell(
      onTap: () => _changeCountry(countryCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Text(
                  countryData['flag']!,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        countryData['name']!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color:
                              isSelected ? AppColors.primary : Colors.black87,
                        ),
                      ),
                      if (!isAvailable) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            'قريباً',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    countryData['nativeName']!,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: const Color(0xFF00296B),
                  size: 16,
                ),
              )
            else if (isAvailable)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  shape: BoxShape.circle,
                ),
              )
            else
              Icon(Icons.lock_outline, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.secondaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.secondary),
              const SizedBox(width: 10),
              Text(
                'معلومات مهمة:',
                style: TextStyle(
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoItem('خدماتنا متوفرة حالياً في العراق فقط'),
          _buildInfoItem('نعمل على توسيع خدماتنا لتشمل المزيد من الدول'),
          _buildInfoItem('سيتم إشعارك عند توفر الخدمة في دولتك'),
          _buildInfoItem('يمكنك تغيير الدولة في أي وقت من هذه الصفحة'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.secondaryDark, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
