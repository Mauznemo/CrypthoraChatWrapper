import 'dart:convert';

import 'package:crypthora_chat_wrapper/utils/i18n_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:workmanager/workmanager.dart';

class PushService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static void onNewEndpoint(PushEndpoint endpoint, String instance) {
    debugPrint("New endpoint: $endpoint");

    // TODO: Send endpoint to server
    saveEndpoint(endpoint);
  }

  static void onRegistrationFailed(FailedReason reason, String instance) {
    debugPrint("Registration failed");
  }

  static void onUnregistered(String instance) {
    debugPrint("Unregistered");
    // Clean up endpoint server
  }

  static Future<void> onMessage(PushMessage message, String instance) async {
    String messageText = utf8.decode(message.content);
    debugPrint("Received message: $messageText");
    final data = jsonDecode(messageText);

    final chatId = data['chatId'] as String;
    final chatName = data['chatName'] as String;
    final username = data['username'] as String;
    final groupType = data['groupType'] as String;
    final timestamp = data['timestamp'] as int;

    await _incrementUnreadCount(chatId);

    await _storePendingNotification(
      chatId,
      chatName,
      username,
      groupType,
      timestamp,
    );

    await _scheduleNotificationUpdate(chatId);
  }

  static Future<void> saveEndpoint(PushEndpoint endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('unifiedpush_endpoint', endpoint.url);
  }

  static Future<void> _scheduleNotificationUpdate(String chatId) async {
    // Cancel existing scheduled notification for this chat
    await Workmanager().cancelByUniqueName('notification_$chatId');

    // Schedule new notification in 2 seconds
    await Workmanager().registerOneOffTask(
      'notification_$chatId',
      'showNotification',
      initialDelay: Duration(seconds: 2),
      inputData: {'chatId': chatId},
    );
  }

  static Future<void> showPendingNotification(
    Map<String, dynamic> inputData,
  ) async {
    final chatId = inputData['chatId'] as String;
    final pending = await _getPendingNotification(chatId);

    if (pending == null) return;

    final unreadCount = await _getUnreadCount(chatId);
    final chatName = pending['chatName'] as String;
    final username = pending['username'] as String;
    final groupType = pending['groupType'] as String;
    final timestamp = pending['timestamp'] as int;

    String title;
    String body;

    if (groupType == 'group') {
      title = chatName;
      body = I18nHelper.t('notifications.new-message-group', {
        'count': unreadCount.toString(),
        'chatName': chatName,
      });
    } else {
      title = username;
      body = I18nHelper.t('notifications.new-message-dm', {
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
    final Map<String, dynamic> decoded = jsonDecode(json);
    return decoded.map((key, value) => MapEntry(key, value as int));
  }

  static Future<void> _saveUnreadCounts(Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('unread_counts', jsonEncode(counts));
  }

  static Future<void> _incrementUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    counts[chatId] = (counts[chatId] ?? 0) + 1;
    await _saveUnreadCounts(counts);
  }

  static Future<int> _getUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    return counts[chatId] ?? 0;
  }

  static Future<void> clearUnreadCount(String chatId) async {
    final counts = await _getUnreadCounts();
    counts.remove(chatId);
    await _saveUnreadCounts(counts);

    // Also cancel any pending notifications for this chat
    await Workmanager().cancelByUniqueName('notification_$chatId');
    await _clearPendingNotification(chatId);
  }
}
