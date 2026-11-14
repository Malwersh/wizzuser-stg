import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/session_service.dart';
import '../services/user_profile_service.dart';
import '../constants/app_colors.dart';
import 'notification_settings_screen.dart';

class PersonalInfoScreen extends StatefulWidget {
  final Future<Map<String, dynamic>?> Function(String)? profileLoader;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  profileSaver;
  final String? Function()? currentOwner;
  const PersonalInfoScreen({
    super.key,
    this.profileLoader,
    this.profileSaver,
    this.currentOwner,
  });

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  String? get _owner =>
      widget.currentOwner != null
          ? widget.currentOwner!()
          : SessionService.instance.currentUserId;

  // Controllers للمدخلات
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _birthdateController = TextEditingController();

  // متغيرات الحالة
  bool _isLoading = true;
  bool _isSaving = false;
  String? _userId;
  String _selectedGender = 'male';
  DateTime? _selectedDate;
  bool _profileLoaded = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    SessionService.instance.addListener(_sessionChanged);
    _loadUserData();
  }

  @override
  void dispose() {
    SessionService.instance.removeListener(_sessionChanged);
    _nameController.dispose();
    _birthdateController.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted || _userId == null || _owner == _userId) {
      return;
    }
    _nameController.clear();
    _birthdateController.clear();
    setState(() {
      _profileLoaded = false;
      _loadError =
          'تغيرت جلسة الحساب. ارجع إلى حسابي لفتح معلومات الحساب الحالي.';
    });
  }

  /// تحميل بيانات المستخدم من قاعدة البيانات
  Future<void> _loadUserData() async {
    final owner = _owner;
    setState(() {
      _isLoading = true;
      _profileLoaded = false;
      _loadError = null;
    });
    try {
      if (owner == null) throw StateError('AUTH_REQUIRED');
      final profile = await (widget.profileLoader ??
          UserProfileService.getUserProfile)(owner);
      if (!mounted) return;
      if (_owner != owner) {
        throw StateError('ACCOUNT_CHANGED');
      }
      if (profile == null) throw StateError('PROFILE_UNAVAILABLE');
      _userId = owner;
      _populateUserData(profile);
      _profileLoaded = true;
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _loadError =
                  'تعذر تحميل معلومات الحساب. أعد المحاولة قبل تعديلها.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ملء البيانات من استجابة قاعدة البيانات
  void _populateUserData(Map<String, dynamic> userProfile) {
    setState(() {
      _nameController.text =
          userProfile['name'] ?? userProfile['username'] ?? '';
      _birthdateController.text = userProfile['birthdate'] ?? '';
      _selectedGender = userProfile['gender'] ?? 'male';
      _selectedDate = null;

      // تحويل تاريخ الميلاد إلى DateTime إذا كان موجوداً
      if (userProfile['birthdate'] != null &&
          userProfile['birthdate'].isNotEmpty) {
        try {
          _selectedDate = DateTime.parse(userProfile['birthdate']);
        } catch (_) {
          _selectedDate = null;
        }
      }
    });
  }

  /// حفظ التحديثات في قاعدة البيانات
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_profileLoaded || _userId == null || _userId != _owner) {
      return;
    }

    try {
      setState(() {
        _isSaving = true;
      });

      final fields = <String, dynamic>{
        'name': _nameController.text.trim(),
        'birthdate': _birthdateController.text.trim(),
        'gender': _selectedGender,
      };
      final result =
          widget.profileSaver != null
              ? await widget.profileSaver!(_userId!, fields)
              : await UserProfileService.updatePersonalInfo(
                userId: _userId!,
                name: fields['name'],
                birthdate: fields['birthdate'],
                gender: fields['gender'],
              );

      if (!mounted || _userId != _owner) return;
      if (result['success'] == true) {
        _showSuccessDialog('تم حفظ التحديثات بنجاح');
      } else {
        _showErrorDialog(
          'فشل في حفظ التحديثات: ${result['message'] ?? 'خطأ غير معروف'}',
        );
      }
    } catch (e) {
      if (mounted) _showErrorDialog('تعذر حفظ المعلومات. أعد المحاولة.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// اختيار تاريخ الميلاد
  Future<void> _selectBirthdate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedDate ??
          DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ar', 'SA'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _birthdateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  /// عرض رسالة خطأ
  void _showErrorDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('خطأ', style: TextStyle(color: Colors.red)),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('حسناً'),
              ),
            ],
          ),
    );
  }

  /// عرض رسالة نجاح
  void _showSuccessDialog(String message) {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder:
          (sheetContext) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(0xFFEAF5EF),
                      child: Icon(
                        Icons.check_rounded,
                        color: Color(0xFF21754E),
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'تم حفظ التغييرات',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF00296B),
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF748198),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: const Color(0xFF00296B),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text(
                          'حسنًا',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'المعلومات الشخصية',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00296B),
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF00296B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body:
          _isLoading
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'جارٍ تحميل المعلومات...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
              : _loadError != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.secondaryDark),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _loadUserData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // بطاقة معلومات أساسية
                      _buildInfoCard(),
                      const SizedBox(height: 16),

                      // بطاقة التفضيلات
                      _buildPreferencesCard(),
                      const SizedBox(height: 24),

                      // زر الحفظ
                      _buildSaveButton(),
                    ],
                  ),
                ),
              ),
    );
  }

  /// بناء بطاقة المعلومات الأساسية
  Widget _buildInfoCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE5EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المعلومات الأساسية',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryDark,
              ),
            ),
            const SizedBox(height: 16),

            // حقل الاسم
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'الاسم الكامل',
                filled: true,
                fillColor: const Color(0xFFF5F6FA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                prefixIcon: Icon(Icons.person, color: AppColors.secondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.secondary, width: 2),
                ),
                labelStyle: TextStyle(color: AppColors.secondary),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال الاسم الكامل';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // حقل تاريخ الميلاد
            TextFormField(
              controller: _birthdateController,
              readOnly: true,
              onTap: _selectBirthdate,
              decoration: InputDecoration(
                labelText: 'تاريخ الميلاد',
                filled: true,
                fillColor: const Color(0xFFF5F6FA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                hintText: 'اختر تاريخ الميلاد',
                prefixIcon: Icon(
                  Icons.calendar_today,
                  color: AppColors.secondary,
                ),
                suffixIcon: Icon(
                  Icons.arrow_drop_down,
                  color: AppColors.secondary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.secondary, width: 2),
                ),
                labelStyle: TextStyle(color: AppColors.secondary),
              ),
            ),
            const SizedBox(height: 16),

            // اختيار الجنس
            const Text(
              'الجنس',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryDark,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                border: Border.all(color: const Color(0xFFE5EAF2)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGender,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: AppColors.secondary),
                  items: [
                    DropdownMenuItem(
                      value: 'male',
                      child: Row(
                        children: [
                          Icon(Icons.male, color: AppColors.secondary),
                          SizedBox(width: 8),
                          Text('ذكر'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'female',
                      child: Row(
                        children: [
                          Icon(Icons.female, color: AppColors.secondary),
                          SizedBox(width: 8),
                          Text('أنثى'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedGender = value;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء بطاقة التفضيلات
  Widget _buildPreferencesCard() => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xFFE5EAF2)),
    ),
    child: ListTile(
      leading: const Icon(
        Icons.notifications_outlined,
        color: AppColors.secondaryDark,
      ),
      title: const Text(
        'العروض وإعدادات الإشعارات',
        style: TextStyle(color: AppColors.secondaryDark),
      ),
      subtitle: const Text('إدارة موافقتك على إشعارات العروض والخصومات'),
      trailing: const Icon(
        Icons.chevron_left,
        textDirection: ui.TextDirection.ltr,
        color: AppColors.secondaryDark,
      ),
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NotificationSettingsScreen(),
            ),
          ),
    ),
  );

  /// بناء زر الحفظ
  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving || !_profileLoaded ? null : _saveProfile,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      child:
          _isSaving
              ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'جارٍ الحفظ...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              )
              : const Text(
                'حفظ التغييرات',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
    );
  }
}
