import 'dart:async';
import 'dart:convert';

import 'package:crypthora_chat_wrapper/i18n/strings.g.dart';
import 'package:crypthora_chat_wrapper/services/fcm_service.dart';
import 'package:crypthora_chat_wrapper/utils/disk_logger.dart';
import 'package:crypthora_chat_wrapper/utils/utils.dart';
import 'package:crypthora_chat_wrapper/utils/image_cache.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' hide ImageCache;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:person_shortcut_creator/person_shortcut_creator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';

/// Entry point for FCM messages that arrive while the app isn't running.
///
/// This runs in its own isolate spawned by the FCM plugin, so Firebase has to be initialized again
/// from the cached config. UnifiedPush has its own equivalent, it re-runs `main()` with
/// `--unifiedpush-bg`.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  if (!await FcmService.initialize()) return;
  await PushService().handlePayload(message.data);
}

/// The push transport the user picked on [AddServerPage], stored under `push_provider`.
///
/// Anything that isn't [fcm] is a UnifiedPush distributor name (usually the ntfy app).
class PushProvider {
  static const fcm = 'fcm';

  static Future<String?> get current async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString('push_provider');
  }

  static Future<bool> get isFcm async => await current == fcm;

  static Future<void> save(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('push_provider', provider);
  }
}

