/// One customer mobile-number contract for registration, addresses and checkout.
abstract final class IraqiPhone {
  static String ascii(String value) =>
      value.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
        final n = m[0]!.codeUnitAt(0);
        return '${n >= 0x6f0 ? n - 0x6f0 : n - 0x660}';
      });
  static String nationalInput(String value) {
    var n = ascii(value).replaceAll(RegExp(r'[\s()\-]'), '');
    if (n.startsWith('+964')) {
      n = n.substring(4);
    } else if (n.startsWith('00964')) {
      n = n.substring(5);
    } else if (n.startsWith('964')) {
      n = n.substring(3);
    }
    if (n.startsWith('07')) {
      n = n.substring(1);
    }
    return n;
  }

  static String normalize(String value) {
    final n = nationalInput(value);
    if (!RegExp(r'^7[0-9]{9}$').hasMatch(n)) {
      throw const FormatException('أدخل رقم هاتف عراقي صحيح');
    }
    return '+964$n';
  }

  static bool valid(String value) {
    try {
      normalize(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  // Preserve unknown, masked and foreign contacts rather than invent a country code.
  static String display(String value) =>
      valid(value) ? normalize(value) : value;
}
