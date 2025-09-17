import 'dart:developer' as developer;

import 'package:crypthora_chat_wrapper/pages/add_server_page.dart';
import 'package:crypthora_chat_wrapper/services/foreground_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ChatPage extends StatefulWidget {
  final String? chatId;
  const ChatPage({Key? key, this.chatId}) : super(key: key);
  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  InAppWebViewController? controller;
  bool isReady = false;

  InAppWebViewSettings get _webViewSettings => InAppWebViewSettings(
    // Performance optimizations
    useHybridComposition: true,
    hardwareAcceleration: true,

    // Rendering optimizations
    allowsBackForwardNavigationGestures: true,
    disableHorizontalScroll: false,
    disableVerticalScroll: false,

    // Disable some heavy features if not needed
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,

    // Network optimizations
    useShouldOverrideUrlLoading: true,

    offscreenPreRaster: true,
    allowsInlineMediaPlayback: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,

    mediaPlaybackRequiresUserGesture: false,
  );

  Uri? _serverUri;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  void _init() async {
    final NotificationAppLaunchDetails? launchDetails = await _notifications
        .getNotificationAppLaunchDetails();

    var prefs = await SharedPreferences.getInstance();

    String? serverUrl = prefs.getString('serverUrl');
    String? notificationServerUrl = prefs.getString('notificationServerUrl');
    String? topic = prefs.getString('topic');

    if (serverUrl == null || notificationServerUrl == null || topic == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => AddServerPage()),
      );
      return;
    }

    String? chatId;

    if (launchDetails?.didNotificationLaunchApp == true) {
      final String? payload = launchDetails!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        developer.log('App launched from notification with payload: $payload');

        chatId = payload;
      }
    }

    if (chatId != null) {
      _serverUri = Uri.parse(
        '${serverUrl}chat',
      ).replace(queryParameters: {'chatId': chatId});
    } else {
      _serverUri = Uri.parse(serverUrl);
    }

    setState(() {
      isReady = true;
    });
    _initForegroundTask();
    _startForegroundTask();
  }

  @override
  void initState() {
    super.initState();
    _init();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundTask();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
        await controller?.evaluateJavascript(
          source: """
      if (window.disconnectSocket) {
        window.disconnectSocket();
      }
    """,
        );
        break;
      case AppLifecycleState.resumed:
        await controller?.evaluateJavascript(
          source: """
      if (window.connectSocket) {
        window.connectSocket();
      }
    """,
        );
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _injectFlutterInfo(String topic) {
    final polyfillScript =
        '''
            window.isFlutterWebView = true;
            window.ntfyTopic = "$topic";
          ''';

    controller?.evaluateJavascript(source: polyfillScript);
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
    await Permission.notification.request();

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

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
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text('CrypthoraChat'),
          actions: [
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => AddServerPage()),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () {
                controller?.reload();
              },
            ),
          ],
        ),
        body: SafeArea(
          child: isReady
              ? InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(_serverUri.toString()),
                  ),
                  initialSettings: _webViewSettings,
                  onWebViewCreated: (InAppWebViewController webController) {
                    controller = webController;
                  },
                  onLoadStop:
                      (
                        InAppWebViewController webController,
                        WebUri? url,
                      ) async {
                        var prefs = await SharedPreferences.getInstance();
                        String? topic = prefs.getString('topic');
                        if (topic != null) {
                          _injectFlutterInfo(topic);
                        }
                      },
                  // Optional: Handle JavaScript messages
                  // onConsoleMessage: (controller, consoleMessage) {
                  //   developer.log(consoleMessage.message, name: 'WebView Console');
                  // },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                        return NavigationActionPolicy.ALLOW;
                      },
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      Text('Loading webview...'),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
void startCallback() {
  developer.log('Foreground service started', name: 'main startCallback');
  FlutterForegroundTask.setTaskHandler(NotificationTaskHandler());
}