/// Receives pushes over whichever transport is active and turns them into local notifications.
///
/// Both transports funnel into [handlePayload], so the notification building (coalescing bursts per
/// chat, unread counts, conversation shortcuts) is identical no matter where the message came from.
class PushService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final _instance = 'crypthora_chat';
  static StreamSubscription<RemoteMessage>? _fcmSub;

  /// Sets up only the transport the user selected.
  Future<void> init() async {
    if (await PushProvider.isFcm) {
      await initFcm();
      return;
    }

    await initUnifiedPush();
  }

  Future<void> initUnifiedPush() async {
    await UnifiedPush.initialize(
      onNewEndpoint: onNewEndpoint,
      onRegistrationFailed: onRegistrationFailed,
      onUnregistered: onUnregistered,
      onMessage: onMessage,
    ).then((registered) {
      if (registered) {
        register();
      }
    });
  }

  /// Wires up both foreground and background FCM messages.
  ///
  /// Also called right after the user switches to FCM, so notifications work without an app restart.
  Future<bool> initFcm() async {
    if (!await FcmService.initialize()) return false;

    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    _fcmSub?.cancel();
    _fcmSub = FirebaseMessaging.onMessage.listen((message) {
      DiskLogger.debug("[push_service] Received FCM message: ${message.data}");
      handlePayload(message.data);
    });
    return true;
  }

  static Future<void> register() async {
    await UnifiedPush.register(instance: _instance);
  }

  static Future<void> unregister() async {
    await UnifiedPush.unregister(_instance);
  }

  void onNewEndpoint(PushEndpoint endpoint, String instance) {
    DiskLogger.debug("[push_service] New endpoint: ${endpoint.url}");

    saveEndpoint(endpoint);
  }

  void onRegistrationFailed(FailedReason reason, String instance) {
    DiskLogger.error("[push_service] Registration failed");
  }

  void onUnregistered(String instance) {
    DiskLogger.debug("Unregistered");
  }

  Future<void> onMessage(PushMessage message, String instance) async {
    String messageText = utf8.decode(message.content);
    DiskLogger.debug("[push_service] Received message: $messageText");
    try {
      await handlePayload(jsonDecode(messageText) as Map<String, dynamic>);
    } catch (e) {
      DiskLogger.error("[push_service] Error parsing message: $e");
    }
  }

  /// Handles a notification payload from either transport.
  ///
  /// The payload is metadata only, it never contains message content. FCM delivers every data value
  /// as a string while ntfy sends real JSON, so [timestamp] is coerced rather than cast.
  Future<void> handlePayload(Map<String, dynamic> data) async {
    try {
      final chatId = data['chatId'] as String;
      // Null for DMs, the server only sends a chat name for groups
      final chatName = data['chatName'] as String?;
      final username = data['username'] as String;
      final groupType = data['groupType'] as String;
      final timestamp = data['timestamp'] is int
          ? data['timestamp'] as int
          : int.parse(data['timestamp'].toString());
      final imageUrl = data['imageUrl'] as String?;

      final count = await _incrementUnreadCount(chatId);
      debugPrint(
        "[push_service] Incremented unread count for $chatId to $count",
      );

      await _storePendingNotification(
        chatId,
        chatName,
        username,
        groupType,
        timestamp,
        imageUrl,
      );

      debugPrint("[push_service] Stored pending notification for $chatId");
      await _scheduleNotificationUpdate(chatId);
    } catch (e) {
      DiskLogger.error("[push_service] Error parsing message: $e");
    }
  }

  Future<void> saveEndpoint(PushEndpoint endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    final topic = Utils.extractNtfyTopic(endpoint.url);
    await prefs.setString('topic', topic);
  }

  Future<void> _scheduleNotificationUpdate(String chatId) async {
    final scheduledTime = DateTime.now().millisecondsSinceEpoch;
    await _setNewestNotificationTimestamp(chatId, scheduledTime);

    Future.delayed(Duration(seconds: 2), () async {
      final newestTimestamp = await _getNewestNotificationTimestamp(chatId);

      // If a newer notification was scheduled after this one, don't show
      if (newestTimestamp != null && newestTimestamp > scheduledTime) {
        return;
      }

      await _showPendingNotification(chatId);
    });
  }

  Future<void> _showPendingNotification(String chatId) async {
    final pending = await _getPendingNotification(chatId);

    if (pending == null) return;

    final unreadCount = await _getUnreadCount(chatId);
    final chatName = pending['chatName'] as String?;
    final username = pending['username'] as String;
    final groupType = pending['groupType'] as String;
    final timestamp = pending['timestamp'] as int;
    final imageUrl = pending['imageUrl'] as String?;

    String title;
    String body;

    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('locale');
    final t = await (locale == 'de' ? AppLocale.de : AppLocale.en).build();

    if (groupType == 'group') {
      title = chatName ?? username;
      body = t.notifications.newMessageGroup(
        count: unreadCount,
        chatName: title,
      );
    } else {
      title = username;
      body = t.notifications.newMessageDm(
        count: unreadCount,
        username: username,
      );
    }

    await _showNotification(
      title,
      body,
      chatId,
      timestamp,
      chatId.hashCode,
      groupType == 'group',
      imageUrl,
    );
    await _clearPendingNotification(chatId);
  }

  Future<void> _showNotification(
    String title,
    String body,
    String chatId,
    int timestamp,
    int notificationId,
    bool isGroup,
    String? imageUrl,
  ) async {
    debugPrint("[push_service] Notification image url $imageUrl");
    final imageCache = ImageCache();
    final imageBytes = await imageCache.getImage(imageUrl);

    DiskLogger.debug(
      "[push_service] Notification image bytes ${imageBytes?.length}",
    );

    try {
      await PersonShortcutCreator.pushDynamicShortcut(
        shortcutId: chatId,
        shortLabel: title,
        imageBytes: imageBytes,
      );
    } catch (e) {
      DiskLogger.error("[push_service] Error creating shortcut: $e");
    }

    final chatPerson = Person(
      name: title,
      key: chatId,
      // icon: imageBytes != null ? ByteArrayAndroidIcon(imageBytes) : null,
    );

    final androidDetails = AndroidNotificationDetails(
      'realtime_channel',
      'Notifications',
      channelDescription: 'Push notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      category: AndroidNotificationCategory.message,
      when: timestamp,
      shortcutId: chatId,
      styleInformation: MessagingStyleInformation(
        chatPerson,
        messages: [
          Message(
            body,
            DateTime.fromMillisecondsSinceEpoch(timestamp),
            chatPerson,
          ),
        ],
      ),
      // largeIcon: imageBytes != null ? ByteArrayAndroidBitmap(imageBytes) : null,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      notificationId,
      title,
      body,
      details,
      payload: chatId,
    );
  }

  Future<void> _storePendingNotification(
    String chatId,
    String? chatName,
    String username,
    String groupType,
    int timestamp,
    String? imageUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pending_notification_$chatId';

    final data = {
      'chatName': chatName,
      'username': username,
      'groupType': groupType,
      'timestamp': timestamp,
      'imageUrl': imageUrl,
    };

    await prefs.setString(key, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> _getPendingNotification(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pending_notification_$chatId';
    final json = prefs.getString(key);

    if (json == null) return null;
    return jsonDecode(json);
  }

  Future<void> _clearPendingNotification(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_notification_$chatId');
  }

  Future<Map<String, int>> _getUnreadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('unread_counts') ?? '{}';
    debugPrint("[push_service] Loading unread counts: $json");
    final Map<String, dynamic> decoded = jsonDecode(json);
    return decoded.map((key, value) => MapEntry(key, value as int));
  }

  Future<void> _saveUnreadCounts(Map<String, int> counts) async {
    debugPrint("[push_service] Saving unread counts: $counts");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('unread_counts', jsonEncode(counts));
  }

  Future<int> _incrementUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    counts[chatId] = (counts[chatId] ?? 0) + 1;
    await _saveUnreadCounts(counts);
    return counts[chatId] ?? 0;
  }

  Future<int> _getUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    return counts[chatId] ?? 0;
  }

  Future<void> _setNewestNotificationTimestamp(
    String chatId,
    int timestamp,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('newest_notification_timestamp_$chatId', timestamp);
  }

  Future<int?> _getNewestNotificationTimestamp(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('newest_notification_timestamp_$chatId');
  }

  Future<void> clearUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    counts.remove(chatId);
    await _saveUnreadCounts(counts);

    await _clearPendingNotification(chatId);
  }

  static Future<void> clearUnreadCounts() async {
    debugPrint("[push_service] Clearing unread counts");
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('unread_counts');
  }

  static Future<void> clearAllNotifications() async {
    await FlutterLocalNotificationsPlugin().cancelAll();
  }
}
