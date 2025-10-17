import 'dart:convert';

import 'package:crypthora_chat_wrapper/utils/i18n_helper.dart';
import 'package:crypthora_chat_wrapper/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';

@pragma('vm:entry-point')
class PushService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final _instance = 'crypthora_chat';

  static Future<void> register() async {
    await UnifiedPush.register(instance: _instance);
  }

  static Future<void> unregister() async {
    await UnifiedPush.unregister(_instance);
  }

  static void onNewEndpoint(PushEndpoint endpoint, String instance) {
    debugPrint("[push_service] New endpoint: ${endpoint.url}");

    saveEndpoint(endpoint);
  }

  static void onRegistrationFailed(FailedReason reason, String instance) {
    debugPrint("[push_service] Registration failed");
  }

  static void onUnregistered(String instance) {
    debugPrint("Unregistered");
  }

  @pragma('vm:entry-point')
  static Future<void> onMessage(PushMessage message, String instance) async {
    String messageText = utf8.decode(message.content);
    debugPrint("[push_service] Received message: $messageText");
    try {
      final data = jsonDecode(messageText);

      final chatId = data['chatId'] as String;
      final chatName = data['chatName'] as String;
      final username = data['username'] as String;
      final groupType = data['groupType'] as String;
      final timestamp = data['timestamp'] as int;

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
      );

      debugPrint("[push_service] Stored pending notification for $chatId");
      await _scheduleNotificationUpdate(chatId);
    } catch (e) {
      debugPrint("[push_service] Error parsing message: $e");
    }
  }

  static Future<void> saveEndpoint(PushEndpoint endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    final topic = Utils.extractNtfyTopic(endpoint.url);
    await prefs.setString('topic', topic);
  }

  static Future<void> _scheduleNotificationUpdate(String chatId) async {
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

  static final Map<String, dynamic> _translationsEn = {
    "new-message-group": "{count} new messages in {chatName}",
    "new-message-dm": "{count} new messages from {username}",
  };

  static final Map<String, dynamic> _translationsDe = {
    "new-message-dm": "{count} neue Nachrichten von {username}",
    "new-message-group": "{count} neue Nachrichten in {chatName}",
  };

  static Future<void> _showPendingNotification(String chatId) async {
    final pending = await _getPendingNotification(chatId);

    if (pending == null) return;

    final unreadCount = await _getUnreadCount(chatId);
    final chatName = pending['chatName'] as String;
    final username = pending['username'] as String;
    final groupType = pending['groupType'] as String;
    final timestamp = pending['timestamp'] as int;

    String title;
    String body;

    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('locale');
    I18nHelper.load(
      locale ?? 'en',
      locale == 'de' ? _translationsDe : _translationsEn,
    );

    if (groupType == 'group') {
      title = chatName;
      body = I18nHelper.t('new-message-group', {
        'count': unreadCount.toString(),
        'chatName': chatName,
      });
    } else {
      title = username;
      body = I18nHelper.t('new-message-dm', {
        'count': unreadCount.toString(),
        'username': username,
      });
    }

    await _showNotification(title, body, chatId, timestamp, chatId.hashCode);
    await _clearPendingNotification(chatId);
  }

  static Future<void> _showNotification(
    String title,
    String body,
    String chatId,
    int timestamp,
    int notificationId,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      'realtime_channel',
      'Notifications',
      channelDescription: 'Push notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      when: timestamp,
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

  static Future<void> _storePendingNotification(
    String chatId,
    String chatName,
    String username,
    String groupType,
    int timestamp,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pending_notification_$chatId';

    final data = {
      'chatName': chatName,
      'username': username,
      'groupType': groupType,
      'timestamp': timestamp,
    };

    await prefs.setString(key, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> _getPendingNotification(
    String chatId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pending_notification_$chatId';
    final json = prefs.getString(key);

    if (json == null) return null;
    return jsonDecode(json);
  }

  static Future<void> _clearPendingNotification(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_notification_$chatId');
  }

  static Future<Map<String, int>> _getUnreadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('unread_counts') ?? '{}';
    debugPrint("[push_service] Loading unread counts: $json");
    final Map<String, dynamic> decoded = jsonDecode(json);
    return decoded.map((key, value) => MapEntry(key, value as int));
  }

  static Future<void> _saveUnreadCounts(Map<String, int> counts) async {
    debugPrint("[push_service] Saving unread counts: $counts");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('unread_counts', jsonEncode(counts));
  }

  static Future<int> _incrementUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    counts[chatId] = (counts[chatId] ?? 0) + 1;
    await _saveUnreadCounts(counts);
    return counts[chatId] ?? 0;
  }

  static Future<int> _getUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    return counts[chatId] ?? 0;
  }

  static Future<void> _setNewestNotificationTimestamp(
    String chatId,
    int timestamp,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('newest_notification_timestamp_$chatId', timestamp);
  }

  static Future<int?> _getNewestNotificationTimestamp(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('newest_notification_timestamp_$chatId');
  }

  static Future<void> clearUnreadCount(String chatId) async {
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
    await _notifications.cancelAll();
  }
}
