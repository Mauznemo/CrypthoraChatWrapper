import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:crypthora_chat_wrapper/pages/add_server_page.dart';
import 'package:crypthora_chat_wrapper/pages/settings_page.dart';
import 'package:crypthora_chat_wrapper/services/push_service.dart';
import 'package:crypthora_chat_wrapper/utils/i18n_helper.dart';
import 'package:flutter/material.dart';
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
  String? _serverUrl;
  bool isReady = false;
  bool _loadError = false;
  String _errorMessage = '';
  SharedPreferences? _prefs;
  PackageInfo? _packageInfo;
  String? _topic;

  InAppWebViewSettings get _webViewSettings => InAppWebViewSettings(
    useHybridComposition: true,
    hardwareAcceleration: true,

    allowsBackForwardNavigationGestures: true,
    disableHorizontalScroll: false,
    disableVerticalScroll: false,

    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,

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

    PushService.clearUnreadCounts();
    PushService.clearAllNotifications();

    _serverUrl = _prefs?.getString('server_url');

    _topic = _prefs?.getString('topic');

    if (_topic == null || _topic!.isEmpty) {
      await Future.delayed(const Duration(seconds: 5));
      _prefs?.reload();
      _topic = _prefs?.getString('topic');
    }

    debugPrint('[chat_page] topic: $_topic');

    await I18nHelper.saveCurrentLocale(context);

    if (_serverUrl == null ||
        _serverUrl!.isEmpty ||
        _topic == null ||
        _topic!.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AddServerPage(canGoBack: false),
        ),
      );
      return;
    }

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    String? chatId;

    if (launchDetails?.didNotificationLaunchApp == true) {
      final String? payload = launchDetails!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        debugPrint(
          '[chat_page] Init: App launched from notification with payload: $payload',
        );

        chatId = payload;
      }
    }

    _serverUri = _getChatUri(chatId);

    setState(() {
      isReady = true;
    });
  }

  Uri _getChatUri([String? chatId]) {
    if (chatId != null) {
      if (_serverUrl!.endsWith('/')) {
        _serverUrl = _serverUrl!.substring(0, _serverUrl!.length - 1);
      }
      return Uri.parse(
        '$_serverUrl/chat',
      ).replace(queryParameters: {'chatId': chatId});
    } else {
      return Uri.parse(_serverUrl!);
    }
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
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
        await controller?.evaluateJavascript(
          source: """
      if (window.setSocketInactive) {
        window.setSocketInactive();
      }
    """,
        );
        break;
      case AppLifecycleState.resumed:
        PushService.clearUnreadCounts();
        PushService.clearAllNotifications();

        final NotificationAppLaunchDetails? launchDetails = await _notifications
            .getNotificationAppLaunchDetails();

        if (launchDetails?.didNotificationLaunchApp == true) {
          final String? payload = launchDetails!.notificationResponse?.payload;
          if (payload != null && payload.isNotEmpty) {
            debugPrint(
              '[chat_page] AppLifecycleState.resumed: App launched from notification with payload: $payload',
            );
            await controller?.evaluateJavascript(
              source:
                  """
          if (window.goToChat) {
            window.goToChat('$payload');
          }
        """,
            );
          }
        }

        await controller?.evaluateJavascript(
          source: """
      if (window.setSocketActive) {
        window.setSocketActive();
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

  Future<void> _injectFlutterInfo(String topic) async {
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

    await controller?.evaluateJavascript(source: data);
    await controller?.evaluateJavascript(
      source: """
      if (window.onFlutterSafeAreaInsetsChanged) {
        window.onFlutterSafeAreaInsetsChanged();
      }
    """,
    );
  }

  bool _isAppUrl(String url) {
    String? serverUrl = _prefs?.getString('server_url') ?? 'http';
    return url.startsWith(serverUrl);
  }

  @override
  Widget build(BuildContext context) {
    return !_loadError
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
                              builder: (context) => SettingsPage(),
                            ),
                          );
                        },
                      );

                      controller?.addJavaScriptHandler(
                        handlerName: 'openUrl',
                        callback: (args) async {
                          final String url = args[0];
                          debugPrint('[chat_page] Launching URL: $url');
                          await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      );
                    },
                    initialUserScripts: UnmodifiableListView<UserScript>([
                      UserScript(
                        source:
                            """
                                window.isFlutterWebView = true;
                                window.topic = "${_topic ?? ''}";
                          """,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                    onUpdateVisitedHistory: (controller, url, isReload) async {
                      if (url != null && !_isAppUrl(url.toString())) {
                        controller.goBack();
                        debugPrint(
                          '[chat_page] Launching URL (fallback on navigate): $url',
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
                          FlutterI18n.translate(context, 'app.loading-webview'),
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
                          builder: (context) => AddServerPage(canGoBack: true),
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
          );
  }
}
