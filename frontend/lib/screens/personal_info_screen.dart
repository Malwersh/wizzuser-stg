import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/session_service.dart';
import '../services/user_profile_service.dart';
import '../constants/app_colors.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
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
  bool _marketingConsent = false;
  bool _newsletterSubscription = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthdateController.dispose();
    super.dispose();
  }

  /// تحميل بيانات المستخدم من قاعدة البيانات
  Future<void> _loadUserData() async {
    try {
      setState(() {
        _isLoading = true;
      });


      // الحصول على معرف المستخدم من الجلسة الحالية
      final userData = await SessionService.instance.getUserData();
      if (userData == null) {
        print('❌ لا توجد بيانات جلسة للمستخدم');
        _showErrorDialog('لا توجد بيانات جلسة صالحة');
        return;
      }

      // ✅ إصلاح: استخراج userId بالترتيب الصحيح مع دعم البيانات المتداخلة
      String? extractedUserId;
      
      // البحث في المواقع المختلفة بالترتيب الأفضل
      if (userData['userId'] != null) {
        extractedUserId = userData['userId'].toString();
      } else if (userData['user_id'] != null) {
        extractedUserId = userData['user_id'].toString();
      } else if (userData['user'] != null && userData['user']['userId'] != null) {
        extractedUserId = userData['user']['userId'].toString();
      } else if (userData['id'] != null) {
        extractedUserId = userData['id'].toString();
      } else if (userData['email'] != null) {
        extractedUserId = userData['email'].toString();
        print('⚠️ استخدام email كـ userId: $extractedUserId');
      }
      
      _userId = extractedUserId;
      print('👤 بيانات المستخدم الكاملة: $userData');
      print('👤 معرف المستخدم المستخرج: $_userId');

      if (_userId == null || _userId!.isEmpty) {
        print('❌ معرف المستخدم غير صالح');
        _showErrorDialog('معرف المستخدم غير صالح');
        return;
      }

      // التحقق من أن userId ليس placeholder
      if (_userId == 'placeholder_user_id' || _userId == 'default_user_id') {
        print('⚠️ تحذير: معرف المستخدم هو placeholder، استخدام بيانات افتراضية');
        _showErrorDialog('معرف المستخدم غير صحيح، يرجى تسجيل الدخول مرة أخرى');
        return;
      }

      // جلب البيانات من جدول WizzUser_users_dev
      final userProfile = await UserProfileService.getUserProfile(_userId!);
      
      if (userProfile != null) {
        _populateUserData(userProfile);
      } else {
        print('⚠️ لم يتم العثور على بيانات المستخدم في قاعدة البيانات');
        // إضافة تشخيص إضافي للبيانات الأساسية
        print('🔍 بيانات الجلسة الحالية: $userData');
        
        // محاولة ملء البيانات من الجلسة نفسها كبديل
        final basicProfile = {
          'id': _userId,
          'name': userData['name'] ?? 'المستخدم',
          'email': userData['email'] ?? '',
          'phone': userData['phone'] ?? '',
          'gender': 'male',
          'birthdate': '',
          'marketing_consent': false,
          'newsletter_subscription': false,
        };
        
        _populateUserData(basicProfile);
        
        // عرض تحذير للمستخدم
        _showErrorDialog('تم تحميل بيانات أساسية. قد تحتاج لإعادة تسجيل الدخول للحصول على البيانات الكاملة.');
      }

    } catch (e) {
      print('❌ خطأ في تحميل البيانات: $e');
      _showErrorDialog('خطأ في تحميل البيانات: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// ملء البيانات من استجابة قاعدة البيانات
  void _populateUserData(Map<String, dynamic> userProfile) {
    setState(() {
      _nameController.text = userProfile['name'] ?? userProfile['username'] ?? '';
      _birthdateController.text = userProfile['birthdate'] ?? '';
      _selectedGender = userProfile['gender'] ?? 'male';
      _marketingConsent = userProfile['marketing_consent'] ?? false;
      _newsletterSubscription = userProfile['newsletter_subscription'] ?? false;
      
      // تحويل تاريخ الميلاد إلى DateTime إذا كان موجوداً
      if (userProfile['birthdate'] != null && userProfile['birthdate'].isNotEmpty) {
        try {
          _selectedDate = DateTime.parse(userProfile['birthdate']);
        } catch (e) {
          print('❌ خطأ في تحليل تاريخ الميلاد: $e');
        }
      }
    });
    
    print('📊 تم تحميل البيانات:');
    print('  - الاسم: ${_nameController.text}');
    print('  - تاريخ الميلاد: ${_birthdateController.text}');
    print('  - الجنس: $_selectedGender');
    print('  - موافقة التسويق: $_marketingConsent');
    print('  - اشتراك النشرة: $_newsletterSubscription');
  }

  /// حفظ التحديثات في قاعدة البيانات
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userId == null) return;

    try {
      setState(() {
        _isSaving = true;
      });

      print('💾 حفظ التحديثات للمستخدم: $_userId');

      final result = await UserProfileService.updatePersonalInfo(
        userId: _userId!,
        name: _nameController.text.trim(),
        birthdate: _birthdateController.text.trim(),
        gender: _selectedGender,
        marketingConsent: _marketingConsent,
        newsletterSubscription: _newsletterSubscription,
      );

      if (result['success'] == true && mounted) {
        _showSuccessDialog('تم حفظ التحديثات بنجاح');
      } else {
        print('❌ فشل في حفظ التحديثات: ${result['message']}');
        _showErrorDialog('فشل في حفظ التحديثات: ${result['message'] ?? 'خطأ غير معروف'}');
      }

    } catch (e) {
      print('❌ خطأ في حفظ البيانات: $e');
      _showErrorDialog('خطأ في حفظ البيانات: $e');
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
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
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
      builder: (context) => AlertDialog(
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
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم بنجاح', style: TextStyle(color: Colors.green)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'المعلومات الشخصية',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'جارٍ تحميل المعلومات...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المعلومات الأساسية',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            
            // حقل الاسم
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'الاسم الكامل',
                prefixIcon: Icon(Icons.person, color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                labelStyle: TextStyle(color: AppColors.primary),
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
                hintText: 'اختر تاريخ الميلاد',
                prefixIcon: Icon(Icons.calendar_today, color: AppColors.primary),
                suffixIcon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                labelStyle: TextStyle(color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            
            // اختيار الجنس
            const Text(
              'الجنس',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGender,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                  items: [
                    DropdownMenuItem(
                      value: 'male',
                      child: Row(
                        children: [
                          Icon(Icons.male, color: AppColors.primary),
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
  Widget _buildPreferencesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'التفضيلات والإشعارات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            
            // موافقة التسويق
            SwitchListTile(
              title: const Text('استقبال رسائل التسويق'),
              subtitle: const Text('الحصول على عروض وخصومات خاصة'),
              value: _marketingConsent,
              activeColor: AppColors.secondary,
              onChanged: (bool value) {
                setState(() {
                  _marketingConsent = value;
                });
              },
              secondary: Icon(Icons.campaign, color: AppColors.secondary),
            ),
            const Divider(),
            
            // اشتراك النشرة الإخبارية
            SwitchListTile(
              title: const Text('النشرة الإخبارية'),
              subtitle: const Text('تلقي آخر الأخبار والتحديثات'),
              value: _newsletterSubscription,
              activeColor: AppColors.secondary,
              onChanged: (bool value) {
                setState(() {
                  _newsletterSubscription = value;
                });
              },
              secondary: Icon(Icons.email, color: AppColors.secondary),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء زر الحفظ
  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveProfile,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
      child: _isSaving
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
