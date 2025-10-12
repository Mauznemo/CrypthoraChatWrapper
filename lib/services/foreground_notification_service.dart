import 'dart:async';
import 'dart:convert';
// import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypthora_chat_wrapper/utils/i18n_helper.dart';
import 'package:flutter/material.dart';
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final Connectivity _connectivity = Connectivity();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;
  DateTime? _lastMessageTimestamp;
  bool _socketOpen = false;
  bool _hasConnectivity = false;
  bool _connecting = false;
  int _reconnectionAttempts = 0;
  Map<String, int> _unreadCounts = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[foreground_service] Notification service started');
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
      debugPrint(
        '[foreground_service] Missing server URL or topic, stopping service',
      );
      return;
    }
    debugPrint('[foreground_service] WS URL: $notificationServerUrl/$topic/ws');
    await _initializeNotifications();

    final results = await _connectivity.checkConnectivity();
    _hasConnectivity = _isConnectivityActive(results);

    if (_hasConnectivity) {
      _connectToNtfy();
    } else {
      debugPrint('[foreground_service] No connectivity, not connecting');
    }

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hadConnectivity = _hasConnectivity;
    _hasConnectivity = _isConnectivityActive(results);

    if (hadConnectivity && !_hasConnectivity) {
      debugPrint('[foreground_service] Connection lost (device)');
    } else if (!hadConnectivity && _hasConnectivity) {
      debugPrint('[foreground_service] Connection restored (device)');
      _connectToNtfy();
    }
  }

  @override
  void onReceiveData(Object data) {
    super.onReceiveData(data);

    if (data is Map<String, dynamic>) {
      if (data['topic'] != null) {
        topic = data['topic'];
        _connectToNtfy();
      } else if (data['resetUnreadCounts'] != null) {
        _unreadCounts = {};
      }
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (_socketOpen) {
      debugPrint(
        '[foreground_service] onRepeatEvent: WebSocket is open, updating last activity',
      );
    } else {
      final results = await _connectivity.checkConnectivity();
      _hasConnectivity = _isConnectivityActive(results);

      if (!_hasConnectivity) {
        debugPrint(
          '[foreground_service] onRepeatEvent: No connectivity, not reconnecting',
        );
        return;
      }

      debugPrint(
        '[foreground_service] onRepeatEvent: Connection lost, reconnecting now',
      );

      _connectToNtfy();
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

  bool _isConnectivityActive(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool _) async {
    debugPrint('[foreground_service] Notification service destroyed');
    _channel?.sink.close();
    _connectivitySubscription?.cancel();
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('ic_notification');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    debugPrint('[foreground_service] Initializing notifications');
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

      debugPrint(
        '[foreground_service] Fetching missed messages, query: ${_wsToHttp(notificationServerUrl)}/$topic/json?since=$since&poll=1',
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
        debugPrint('[foreground_service] Received missed messages');
        final body = response.body.trim();
        debugPrint('[foreground_service] Trimmed missed messages');
        if (body.isEmpty) return;

        final lines = body.split('\n').where((line) => line.isNotEmpty);
        debugPrint('[foreground_service] Split missed messages');

        debugPrint(
          '[foreground_service] Received ${lines.length} missed messages',
        );

        for (var line in lines) {
          final msg = jsonDecode(line);
          final time = msg['time'] ?? 0;

          final latestMessageTime = (lastTimestamp / 1000).floor();

          if (time <= latestMessageTime) {
            debugPrint(
              '[foreground_service] Skipping old message $time <= $latestMessageTime = ${time <= latestMessageTime}',
            );
            continue;
          }

          _handleMessage(line);
        }
      }
    } catch (e) {
      debugPrint('[foreground_service] Error fetching missed messages: $e');
    }
  }

  Future<void> _handleMessage(String data) async {
    try {
      // Skip empty messages
      if (data.toString().trim().isEmpty) {
        debugPrint('[foreground_service] Empty message received, skipping');
        return;
      }

      final notification = jsonDecode(data);
      if (notification['event'] != 'message') return;
      final notificationPushData = jsonDecode(notification['message']);
      final groupType = notificationPushData['groupType'] ?? '';
      final username = notificationPushData['username'] ?? '';
      final chatId = notificationPushData['chatId'] ?? '';
      final chatName = notificationPushData['chatName'] ?? '';
      final timestamp = notificationPushData['timestamp'];

      _setLastMessageTimestamp(DateTime.fromMillisecondsSinceEpoch(timestamp));

      var unreadCount = _unreadCounts[chatId];

      unreadCount ??= 0;

      unreadCount++;

      _unreadCounts[chatId] = unreadCount;

      String title = '';
      String message = '';
      if (groupType == 'group') {
        title = chatName;
        final translation = I18nHelper.t('notifications.new-message-group', {
          'count': unreadCount.toString(),
          'chatName': chatName,
        });
        message = translation;
      } else {
        title = username;
        final translation = I18nHelper.t('notifications.new-message-dm', {
          'count': unreadCount.toString(),
          'username': username,
        });
        message = translation;
      }

      final notificationId = chatId.hashCode;

      _scheduleNotificationUpdate(
        title,
        message,
        chatId,
        timestamp,
        notificationId,
      );
    } catch (e) {
      debugPrint('[foreground_service] Error parsing notification: $e');
      debugPrint('Error parsing notification: $e');
    }
  }

  Timer? _updateTimer;

  void _scheduleNotificationUpdate(
    String title,
    String body,
    String chatId,
    int timestamp,
    int notificationId,
  ) {
    _updateTimer?.cancel();
    _updateTimer = Timer(const Duration(seconds: 2), () {
      _showNotification(title, body, chatId, timestamp, notificationId);
    });
  }

  Future<void> _connectToNtfy() async {
    if (_connecting) return;
    _connecting = true;
    await _getMissedMessages();

    try {
      debugPrint('[foreground_service] Tying to connect to WebSocket');
      _channel?.sink.close();
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$notificationServerUrl/$topic/ws'),
        pingInterval: const Duration(seconds: 30),
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
          debugPrint('[foreground_service] Received data: $data');
          _handleMessage(data);
        },
        onError: (error) {
          debugPrint('[foreground_service] WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[foreground_service] WebSocket connection closed');
          _handleDisconnect();
        },
      );

      _handleConnect();
    } catch (e) {
      debugPrint('[foreground_service] Failed to connect to ntfy: $e');
      debugPrint('[foreground_service] Failed to connect to ntfy: $e');
      _handleDisconnect();
    }
  }

  void _handleConnect() {
    _connecting = false;
    _socketOpen = true;
    _reconnectionAttempts = 0;

    _updateServiceNotification(true, 'Connected to ntfy server');

    debugPrint('[foreground_service] Connected to ntfy WebSocket');
  }

  void _handleDisconnect() {
    _connecting = false;
    _socketOpen = false;
    _channel = null;
    debugPrint('[foreground_service] Disconnected from ntfy WebSocket');

    if (_getLastMessageTimestamp() == null) {
      _setLastMessageTimestamp(DateTime.now());
    }

    if (!_hasConnectivity) {
      _updateServiceNotification(
        false,
        'Device offline, not attempting reconnection',
      );
      return;
    }

    if (_reconnectionAttempts >= 5) {
      _updateServiceNotification(
        false,
        'Max reconnection attempts reached, retrying later',
      );
      return;
    }

    final baseDelay = 2;
    final maxDelay = 60;
    final delay = min(maxDelay, baseDelay * (1 << _reconnectionAttempts));

    final jitter = Random().nextInt(3);
    final delayWithJitter = delay + jitter;

    debugPrint(
      '[foreground_service] Reconnection attempt $_reconnectionAttempts',
    );

    _updateServiceNotification(false, 'Retying in $delay seconds');

    _reconnectionAttempts += 1;
    Timer(Duration(seconds: delayWithJitter), _connectToNtfy);
  }

  void _updateServiceNotification(bool connected, String notificationText) {
    final notificationTitle = I18nHelper.t(
      connected
          ? 'notifications.service.connected'
          : 'notifications.service.disconnected',
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
}

@pragma('vm:entry-point')
void onDidReceiveNotificationResponse(NotificationResponse response) async {
  debugPrint('[foreground_service] Notification response: $response');
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  debugPrint(
    '[foreground_service] Notification Background response: $response',
  );
}
