# Flutter rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Prevent obfuscation of models to ensure JSON parsing works
-keep class com.laundry_apps.database.models.** { *; }

# If you use sqflite
-keep class com.tekartik.sqflite.** { *; }

# Ignore warnings for missing Play Core classes (common in Flutter R8 builds)
-dontwarn com.google.android.play.core.**

