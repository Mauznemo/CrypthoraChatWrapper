import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationTaskHandler extends TaskHandler {
  static const String NTFY_WS_URL = 'wss://ntfy.my-server.com/test-topic/ws';

  WebSocketChannel? _channel;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    developer.log('Notification service started', name: 'foreground_service');
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
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(settings);
  }

  void _connectToNtfy() {
    try {
      _channel?.sink.close(); // Close existing connection if any
      _channel = WebSocketChannel.connect(Uri.parse(NTFY_WS_URL));

      _channel!.stream.listen(
        (data) async {
          try {
            // Skip ping responses
            if (data == 'pong' || data.toString().trim().isEmpty) {
              return;
            }

            final notification = jsonDecode(data);
            if (notification['event'] == 'message') {
              await _showNotification(
                notification['title'] ?? 'New notification',
                notification['message'] ?? '',
              );
            }
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

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'realtime_channel',
      'Real-time Notifications',
      channelDescription: 'Real-time push notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(DateTime.now().millisecond, title, body, details);
  }

  @override
  void onNotificationPressed() {
    // Handle notification tap
    FlutterForegroundTask.launchApp();
  }
}
