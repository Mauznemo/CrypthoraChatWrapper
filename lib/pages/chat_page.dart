import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:crypthora_chat_wrapper/pages/add_server_page.dart';
import 'package:crypthora_chat_wrapper/services/foreground_notification_service.dart';
import 'package:crypthora_chat_wrapper/utils/i18n_helper.dart';
import 'package:crypthora_chat_wrapper/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatPage extends StatefulWidget {
  final String? chatId;
  const ChatPage({super.key, this.chatId});
  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  InAppWebViewController? controller;
  bool isReady = false;
  bool _loadError = false;
  String _errorMessage = '';
  SharedPreferences? _prefs;
  PackageInfo? _packageInfo;

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

    _prefs = await SharedPreferences.getInstance();

    _packageInfo = await PackageInfo.fromPlatform();

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'resetUnreadCounts': true});
    }

    String? serverUrl = _prefs?.getString('serverUrl');
    String? notificationServerUrl = _prefs?.getString('notificationServerUrl');
    String? topic = _prefs?.getString('topic');

    await I18nHelper.saveCurrentLocale(context);

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
        developer.log(
          'App launched from notification with payload: $payload',
          name: 'foreground_service',
        );

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

    final data =
        '''
            window.isFlutterWebView = true;
            window.wrapperVersion = "${_packageInfo?.version ?? 'Unknown'}";
            window.ntfyTopic = "$topic";
            window.flutterSafeAreaInsets = {
              top: ${padding.top},
              bottom: ${padding.bottom},
              left: ${padding.left},
              right: ${padding.right}
            }
          ''';

    controller?.evaluateJavascript(source: data);
  }

  void _initForegroundTask() {
    developer.log('Initializing foreground task', name: 'main');
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service_min',
        channelName: 'Push Notification Service',
        channelDescription:
            'Keeps the app connected for real-time notifications',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        showBadge: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          const Duration(hours: 2).inMilliseconds,
        ),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  bool _isAppUrl(String url) {
    String? serverUrl = _prefs?.getString('serverUrl') ?? 'http';
    return url.startsWith(serverUrl);
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
        notificationTitle: FlutterI18n.translate(
          context,
          'notifications.service.starting',
        ),
        notificationText: FlutterI18n.translate(
          context,
          'notifications.service.starting-text',
        ),
        callback: startCallback,
      );
    } //else {
    //   await FlutterForegroundTask.updateService(
    //     notificationTitle: FlutterI18n.translate(
    //       context,
    //       'notifications.service.connected',
    //     ),
    //     notificationText: FlutterI18n.translate(
    //       context,
    //       'notifications.service.receiving',
    //     ),
    //   );
    // }
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

                        controller?.addJavaScriptHandler(
                          handlerName: 'regenerateNtfyTopic',
                          callback: (args) async {
                            String topic = Utils.generateRandomTopic();

                            await _prefs?.setString('topic', topic);

                            FlutterForegroundTask.sendDataToTask({
                              'topic': topic,
                            });
                          },
                        );
                      },
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        UserScript(
                          source: """
                                window.isFlutterWebView = true;
                          """,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      onUpdateVisitedHistory:
                          (controller, url, isReload) async {
                            if (url != null && !_isAppUrl(url.toString())) {
                              controller.goBack();
                              debugPrint(
                                '[foreground_service] Launching URL: $url',
                              );
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                      onLoadStop:
                          (InAppWebViewController webController, WebUri? url) {
                            String? topic = _prefs?.getString('topic');
                            if (topic != null) {
                              _injectFlutterInfo(topic);
                            } else {
                              developer.log(
                                'Missing topic, not injecting',
                                name: 'foreground_service',
                              );
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
                          Text(
                            FlutterI18n.translate(
                              context,
                              'app.loading-webview',
                            ),
                          ),
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
                      FlutterI18n.translate(
                        context,
                        'app.failed-to-load-webview',
                      ),
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
                      child: Text(FlutterI18n.translate(context, 'app.retry')),
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
                      child: Text(
                        FlutterI18n.translate(context, 'app.change-server'),
                      ),
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
