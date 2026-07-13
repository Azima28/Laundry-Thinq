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
