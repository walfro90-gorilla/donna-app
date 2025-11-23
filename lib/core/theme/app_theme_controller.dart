import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global theme controller to switch between light and dark modes.
/// Keeps API minimal and avoids circular imports.
class AppThemeController {
  AppThemeController._();

  static const String _themeKey = 'theme_mode';
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Initialize and load saved theme preference
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themeKey);
      
      if (savedTheme == 'dark') {
        themeMode.value = ThemeMode.dark;
      } else if (savedTheme == 'light') {
        themeMode.value = ThemeMode.light;
      } else {
        themeMode.value = ThemeMode.system;
      }
    } catch (e) {
      debugPrint('⚠️ [THEME] Error loading theme preference: $e');
    }
  }

  /// Save theme preference to local storage
  static Future<void> _saveTheme(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String value;
      if (mode == ThemeMode.dark) {
        value = 'dark';
      } else if (mode == ThemeMode.light) {
        value = 'light';
      } else {
        value = 'system';
      }
      await prefs.setString(_themeKey, value);
    } catch (e) {
      debugPrint('⚠️ [THEME] Error saving theme preference: $e');
    }
  }

  static void set(ThemeMode mode) {
    themeMode.value = mode;
    _saveTheme(mode);
  }

  static void toggle() {
    final current = themeMode.value;
    final newMode = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    themeMode.value = newMode;
    _saveTheme(newMode);
  }
}
