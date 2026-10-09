import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
// import '../services/session_service.dart'; // غير مستخدم مؤقتاً
import '../services/user_profile_service.dart';
import '../services/session_service.dart';

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String _selectedLanguage = 'ar'; // Arabic as default
  bool _isLoading = false;

  final Map<String, Map<String, String>> _languages = {
    'ar': {
      'name': 'العربية',
      'nativeName': 'العربية',
      'flag': '🇸🇦',
    },
    'en': {
      'name': 'English',
      'nativeName': 'English',
      'flag': '🇺🇸',
    },
    'ku': {
      'name': 'كوردي',
      'nativeName': 'کوردی',
      'flag': '🏴',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  Future<void> _loadCurrentLanguage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sessionData = await SessionService.instance.getUserData();
      final userId = sessionData?['user_id'] ?? '';
      
      if (userId.isNotEmpty) {
        // جلب اللغة الحالية من الخادم
        final profile = await UserProfileService.getUserProfile(userId);
        
        if (profile != null && profile['language_preference'] != null) {
          setState(() {
            _selectedLanguage = profile['language_preference'] ?? 'ar';
          });
        } else {
          setState(() {
            _selectedLanguage = 'ar'; // العربية كافتراضي
          });
        }
      } else {
        setState(() {
          _selectedLanguage = 'ar'; // العربية كافتراضي
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل إعدادات اللغة: $e'),
            backgroundColor: AppColors.primaryDark,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _changeLanguage(String languageCode) async {
    if (_selectedLanguage == languageCode) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final sessionData = await SessionService.instance.getUserData();
      final userId = sessionData?['userId'] ?? sessionData?['user_id'] ?? '';
      
      if (userId.isNotEmpty) {
        // حفظ اللغة الجديدة في الخادم
        final result = await UserProfileService.updateLanguagePreference(
          userId: userId,
          language: languageCode,
        );

        if (result['success'] == true) {
          setState(() {
            _selectedLanguage = languageCode;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم تغيير اللغة إلى ${_languages[languageCode]!['name']!}'),
                backgroundColor: AppColors.primary,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message']?.toString() ?? 'فشل في تغيير اللغة'),
                backgroundColor: AppColors.primaryDark,
              ),
            );
          }
        }
      } else {
        // حفظ محلي فقط إذا لم يكن المستخدم مسجل دخول
        setState(() {
          _selectedLanguage = languageCode;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تغيير اللغة إلى ${_languages[languageCode]!['name']!}'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تغيير اللغة: $e'),
            backgroundColor: AppColors.primaryDark,
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text(
            'إعدادات اللغة',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLanguageInfo(),
                    const SizedBox(height: 20),
                    _buildLanguageOptions(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLanguageInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.secondaryLight),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.secondaryDark),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'اختر اللغة المفضلة لعرض واجهة التطبيق',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOptions() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 6,
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
              'اللغات المتاحة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          ..._languages.entries.map((entry) => _buildLanguageTile(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildLanguageTile(String languageCode, Map<String, String> languageData) {
    final isSelected = _selectedLanguage == languageCode;
    
    return InkWell(
      onTap: _isLoading ? null : () => _changeLanguage(languageCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
          border: isSelected ? Border.all(color: AppColors.primary, width: 2) : null,
        ),
        child: Row(
          children: [
            Text(
              languageData['flag']!,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    languageData['name']!,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.primary : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    languageData['nativeName']!,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected ? AppColors.primary : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 24,
              ),
            if (!isSelected && !_isLoading)
              Icon(
                Icons.circle_outlined,
                color: Colors.grey[400],
                size: 24,
              ),
            if (_isLoading && _selectedLanguage == languageCode)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}