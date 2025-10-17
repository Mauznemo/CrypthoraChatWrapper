import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class I18nHelper {
  static Map<String, dynamic>? _translations;
  static String _locale = 'en';

  /// Load the translation file for the given locale
  static Future<void> load(
    String locale, [
    Map<String, dynamic>? translations,
  ]) async {
    _locale = locale;
    debugPrint('[i18n_helper] Setting locale to $locale');
    if (translations == null) {
      final jsonStr = await rootBundle.loadString('assets/i18n/$locale.json');
      _translations = json.decode(jsonStr) as Map<String, dynamic>;
    } else {
      debugPrint('[i18n_helper] Setting translations to custom set');
      _translations = translations;
    }
  }

  /// Get a translation by key
  ///optionally provide variables for placeholders.
  static String t(String key, [Map<String, String>? vars]) {
    if (_translations == null) {
      debugPrint('[i18n_helper] No translations loaded, returning key: $key');
      return key;
    }

    final value = _resolveKey(_translations!, key);
    if (value == null) return key;

    if (vars != null && vars.isNotEmpty) {
      return _replaceVars(value, vars);
    }

    return value;
  }

  static dynamic _resolveKey(Map<String, dynamic> map, String key) {
    final parts = key.split('.');
    dynamic value = map;
    for (final part in parts) {
      if (value is Map<String, dynamic> && value.containsKey(part)) {
        value = value[part];
      } else {
        return null;
      }
    }
    return value;
  }

  static String _replaceVars(String text, Map<String, String> vars) {
    var result = text;
    vars.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }

  static String get locale => _locale;

  static Future<void> saveCurrentLocale(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final locale = await FlutterI18n.currentLocale(context);
    await prefs.setString('locale', locale?.languageCode ?? 'en');
  }
}
