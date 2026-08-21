import 'package:flutter/services.dart';

/// Format angka ke format Rupiah dengan titik pemisah ribuan.
/// Contoh: formatRp(10000) => 'Rp 10.000'
/// Contoh: formatRp(-5000) => '- Rp 5.000'
String formatRp(int amount) {
  bool isNeg = amount < 0;
  String s = amount.abs().toString();
  String result = '';
  int count = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    result = s[i] + result;
    count++;
    if (count == 3 && i > 0) {
      result = '.$result';
      count = 0;
    }
  }
  return '${isNeg ? '- ' : ''}Rp $result';
}

/// Format angka biasa dengan titik pemisah ribuan (tanpa prefix Rp).
/// Contoh: formatNumber(10000) => '10.000'
String formatNumber(int amount) {
  String s = amount.abs().toString();
  String result = '';
  int count = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    result = s[i] + result;
    count++;
    if (count == 3 && i > 0) {
      result = '.$result';
      count = 0;
    }
  }
  return amount < 0 ? '-$result' : result;
}

/// Formatter input real-time dengan titik pemisah ribuan untuk TextFormField / TextField uang tunai.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static String format(String digitsOnly) {
    if (digitsOnly.isEmpty) return '';
    final number = int.tryParse(digitsOnly) ?? 0;
    if (number == 0) return '0';
    final s = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    final formatted = format(digitsOnly);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
