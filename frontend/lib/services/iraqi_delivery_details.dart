class IraqiDeliveryDetails {
  static bool meaningful(String? value) {
    final v = (value ?? '').trim();
    return v.length >= 2 &&
        ![
          '-',
          'غير محدد',
          'غير متوفر',
          'موقع محدد من الخريطة',
          'عنوان غير محدد',
        ].contains(v) &&
        RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(v);
  }

  static String? validateNeighborhood(String? value) =>
      meaningful(value) ? null : 'اكتب اسم الحي أو المحلة';
  static String? validateLandmark(String? value) =>
      meaningful(value) ? null : 'اكتب أقرب نقطة دالة واضحة';
}
