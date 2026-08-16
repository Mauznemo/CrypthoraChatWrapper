import 'dart:async';
import 'dart:convert';

import 'package:crypthora_chat_wrapper/i18n/strings.g.dart';
import 'package:crypthora_chat_wrapper/services/fcm_service.dart';
import 'package:crypthora_chat_wrapper/services/shortcut_service.dart';
import 'package:crypthora_chat_wrapper/utils/avatar_cache.dart';
import 'package:crypthora_chat_wrapper/utils/disk_logger.dart';
import 'package:crypthora_chat_wrapper/utils/utils.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  static const channelId = 'realtime_channel';

  /// Notification bookkeeping is written from the push isolate and read from the UI isolate.
  ///
  /// [SharedPreferences] hands each isolate its own cached snapshot of the whole store, so the UI
  /// isolate clearing a count stayed invisible to the push isolate, which then incremented from a
  /// stale value and wrote the inflated map back. This API does no caching.
  static final _state = SharedPreferencesAsync();

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
    final isGroup = groupType == 'group';

    final prefs = await SharedPreferences.getInstance();
    // Written by the UI isolate, so this isolate's snapshot can predate it.
    await prefs.reload();
    final locale = prefs.getString('locale');
    final t = await (locale == 'de' ? AppLocale.de : AppLocale.en).build();

    final title = isGroup ? (chatName ?? username) : username;
    final body = isGroup
        ? t.notifications.newMessageGroup(count: unreadCount, chatName: title)
        : t.notifications.newMessageDm(count: unreadCount, username: username);

    await _showNotification(
      title: title,
      body: body,
      senderName: username,
      chatId: chatId,
      timestamp: timestamp,
      unreadCount: unreadCount,
      isGroup: isGroup,
      imageUrl: imageUrl,
      t: t,
    );
    await _clearPendingNotification(chatId);
  }

  Future<void> _showNotification({
    required String title,
    required String body,
    required String senderName,
    required String chatId,
    required int timestamp,
    required int unreadCount,
    required bool isGroup,
    required String? imageUrl,
    required Translations t,
  }) async {
    debugPrint("[push_service] Notification image url $imageUrl");
    final imagePath = await AvatarCache().getImagePath(imageUrl);
    DiskLogger.debug("[push_service] Notification image path $imagePath");

    // The shortcut has to exist before the notification references it, that binding is what puts
    // the notification in the conversation section.
    await ShortcutService.pushForChat(
      chatId: chatId,
      label: title,
      imagePath: imagePath,
    );

    // MessagingStyle's first person is the device owner. Giving it the same person as the message
    // sender makes Android treat the message as outgoing and drop the avatar entirely.
    final selfPerson = Person(key: 'self', name: t.notifications.you);
    final senderPerson = Person(
      key: chatId,
      name: senderName,
      // Deliberately a file rather than bytes: a byte array icon is embedded in the notification's
      // extras and parceled to the system on every update, where it competes for a 1MB budget.
      icon: imagePath != null ? BitmapFilePathAndroidIcon(imagePath) : null,
    );

    final androidDetails = AndroidNotificationDetails(
      channelId,
      t.notifications.channelName,
      channelDescription: t.notifications.channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      category: AndroidNotificationCategory.message,
      when: timestamp,
      number: unreadCount,
      shortcutId: chatId,
      styleInformation: MessagingStyleInformation(
        selfPerson,
        groupConversation: isGroup,
        conversationTitle: isGroup ? title : null,
        messages: [
          Message(
            body,
            DateTime.fromMillisecondsSinceEpoch(timestamp),
            senderPerson,
          ),
        ],
      ),
      // The conversation section is only reached on newer Android, and only when the shortcut
      // survived the system's dynamic shortcut cap. This is what shows the picture everywhere else.
      largeIcon: imagePath != null ? FilePathAndroidBitmap(imagePath) : null,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      notificationId(chatId),
      title,
      body,
      details,
      payload: chatId,
    );
  }

  /// Stable per chat, so a later push replaces the chat's notification instead of stacking.
  ///
  /// Derived rather than taken from [String.hashCode] because the notification is posted by the
  /// push isolate and cancelled by the UI isolate, and the two have to agree on the id.
  static int notificationId(String chatId) {
    final digest = md5.convert(utf8.encode(chatId)).bytes;
    return ((digest[0] << 24) |
            (digest[1] << 16) |
            (digest[2] << 8) |
            digest[3]) &
        0x7fffffff;
  }

  Future<void> _storePendingNotification(
    String chatId,
    String? chatName,
    String username,
    String groupType,
    int timestamp,
    String? imageUrl,
  ) async {
    final data = {
      'chatName': chatName,
      'username': username,
      'groupType': groupType,
      'timestamp': timestamp,
      'imageUrl': imageUrl,
    };

    await _state.setString('pending_notification_$chatId', jsonEncode(data));
  }

  Future<Map<String, dynamic>?> _getPendingNotification(String chatId) async {
    final json = await _state.getString('pending_notification_$chatId');

    if (json == null) return null;
    return jsonDecode(json);
  }

  Future<void> _clearPendingNotification(String chatId) async {
    await _state.remove('pending_notification_$chatId');
  }

  Future<Map<String, int>> _getUnreadCounts() async {
    final json = await _state.getString('unread_counts') ?? '{}';
    debugPrint("[push_service] Loading unread counts: $json");
    final Map<String, dynamic> decoded = jsonDecode(json);
    return decoded.map((key, value) => MapEntry(key, value as int));
  }

  Future<void> _saveUnreadCounts(Map<String, int> counts) async {
    debugPrint("[push_service] Saving unread counts: $counts");
    await _state.setString('unread_counts', jsonEncode(counts));
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
    await _state.setInt('newest_notification_timestamp_$chatId', timestamp);
  }

  Future<int?> _getNewestNotificationTimestamp(String chatId) async {
    return await _state.getInt('newest_notification_timestamp_$chatId');
  }

  /// Forgets everything about one chat and takes its notification down.
  ///
  /// Called when the user opens that chat, which is the only point at which the messages have
  /// actually been seen. Clearing every chat instead would hide unread counts for the chats the
  /// user did not open.
  Future<void> clearUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    counts.remove(chatId);
    await _saveUnreadCounts(counts);

    await _clearPendingNotification(chatId);
    await _state.remove('newest_notification_timestamp_$chatId');
    await _notifications.cancel(notificationId(chatId));
  }

  /// Drops every count and notification, for when the app is pointed at a different server and
  /// the old chats stop meaning anything.
  static Future<void> clearUnreadCounts() async {
    debugPrint("[push_service] Clearing unread counts");
    await _state.remove('unread_counts');
  }

  static Future<void> clearAllNotifications() async {
    await FlutterLocalNotificationsPlugin().cancelAll();
  }
}
