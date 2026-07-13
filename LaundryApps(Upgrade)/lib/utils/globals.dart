import 'package:flutter/material.dart';

class Globals {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void showSuccessSnackBar(String message) {
    // Silenced success snackbar popup to prevent annoying notifications.
    debugPrint('SUCCESS_POPUP_SILENCED: $message');
  }

  static void showErrorSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
