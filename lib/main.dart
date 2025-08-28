import 'dart:developer' as developer;

import 'package:crypthora_chat_wrapper/services/foreground_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: WebViewScreen());
  }
}

class WebViewScreen extends StatefulWidget {
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://chat.my-server.com/'));

    _initForegroundTask();
    _startForegroundTask();
  }

  void _initForegroundTask() {
    developer.log('Initializing foreground task', name: 'main');
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Push Notification Service',
        channelDescription:
            'Keeps the app connected for real-time notifications',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        showBadge: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          5000,
        ), // Check every 5 seconds
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startForegroundTask() async {
    developer.log('Starting foreground task', name: 'main');
    //TODO: Request permissions
    /*
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }*/

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 256, // Add unique service ID
        notificationTitle: 'Connected',
        notificationText: 'Receiving real-time notifications',
        callback: startCallback,
      );
    }
  }

  Future<void> _stopForegroundTask() async {
    developer.log('Stopping foreground task', name: 'main');
    await FlutterForegroundTask.stopService();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          //TODO: Hide app bar and only open native settings from PWA
          title: Text('CrypthoraChat'),
          actions: [
            IconButton(
              icon: Icon(Icons.notifications),
              onPressed: () {
                // Toggle foreground service
                FlutterForegroundTask.isRunningService.then((isRunning) {
                  if (isRunning) {
                    _stopForegroundTask();
                  } else {
                    _startForegroundTask();
                  }
                });
              },
            ),
          ],
        ),
        body: SafeArea(child: WebViewWidget(controller: controller)),
      ),
    );
  }

  @override
  void dispose() {
    _stopForegroundTask();
    super.dispose();
  }
}

@pragma('vm:entry-point')
void startCallback() {
  developer.log('Foreground service started', name: 'main startCallback');
  FlutterForegroundTask.setTaskHandler(NotificationTaskHandler());
}
