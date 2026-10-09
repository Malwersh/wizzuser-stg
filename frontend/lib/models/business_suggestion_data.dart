/// فئة لحفظ بيانات المطعم المطلوبة لقسم الاقتراحات
class BusinessSuggestionData {
  final String businessId;
  final String businessName;
  final String? businessType;
  final List<String> availableCategories;
  
  const BusinessSuggestionData({
    required this.businessId,
    required this.businessName,
    this.businessType,
    required this.availableCategories,
  });
  
  /// التحقق من أن المطعم من نوع مطعم
  bool get isRestaurant {
    // إذا كان businessType فارغ أو null، افترض أنه مطعم (للتوافق مع البيانات القديمة)
    if (businessType == null || businessType!.isEmpty) return true;
    
    final type = businessType!.toLowerCase().trim();
    return type == 'restaurant' || 
           type == 'مطعم' || 
           type.contains('restaurant') || 
           type.contains('مطعم') ||
           type == 'food' ||
           type == 'cafe' ||
           type == 'مقهى';
  }
  
  /// الحصول على الفئات المطلوبة للاقتراحات
  static const List<String> suggestionCategories = [
    'Appetizers',
    'المقبلات',
    'Beverages', 
    'المشروبات',
    'Cold Drinks',
    'المشروبات الباردة',
    'Cookies',
    'البسكويت',
    'Desserts',
    'الحلويات',
    'Sides',
    'الأطباق الجانبية',
  ];
  
  /// الحصول على الفئات المتوفرة من الفئات المطلوبة فقط
  List<String> get suggestionAvailableCategories {
    return availableCategories.where((category) {
      return suggestionCategories.any((targetCategory) =>
          category.toLowerCase().contains(targetCategory.toLowerCase()) ||
          targetCategory.toLowerCase().contains(category.toLowerCase()));
    }).toList();
  }
  
  @override
  String toString() {
    return 'BusinessSuggestionData(businessId: $businessId, businessName: $businessName, businessType: $businessType, availableCategories: $availableCategories)';
  }
}
