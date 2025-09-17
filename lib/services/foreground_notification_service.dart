import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypthora_chat_wrapper/pages/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationTaskHandler extends TaskHandler {
  String notificationServerUrl = '';
  String topic = '';
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  WebSocketChannel? _channel;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    developer.log('Notification service started', name: 'foreground_service');
    var prefs = await SharedPreferences.getInstance();
    notificationServerUrl = prefs.getString('notificationServerUrl') ?? '';
    if (notificationServerUrl.endsWith('/')) {
      notificationServerUrl = notificationServerUrl.substring(
        0,
        notificationServerUrl.length - 1,
      );
    }
    topic = prefs.getString('topic') ?? '';
    if (notificationServerUrl.isEmpty || topic.isEmpty) return;
    await _initializeNotifications();
    _connectToNtfy();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // This is called periodically - use it to check connection health
    if (_channel == null) {
      developer.log(
        'WebSocket disconnected, reconnecting...',
        name: 'foreground_service',
      );
      _connectToNtfy();
    }

    // Optional: Send a ping to keep connection alive
    try {
      _channel?.sink.add('ping');
    } catch (e) {
      developer.log('Failed to ping WebSocket: $e', name: 'foreground_service');
      _connectToNtfy();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool _) async {
    print('Notification service destroyed');
    _channel?.sink.close();
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('ic_notification');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    developer.log('Initializing notifications', name: 'foreground_service');
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  void _connectToNtfy() {
    try {
      _channel?.sink.close(); // Close existing connection if any
      _channel = WebSocketChannel.connect(
        Uri.parse('$notificationServerUrl/$topic/ws'),
      );

      _channel!.stream.listen(
        (data) async {
          try {
            // Skip ping responses
            if (data == 'pong' || data.toString().trim().isEmpty) {
              return;
            }

            final notification = jsonDecode(data);
            if (notification['event'] != 'message') return;
            final notificationData = jsonDecode(notification['message']);
            final groupType = notificationData['groupType'] ?? '';
            final username = notificationData['username'] ?? '';
            final chatId = notificationData['chatId'] ?? '';
            final chatName = notificationData['chatName'] ?? '';

            String message = '';
            if (groupType == 'group') {
              message = 'New Message from $username in $chatName';
            } else {
              message = 'New Message from $username';
            }

            await _showNotification('New Message', message, chatId);
          } catch (e) {
            developer.log(
              'Error parsing notification: $e',
              name: 'foreground_service',
            );
          }
        },
        onError: (error) {
          developer.log('WebSocket error: $error', name: 'foreground_service');
          _channel = null;
          // Don't reconnect immediately here - let onRepeatEvent handle it
        },
        onDone: () {
          developer.log(
            'WebSocket connection closed',
            name: 'foreground_service',
          );
          _channel = null;
          // Don't reconnect immediately here - let onRepeatEvent handle it
        },
      );

      developer.log('Connected to ntfy WebSocket', name: 'foreground_service');
    } catch (e) {
      developer.log(
        'Failed to connect to ntfy: $e',
        name: 'foreground_service',
      );
      _channel = null;
    }
  }

  Future<void> _showNotification(
    String title,
    String body,
    String chatId,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'realtime_channel',
      'Notifications',
      channelDescription: 'Push notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
      payload: chatId,
    );
  }

  // @override
  // void onNotificationPressed() {
  //   // Handle notification tap
  //   FlutterForegroundTask.launchApp();
  // }
}

@pragma('vm:entry-point')
void onDidReceiveNotificationResponse(NotificationResponse response) async {
  developer.log('Notification response: $response', name: 'foreground_service');
  // if (response.payload != null && response.payload!.isNotEmpty) {
  //   _onNotificationPressed(response.payload!);
  // }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  developer.log(
    'Notification Background response: $response',
    name: 'foreground_service',
  );
  // if (response.payload != null && response.payload!.isNotEmpty) {
  //   _onNotificationPressed(response.payload!);
  // }
}

  // void _onNotificationPressed(String chatId) {
  //   developer.log('Notification pressed: $chatId', name: 'foreground_service');
  //   navigatorKey.currentState?.pushAndRemoveUntil(
  //     MaterialPageRoute(builder: (_) => ChatPage(chatId: chatId)),
  //     (route) => false,
  //   );
  // }
