import 'package:flutter/material.dart';

class CustomErrorScreen extends StatelessWidget {
  final FlutterErrorDetails? details;
  final Object? exception;
  final StackTrace? stackTrace;

  const CustomErrorScreen({
    super.key,
    this.details,
    this.exception,
    this.stackTrace,
  });

  String _getErrorCode() {
    // Generate a unique, readable error code for troubleshooting
    if (exception != null) {
      final code = exception.runtimeType.toString().toUpperCase();
      return 'CODE_$code';
    }
    if (details != null) {
      final code = details!.exception.runtimeType.toString().toUpperCase();
      return 'CODE_$code';
    }
    return 'CODE_UNKNOWN_FATAL';
  }

  String _getErrorMessage() {
    if (exception != null) {
      return exception.toString();
    }
    if (details != null) {
      return details!.exceptionAsString();
    }
    return 'Terjadi kesalahan sistem yang tidak diketahui.';
  }

  @override
  Widget build(BuildContext context) {
    final errorCode = _getErrorCode();
    final errorMessage = _getErrorMessage();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 80,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Terjadi Masalah',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E3A59),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Aplikasi mengalami error tak terduga. Untuk menjaga keamanan data Anda, silakan hubungi administrator.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8F9BB3),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEDF1F7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DIAGNOSTIC ERROR CODE:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8F9BB3),
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        errorCode,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'DETAIL ERROR:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8F9BB3),
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        errorMessage,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2E3A59),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    // Try to pop or push to dashboard if navigator works
                    try {
                      Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
                    } catch (_) {
                      // Fallback: If navigator fails, display an instructional popup
                      debugPrint('Error Screen recovery failed.');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4E80EE),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Kembali ke Beranda',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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
}
