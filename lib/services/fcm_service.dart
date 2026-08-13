import 'dart:convert';

import 'package:crypthora_chat_wrapper/models/fcm_config.dart';
import 'package:crypthora_chat_wrapper/utils/disk_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Google FCM as an alternative to ntfy/UnifiedPush.
///
/// Unlike UnifiedPush this needs no companion app, which is what makes notifications survive doze
/// reliably. The Firebase config is not compiled in, it is fetched from the CrypthoraChat server
/// (see [fetchConfig]) and cached, so a single released apk works with any self hosted instance.
class FcmService {
  static const _configKey = 'fcm_config';
  static const _tokenKey = 'fcm_token';

  /// Asks a CrypthoraChat server for its Firebase config.
  ///
  /// Returns null when the server has no FCM set up (or isn't reachable), in which case FCM is
  /// simply not offered as a push provider.
  static Future<FcmConfig?> fetchConfig(String serverUrl) async {
    final baseUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/push-config'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        DiskLogger.warning(
          "[fcm_service] Push config request failed: ${response.statusCode}",
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final fcm = json['fcm'];
      if (fcm == null) {
        DiskLogger.debug("[fcm_service] Server has no FCM configured");
        return null;
      }

      return FcmConfig.fromJson(fcm as Map<String, dynamic>);
    } catch (e) {
      DiskLogger.error("[fcm_service] Error fetching push config: $e");
      return null;
    }
  }

  /// The config has to be on disk, the FCM background isolate initializes Firebase itself.
  static Future<void> saveConfig(FcmConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  static Future<FcmConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final json = prefs.getString(_configKey);
    if (json == null) return null;

    try {
      return FcmConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      DiskLogger.error("[fcm_service] Error parsing cached config: $e");
      return null;
    }
  }

  /// Initializes Firebase from the cached config. Safe to call more than once.
  static Future<bool> initialize() async {
    if (Firebase.apps.isNotEmpty) return true;

    final config = await loadConfig();
    if (config == null) {
      DiskLogger.warning("[fcm_service] No cached FCM config, cannot initialize");
      return false;
    }

    try {
      await Firebase.initializeApp(options: config.toFirebaseOptions());
      return true;
    } catch (e) {
      DiskLogger.error("[fcm_service] Error initializing Firebase: $e");
      return false;
    }
  }

  /// Requests notification permission, fetches the device token and stores it.
  static Future<String?> registerAndSaveToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        DiskLogger.error("[fcm_service] Got no FCM token");
        return null;
      }

      await saveToken(token);
      DiskLogger.debug("[fcm_service] Registered FCM token");
      return token;
    } catch (e) {
      DiskLogger.error("[fcm_service] Error registering FCM token: $e");
      return null;
    }
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_tokenKey);
  }

  /// Deletes the token on Firebase's side and locally, used when switching to another provider.
  static Future<void> unregister() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseMessaging.instance.deleteToken();
      }
    } catch (e) {
      DiskLogger.error("[fcm_service] Error deleting FCM token: $e");
    }
    await prefs.remove(_tokenKey);
    await prefs.remove(_configKey);
  }
}
