import 'package:flutter/material.dart';

class StyleConstants {
  // Brand & Accent Colors
  static const Color primaryColor = Color(0xFF3B82F6); // Modern Blue
  static const Color secondaryColor = Color(0xFF6366F1); // Indigo
  static const Color backgroundColor = Color(0xFFF8FAFC); // Very light grey/blue slate background
  static const Color cardColor = Colors.white;
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200 border
  
  // Status Colors
  static const Color successColor = Color(0xFF10B981); // Emerald
  static const Color warningColor = Color(0xFFF59E0B); // Amber
  static const Color dangerColor = Color(0xFFEF4444); // Coral/Red

  // Gradients for modern UI accents
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sidebarGradient = LinearGradient(
    colors: [Color(0xFF0B0F19), Color(0xFF1E293B)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Layout density parameters
  static const double densePadding = 16.0;
  static const double standardPadding = 24.0;

  // Typography definitions (clean modern sizing, slightly larger where needed)
  static const TextStyle titleLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Color(0xFF0F172A),
    letterSpacing: 0.5,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Color(0xFF0F172A),
    letterSpacing: 0.2,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
    color: Color(0xFF1E293B),
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.normal,
    color: Color(0xFF334155),
    height: 1.4,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFF475569),
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.normal,
    color: Color(0xFF64748B),
  );

  static const TextStyle badgeStyle = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.3,
  );

  // Reusable input decoration base
  static InputDecoration inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      floatingLabelStyle: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
