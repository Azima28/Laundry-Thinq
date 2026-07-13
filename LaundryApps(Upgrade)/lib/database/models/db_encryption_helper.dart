import 'dart:convert';

class DbEncryptionHelper {
  static const String _key = "AzimaSecretKey2026";

  static String encrypt(String val) {
    if (val.trim().isEmpty) return val;
    final valBytes = utf8.encode(val);
    final keyBytes = utf8.encode(_key);
    final xorBytes = List<int>.generate(valBytes.length, (i) => valBytes[i] ^ keyBytes[i % keyBytes.length]);
    return base64.encode(xorBytes);
  }

  static String decrypt(String val) {
    if (val.trim().isEmpty) return val;
    try {
      final xorBytes = base64.decode(val);
      final keyBytes = utf8.encode(_key);
      final valBytes = List<int>.generate(xorBytes.length, (i) => xorBytes[i] ^ keyBytes[i % keyBytes.length]);
      return utf8.decode(valBytes);
    } catch (_) {
      // Fallback to original value if decryption/decoding fails
      return val;
    }
  }
}
