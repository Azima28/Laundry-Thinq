import 'package:flutter/material.dart';

class StyleConstants {
  // --- BRAND & CORE PALETTE (SLATE & BLUE ENTERPRISE) ---
  static const Color primaryColor = Color(0xFF2563EB);      // Blue 600 (Primary Action)
  static const Color primaryHover = Color(0xFF1D4ED8);      // Blue 700
  static const Color secondaryColor = Color(0xFF4F46E5);    // Indigo 600
  static const Color accentCyan = Color(0xFF06B6D4);        // Cyan 500

  // --- SURFACE & BACKGROUNDS ---
  static const Color backgroundColor = Color(0xFFF8FAFC);  // Slate 50 (App Ground)
  static const Color cardColor = Color(0xFFFFFFFF);        // Pure White
  static const Color subSurface = Color(0xFFF1F5F9);        // Slate 100
  static const Color sidebarBackground = Color(0xFF0F172A); // Slate 900
  static const Color darkSurface = Color(0xFF1E293B);       // Slate 800

  // --- BORDER & LINES ---
  static const Color borderLight = Color(0xFFE2E8F0);       // Slate 200 (Hairline 1px)
  static const Color borderMedium = Color(0xFFCBD5E1);      // Slate 300
  static const Color borderFocus = Color(0xFF3B82F6);       // Blue 500 (Focus ring)

  // --- STATUS COLORS (WCAG 2.1 AAA Compliant) ---
  static const Color successColor = Color(0xFF10B981);      // Emerald 500
  static const Color warningColor = Color(0xFFF59E0B);      // Amber 500
  static const Color dangerColor = Color(0xFFEF4444);       // Red 500
  static const Color infoColor = Color(0xFF0EA5E9);         // Sky 500

  // Soft Backgrounds for Badges & Alerts
  static const Color statusSuccessBg = Color(0xFFECFDF5);   // Emerald 50
  static const Color statusSuccessText = Color(0xFF047857); // Emerald 700
  static const Color statusWarningBg = Color(0xFFFFFBEB);   // Amber 50
  static const Color statusWarningText = Color(0xFFB45309); // Amber 700
  static const Color statusDangerBg = Color(0xFFFEF2F2);    // Red 50
  static const Color statusDangerText = Color(0xFFB91C1C);  // Red 700
  static const Color statusInfoBg = Color(0xFFF0F9FF);      // Sky 50
  static const Color statusInfoText = Color(0xFF0369A1);    // Sky 700

  // --- TEXT INK TOKENS ---
  static const Color textHeading = Color(0xFF0F172A);       // Slate 900
  static const Color textBody = Color(0xFF334155);          // Slate 700
  static const Color textMuted = Color(0xFF64748B);         // Slate 500
  static const Color textOnDark = Color(0xFFF8FAFC);        // Slate 50

  // --- GRADIENTS FOR PREMIUM ACCENTS ---
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sidebarGradient = LinearGradient(
    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient kpiCardGradient = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // --- DESKTOP LAYOUT SIZING CONSTANTS ---
  static const double sidebarExpandedWidth = 240.0;
  static const double sidebarCollapsedWidth = 68.0;
  static const double topBarHeight = 60.0;
  static const double bottomBarHeight = 28.0;
  static const double posReceiptWidth = 380.0;
  static const double densePadding = 16.0;
  static const double standardPadding = 24.0;
  static const double cardRadius = 14.0;

  // --- TYPOGRAPHY DEFINITIONS ---
  static const TextStyle displayLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: textHeading,
    letterSpacing: -0.6,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: textHeading,
    letterSpacing: -0.4,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textHeading,
    letterSpacing: -0.2,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: textHeading,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textBody,
    height: 1.45,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textBody,
    height: 1.4,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textMuted,
    letterSpacing: 0.2,
  );

  static const TextStyle badgeStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
  );

  // Tabular numeric font for financial alignment
  static TextStyle tabularNumbers({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
    Color color = textHeading,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: -0.2,
    );
  }

  // --- SHADOW & CARD DECORATIONS ---
  static BoxDecoration cardDecoration({
    Color background = cardColor,
    BorderRadius? borderRadius,
    Border? border,
    bool withShadow = true,
  }) {
    return BoxDecoration(
      color: background,
      borderRadius: borderRadius ?? BorderRadius.circular(cardRadius),
      border: border ?? Border.all(color: borderLight, width: 1),
      boxShadow: withShadow
          ? [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );
  }

  // --- REUSABLE INPUT DECORATION BASE ---
  static InputDecoration inputDecoration(
    String label,
    IconData? icon, {
    String? hintText,
    Widget? suffixIcon,
    String? prefixText,
    bool isDense = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixText: prefixText,
      isDense: isDense,
      labelStyle: const TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(color: primaryColor, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderFocus, width: 2),
      ),
      prefixIcon: icon != null ? Icon(icon, color: textMuted, size: 18) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: isDense ? 12 : 14,
      ),
    );
  }

  // --- REUSABLE STATUS BADGE WIDGET HELPER ---
  static Widget statusBadge({
    required String text,
    IconData? icon,
    required Color backgroundColor,
    required Color textColor,
    double fontSize = 11,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
