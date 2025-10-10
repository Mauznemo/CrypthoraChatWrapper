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
  bool _loadError = false;
  String _errorMessage = '';

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
        MaterialPageRoute(
          builder: (context) => AddServerPage(canGoBack: false),
        ),
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
      if (serverUrl.endsWith('/')) {
        serverUrl = serverUrl.substring(0, serverUrl.length - 1);
      }
      _serverUri = Uri.parse(
        '$serverUrl/chat',
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
    final padding = MediaQuery.of(context).padding;

    final polyfillScript =
        '''
            window.isFlutterWebView = true;
            window.ntfyTopic = "$topic";
            window.flutterSafeAreaInsets = {
              top: ${padding.top},
              bottom: ${padding.bottom},
              left: ${padding.left},
              right: ${padding.right}
            }
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
          15000,
        ), // Increased to 15 seconds for better battery efficiency
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startForegroundTask() async {
    developer.log('Starting foreground task', name: 'main');
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 256, // Unique service ID
        serviceTypes: [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: 'Connected',
        notificationText: 'Receiving real-time notifications',
        callback: startCallback,
      );
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Connected',
        notificationText: 'Receiving real-time notifications',
      );
    }
  }

  Future<void> _stopForegroundTask() async {
    developer.log('Stopping foreground task', name: 'main');
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: !_loadError
          ? Scaffold(
              body: isReady
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(_serverUri.toString()),
                      ),
                      initialSettings: _webViewSettings,
                      onWebViewCreated: (InAppWebViewController webController) {
                        controller = webController;
                        controller?.addJavaScriptHandler(
                          handlerName: 'openSettings',
                          callback: (args) async {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AddServerPage(canGoBack: true),
                              ),
                            );
                          },
                        );
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
                      onReceivedError: (controller, request, error) => {
                        setState(() {
                          _loadError = true;
                          _errorMessage = error.description;
                        }),
                      },
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                            return NavigationActionPolicy.ALLOW;
                          },
                      onPermissionRequest: (controller, permissionRequest) async {
                        developer.log(
                          'Permission request: ${permissionRequest.resources}',
                        );

                        if (permissionRequest.resources.contains(
                          PermissionResourceType.CAMERA,
                        )) {
                          final status = await Permission.camera.request();
                          return PermissionResponse(
                            resources: permissionRequest.resources,
                            action: status == PermissionStatus.granted
                                ? PermissionResponseAction.GRANT
                                : PermissionResponseAction.DENY,
                          );
                        }

                        return PermissionResponse(
                          resources: permissionRequest.resources,
                          action: PermissionResponseAction.DENY,
                        );
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
            )
          : Scaffold(
              resizeToAvoidBottomInset: true,
              appBar: AppBar(title: Text('CrypthoraChat Wrapper')),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Failed to load webview',
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 16),
                    Text(_errorMessage, style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 5),
                    Text('Server: $_serverUri', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 56),
                    FilledButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => ChatPage()),
                        );
                      },
                      child: Text('Retry'),
                    ),
                    const SizedBox(height: 5),
                    FilledButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AddServerPage(canGoBack: true),
                          ),
                        );
                      },
                      child: Text('Change server address'),
                    ),
                  ],
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
