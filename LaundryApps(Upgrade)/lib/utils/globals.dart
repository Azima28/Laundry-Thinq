import 'package:flutter/material.dart';

class Globals {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void showSuccessSnackBar(String message) {
    // Silenced success snackbar popup to prevent annoying notifications.
    debugPrint('SUCCESS_POPUP_SILENCED: $message');
  }

  static void showWarningSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: const Color(0xFFD97706),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static void showInfoSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF0284C7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static void showErrorSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
