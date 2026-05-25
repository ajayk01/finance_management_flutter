import 'package:intl/intl.dart';

final NumberFormat inrFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final NumberFormat inrFormatNoDecimal = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String formatINR(double amount, {int decimals = 2}) {
  if (decimals == 0) return inrFormatNoDecimal.format(amount);
  return inrFormat.format(amount);
}
