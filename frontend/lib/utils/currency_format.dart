import 'package:intl/intl.dart';

/// Prices are already in Iraqi dinars; formatting never converts their value.
String formatIqd(num amount) =>
    '${NumberFormat('#,##0.###', 'en').format(amount)} د.ع';
