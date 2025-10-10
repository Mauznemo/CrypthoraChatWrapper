import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:crypthora_chat_wrapper/utils/i18n_helper.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NotificationTaskHandler extends TaskHandler {
  String notificationServerUrl = '';
  String topic = '';

  IOWebSocketChannel? _channel;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  DateTime _lastActivity = DateTime.now();
  int _notificationId = 0;
  SharedPreferences? _prefs;
  DateTime? _lastMessageTimestamp;
  bool _socketOpen = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    developer.log('Notification service started', name: 'foreground_service');
    _prefs = await SharedPreferences.getInstance();
    I18nHelper.load(_prefs?.getString('locale') ?? 'en');
    notificationServerUrl = _prefs?.getString('notificationServerUrl') ?? '';
    if (notificationServerUrl.endsWith('/')) {
      notificationServerUrl = notificationServerUrl.substring(
        0,
        notificationServerUrl.length - 1,
      );
    }
    topic = _prefs?.getString('topic') ?? '';
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
    // final isChannelOpen = _isChannelOpen();

    // Wait 60 to try reconnecting
    if (_socketOpen) {
      developer.log(
        'WebSocket is open, updating last activity',
        name: 'foreground_service',
      );
      _lastActivity = DateTime.now();
    } else {
      final disconnectedFor = DateTime.now()
          .difference(_lastActivity)
          .inSeconds;

      final retryingInSeconds = (60 + 15) - (disconnectedFor);
      developer.log(
        'Connection lost, reconnecting in $retryingInSeconds seconds',
        name: 'foreground_service',
      );

      if (disconnectedFor > 60) {
        await _getMissedMessages();
        _connectToNtfy();
      }
    }
  }

  void _setLastMessageTimestamp(DateTime timestamp) {
    _lastMessageTimestamp = timestamp;
    _prefs?.setInt('lastMessageTimestamp', timestamp.millisecondsSinceEpoch);
  }

  DateTime? _getLastMessageTimestamp() {
    if (_lastMessageTimestamp != null) {
      return _lastMessageTimestamp;
    }

    final lastMessage = _prefs?.getInt('lastMessageTimestamp');
    if (lastMessage == null) return null;
    final lastMessageDate = DateTime.fromMillisecondsSinceEpoch(lastMessage);
    return lastMessageDate;
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

  String _wsToHttp(String wsUrl) {
    if (wsUrl.startsWith('ws://')) {
      return wsUrl.replaceFirst('ws://', 'http://');
    }
    if (wsUrl.startsWith('wss://')) {
      return wsUrl.replaceFirst('wss://', 'https://');
    }
    return wsUrl;
  }

  Future<void> _getMissedMessages() async {
    try {
      final lastTimestamp = _getLastMessageTimestamp()?.millisecondsSinceEpoch;

      if (lastTimestamp == null) return;

      final since = (lastTimestamp / 1000).floor().toString();

      developer.log(
        'Fetching missed messages, query: ${_wsToHttp(notificationServerUrl)}/$topic/json?since=$since&poll=1',
        name: 'foreground_service',
      );

      final response = await http
          .get(
            Uri.parse(
              '${_wsToHttp(notificationServerUrl)}/$topic/json?since=$since&poll=1',
            ),
            headers: {'Accept': 'application/json'},
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        developer.log('Received missed messages', name: 'foreground_service');
        final body = response.body.trim();
        developer.log('Trimmed missed messages', name: 'foreground_service');
        if (body.isEmpty) return;

        final lines = body.split('\n').where((line) => line.isNotEmpty);
        developer.log('Split missed messages', name: 'foreground_service');

        developer.log(
          'Received ${lines.length} missed messages',
          name: 'foreground_service',
        );

        for (var line in lines) {
          // final msg = jsonDecode(line);
          _handleMessage(line);
        }
      }
    } catch (e) {
      developer.log(
        'Error fetching missed messages: $e',
        name: 'foreground_service',
      );
    }
  }

  Future<void> _handleMessage(String data) async {
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
      final timestamp = notificationData['timestamp'];
      final notificationTime = timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.now();

      _setLastMessageTimestamp(notificationTime);

      String message = '';
      if (groupType == 'group') {
        final translation = I18nHelper.t('notifications.new-message-group', {
          'username': username,
          'chatName': chatName,
        });
        message = translation;
      } else {
        final translation = I18nHelper.t('notifications.new-message-dm', {
          'username': username,
        });
        message = translation;
      }

      await _showNotification(username, message, chatId, notificationTime);
    } catch (e) {
      developer.log(
        'Error parsing notification: $e',
        name: 'foreground_service',
      );
    }
  }

  Future<void> _connectToNtfy() async {
    try {
      developer.log(
        'Tying to connect to WebSocket',
        name: 'foreground_service',
      );
      _channel?.sink.close();
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$notificationServerUrl/$topic/ws'),
      );

      // await _channel?.ready;
      try {
        await _channel?.ready;
      } on SocketException catch (e) {
        throw Exception('Socket not ready: $e');
      } on WebSocketChannelException catch (e) {
        throw Exception('Socket not ready: $e');
      }

      _channel!.stream.listen(
        (data) async {
          developer.log('Received data: $data', name: 'foreground_service');
          _handleMessage(data);
        },
        onError: (error) {
          developer.log('WebSocket error: $error', name: 'foreground_service');
          _handleDisconnect();
        },
        onDone: () {
          developer.log(
            'WebSocket connection closed',
            name: 'foreground_service',
          );
          _handleDisconnect();
        },
      );

      _lastActivity = DateTime.now();

      _socketOpen = true;

      _updateServiceNotification(true);

      developer.log('Connected to ntfy WebSocket', name: 'foreground_service');
    } catch (e) {
      developer.log(
        'Failed to connect to ntfy: $e',
        name: 'foreground_service',
      );
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _socketOpen = false;
    _channel = null;
    _lastActivity = DateTime.now();
    _updateServiceNotification(false);
    if (_getLastMessageTimestamp() == null) {
      _setLastMessageTimestamp(DateTime.now());
    }
  }

  void _updateServiceNotification(bool connected) {
    final notificationTitle = I18nHelper.t(
      connected
          ? 'notifications.service.connected'
          : 'notifications.service.disconnected',
    );
    final notificationText = I18nHelper.t(
      connected
          ? 'notifications.service.receiving'
          : 'notifications.service.trying-to-reconnect',
    );
    FlutterForegroundTask.updateService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
  }

  Future<void> _showNotification(
    String title,
    String body,
    String chatId,
    DateTime timestamp,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      'realtime_channel',
      'Notifications',
      channelDescription: 'Push notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      when: timestamp.millisecondsSinceEpoch,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
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
