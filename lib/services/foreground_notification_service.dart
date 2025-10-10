import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationTaskHandler extends TaskHandler {
  String notificationServerUrl = '';
  String topic = '';

  IOWebSocketChannel? _channel;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  DateTime? _lastActivity;
  int _notificationId = 0;

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
    if (notificationServerUrl.isEmpty || topic.isEmpty) {
      developer.log(
        'Missing server URL or topic, stopping service',
        name: 'foreground_service',
      );
      return;
    }
    developer.log(
      'WS URL: $notificationServerUrl/$topic/ws',
      name: 'foreground_service',
    );
    await _initializeNotifications();
    _connectToNtfy();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Check connection health periodically
    final isChannelOpen = _isChannelOpen();

    // Wait 60 to try reconnecting
    if (isChannelOpen) {
      developer.log(
        'WebSocket is open, updating last activity',
        name: 'foreground_service',
      );
      _lastActivity = DateTime.now();
    } else {
      final disconnectedFor = _lastActivity != null
          ? DateTime.now().difference(_lastActivity!).inSeconds
          : 0;
      developer.log(
        'Connection lost, reconnecting in ${60 - disconnectedFor} seconds',
        name: 'foreground_service',
      );
      if (disconnectedFor > 60) {
        _connectToNtfy();
      }
    }
  }

  bool _isChannelOpen() {
    if (_channel == null) return false;

    // closeCode is null while the socket is open
    return _channel!.closeCode == null;
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool _) async {
    developer.log('Notification service destroyed', name: 'foreground_service');
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
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$notificationServerUrl/$topic/ws'),
      );

      _channel!.stream.listen(
        (data) async {
          developer.log('Received data: $data', name: 'foreground_service');
          try {
            // Skip empty messages
            if (data.toString().trim().isEmpty) {
              developer.log(
                'Empty message received, skipping',
                name: 'foreground_service',
              );
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

            await _showNotification(username, message, chatId);
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
        },
        onDone: () {
          developer.log(
            'WebSocket connection closed',
            name: 'foreground_service',
          );
          _channel = null;
        },
      );

      _lastActivity = DateTime.now(); // Set initial activity on connect
      developer.log('Connected to ntfy WebSocket', name: 'foreground_service');
    } catch (e) {
      developer.log(
        'Failed to connect to ntfy: $e',
        name: 'foreground_service',
      );
      _channel = null;
      _lastActivity = null;
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
      _notificationId++,
      title,
      body,
      details,
      payload: chatId,
    );
  }
}

@pragma('vm:entry-point')
void onDidReceiveNotificationResponse(NotificationResponse response) async {
  developer.log('Notification response: $response', name: 'foreground_service');
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  developer.log(
    'Notification Background response: $response',
    name: 'foreground_service',
  );
}
