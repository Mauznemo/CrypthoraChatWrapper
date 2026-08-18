import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypthora_chat_wrapper/i18n/strings.g.dart';
import 'package:crypthora_chat_wrapper/pages/add_server_page.dart';
import 'package:crypthora_chat_wrapper/pages/settings_page.dart';
import 'package:crypthora_chat_wrapper/services/fcm_service.dart';
import 'package:crypthora_chat_wrapper/services/pending_chat_service.dart';
import 'package:crypthora_chat_wrapper/services/push_service.dart';
import 'package:crypthora_chat_wrapper/services/shortcut_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:person_shortcut_creator/person_shortcut_creator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
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
  String? _fcmToken;
  bool _usesFcm = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<PendingChat>? _pendingChatSub;
  StreamSubscription<ShortcutLaunch>? _shortcutSub;

  /// A chat to open that arrived before the page was ready to be told about it.
  PendingChat? _pendingChat;

  /// Guards [_handleBack] against a second press landing mid round trip to the web app.
  bool _handlingBack = false;

  /// Last insets handed to the web app, so [didChangeMetrics] can skip the frames that changed
  /// nothing it cares about.
  EdgeInsets? _sentSafeAreaInsets;

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

  void _init() async {
    _prefs = await SharedPreferences.getInstance();

    _packageInfo = await PackageInfo.fromPlatform();

    _serverUrl = _prefs?.getString('server_url');

    _usesFcm = await PushProvider.isFcm;

    await _loadPushToken();

    // The registration is async and may not have landed yet on a fresh install. Polling instead of
    // sleeping the full timeout keeps the usual launch instant.
    for (var i = 0; i < 20 && !_isPushRegistered; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      await _prefs?.reload();
      await _loadPushToken();
    }

    debugPrint('[chat_page] fcm: $_usesFcm, topic: $_topic');

    await _prefs?.setString(
      'locale',
      LocaleSettings.currentLocale.languageCode,
    );

    if (!mounted) return;

    if (_serverUrl == null || _serverUrl!.isEmpty || !_isPushRegistered) {
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

    // Whatever this launch was for, worked out once in main().
    _pendingChat = PendingChatService.take();
    _serverUri = _getChatUri(_pendingChat?.chatId);

    if (!mounted) return;
    setState(() {
      isReady = true;
    });
  }

  /// Reads whichever push identifier the selected provider produced.
  Future<void> _loadPushToken() async {
    if (_usesFcm) {
      _fcmToken = _prefs?.getString('fcm_token');
    } else {
      _topic = _prefs?.getString('topic');
    }
  }

  /// The selected provider handed us something to give the web app.
  bool get _isPushRegistered {
    final token = _usesFcm ? _fcmToken : _topic;
    return token != null && token.isNotEmpty;
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
    _listenForTokenRefresh();
    _listenForPendingChats();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Person shortcut taps and shares that land while the app is already running.
  void _listenForPendingChats() {
    _shortcutSub = PersonShortcutCreator.launches.listen((launch) {
      PendingChatService.offer(
        PendingChat(
          chatId: launch.shortcutId,
          sharedText: launch.sharedText,
          source: launch.sharedText != null
              ? PendingChatSource.share
              : PendingChatSource.shortcut,
        ),
      );
    });

    _pendingChatSub = PendingChatService.stream.listen((_) {
      final pending = PendingChatService.take();
      if (pending == null) return;

      if (controller == null || !isReady) {
        _pendingChat = pending;
        return;
      }
      _deliverPendingChat(pending);
    });
  }

  /// Hands the web app the chat it should open, and any text that was shared to it.
  ///
  /// Both halves are set as globals as well as called directly: the page may still be mounting
  /// when this runs, in which case the web app picks the globals up once it connects.
  Future<void> _deliverPendingChat(PendingChat pending) async {
    debugPrint('[chat_page] Delivering $pending');
    final chatId = jsonEncode(pending.chatId);
    final sharedText = jsonEncode(pending.sharedText);

    await controller?.evaluateJavascript(
      source:
          '''
      (function () {
        var chatId = $chatId;
        var sharedText = $sharedText;
        window.__pendingChatId = chatId;
        window.__pendingSharedText = sharedText;
        if (sharedText != null && window.shareToChat) {
          window.shareToChat(chatId, sharedText);
          window.__pendingChatId = null;
          window.__pendingSharedText = null;
        } else if (chatId != null && window.goToChat) {
          window.goToChat(chatId);
          window.__pendingChatId = null;
        }
      })();
    ''',
    );
  }

  /// FCM tokens rotate, the web app has to re-register the new one with the server.
  Future<void> _listenForTokenRefresh() async {
    // Firebase is only initialized when FCM is the selected provider
    if (!await PushProvider.isFcm || Firebase.apps.isEmpty) return;

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      debugPrint('[chat_page] FCM token refreshed');
      await FcmService.saveToken(token);
      _fcmToken = token;

      await controller?.evaluateJavascript(
        source:
            '''
        window.fcmToken = "$token";
        if (window.reRegisterPush) {
          window.reRegisterPush();
        }
      ''',
      );
    });
  }

  @override
  void dispose() {
    _tokenRefreshSub?.cancel();
    _pendingChatSub?.cancel();
    _shortcutSub?.cancel();
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
        // Nothing about notifications is read here on purpose. Unread counts are cleared per chat
        // by the web app's `chatOpened` call, so resuming into chat A no longer wipes chat B's
        // count, and nothing re-reads the launch intent to replay an old chat.
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

  @override
  void didChangeMetrics() {
    // MediaQuery has not been rebuilt yet when this fires, so the new insets are only readable
    // after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Rotation, a switch between gesture and 3 button navigation, a cutout change - but also
      // every frame of the keyboard animation, so unchanged insets are not worth a round trip.
      if (MediaQuery.of(context).padding == _sentSafeAreaInsets) return;
      _injectFlutterInfo();
    });
  }

  /// The push identifier the web app registers with the server, only one provider is ever active.
  String get _pushGlobals =>
      'window.ntfyTopic = "${_usesFcm ? '' : (_topic ?? '')}";\n'
      'window.fcmToken = "${_usesFcm ? (_fcmToken ?? '') : ''}";';

  /// The insets the web app pads itself with, as a JS assignment.
  ///
  /// Also injected at document start, because the notification below only reaches a web app that
  /// has already hydrated. The page finishing its load before its route chunk has run is a real
  /// ordering (SvelteKit imports routes dynamically, and `load` does not wait for those), and it
  /// used to leave the web app on the zeroes it starts with for the rest of the page's life.
  String _safeAreaGlobals(EdgeInsets padding) =>
      'window.flutterSafeAreaInsets = {'
      'top: ${padding.top},'
      'bottom: ${padding.bottom},'
      'left: ${padding.left},'
      'right: ${padding.right}'
      '};';

  Future<void> _injectFlutterInfo() async {
    final padding = MediaQuery.of(context).padding;
    _sentSafeAreaInsets = padding;

    final data =
        '''
            window.isFlutterWebView = true;
            window.wrapperVersion = "${_packageInfo?.version ?? 'Unknown'}";
            $_pushGlobals
            ${_safeAreaGlobals(padding)}
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

  /// Whether a URL belongs to the configured server.
  ///
  /// Compared by origin rather than by prefix, so a trailing slash or a path that merely starts
  /// with the server URL cannot be mistaken for an external link.
  bool _isAppUrl(Uri url) {
    final server = _serverUri;
    if (server == null) return false;
    return url.scheme == server.scheme &&
        url.host == server.host &&
        url.port == server.port;
  }

  void _registerJavaScriptHandlers() {
    controller?.addJavaScriptHandler(
      handlerName: 'openSettings',
      callback: (args) async {
        if (!mounted) return;
        // A push, not a pushReplacement: the WebView stays alive underneath, so coming back does
        // not reload the whole web app.
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SettingsPage()),
        );
      },
    );

    controller?.addJavaScriptHandler(
      handlerName: 'openUrl',
      callback: (args) async {
        final String url = args[0];
        debugPrint('[chat_page] Launching URL: $url');
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
    );

    // The web app owns the chat list, so it is the only thing that can keep the person shortcuts
    // (launcher search, share sheet, conversation notifications) up to date.
    controller?.addJavaScriptHandler(
      handlerName: 'syncShortcuts',
      callback: (args) async {
        if (args.isEmpty || args.first is! List) return;
        await ShortcutService.sync(args.first as List);
      },
    );

    // Sent when a chat is actually on screen, which is the only moment its messages count as seen.
    controller?.addJavaScriptHandler(
      handlerName: 'chatOpened',
      callback: (args) async {
        final chatId = args.isEmpty ? null : args.first as String?;
        if (chatId == null || chatId.isEmpty) return;
        debugPrint('[chat_page] Chat opened: $chatId');
        await PushService().clearUnreadCount(chatId);
        await ShortcutService.reportUsed(chatId);
      },
    );
  }

  /// Whether the web app dismissed something of its own, so back should stop here.
  ///
  /// Modals, sheets, the sidebar and the pickers are plain component state over there, none of it
  /// backed by a history entry, so nothing but the web app can know they are open.
  ///
  /// The JS side has to answer synchronously: a promise does not marshal back through
  /// evaluateJavascript, it arrives as an empty map and would read as "not handled".
  Future<bool> _webAppHandledBack() async {
    // The error overlay is covering the WebView, there is no web app to ask.
    if (_loadError) return false;
    try {
      final result = await controller
          ?.evaluateJavascript(
            source: 'window.handleBackPress ? window.handleBackPress() : false',
          )
          .timeout(const Duration(milliseconds: 300));
      return result == true;
    } catch (e) {
      // A wedged or half loaded page must never be able to trap the user in the app.
      debugPrint('[chat_page] handleBackPress failed: $e');
      return false;
    }
  }

  Future<void> _handleBack() async {
    if (_handlingBack) return;
    _handlingBack = true;
    try {
      // Whatever the web app has stacked on top of the page comes off first, an overlay is always
      // above the page it was opened from.
      if (await _webAppHandledBack()) return;
      // Then back inside the web app, so it does not exit the app from a sub page and force a cold
      // start (which reads as "the app reloaded itself") on the next launch.
      if (await controller?.canGoBack() ?? false) {
        await controller?.goBack();
        return;
      }
      // Leaves the app, same as before. Navigator.maybePop would re-enter this callback, since the
      // PopScope above already refused the pop.
      await SystemNavigator.pop();
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: isReady
            ? Stack(
                children: [
                  InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(_serverUri.toString()),
                      ),
                      initialSettings: _webViewSettings,
                      onWebViewCreated: (InAppWebViewController webController) {
                        controller = webController;
                        _registerJavaScriptHandlers();
                      },
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        // Set before the page runs: it registers for push on mount, and reads the
                        // insets while hydrating.
                        UserScript(
                          source:
                              """
                                window.isFlutterWebView = true;
                                $_pushGlobals
                                ${_safeAreaGlobals(MediaQuery.of(context).padding)}
                          """,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      onLoadStart: (controller, url) {
                        if (!_loadError) return;
                        setState(() => _loadError = false);
                      },
                      onLoadStop:
                          (InAppWebViewController webController, WebUri? url) async {
                            // Runs even without a push token: the web app still has to be told
                            // how to pad itself.
                            await _injectFlutterInfo();

                            if (!_isPushRegistered) {
                              developer.log(
                                'Missing push token, not delivering pending chat',
                                name: 'chat_page',
                              );
                              return;
                            }

                            final pending = _pendingChat;
                            if (pending != null) {
                              _pendingChat = null;
                              await _deliverPendingChat(pending);
                            }
                          },
                      onReceivedError: (controller, request, error) {
                        // Fires for subresources too. Without this a single failed avatar or icon
                        // request replaced the whole session with the error screen.
                        if (request.isForMainFrame != true) return;
                        if (error.type == WebResourceErrorType.CANCELLED) return;
                        setState(() {
                          _loadError = true;
                          _errorMessage = error.description;
                        });
                      },
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                            final url = navigationAction.request.url;
                            if (url == null) {
                              return NavigationActionPolicy.ALLOW;
                            }
                            // about:/blob:/data: are the web app's own machinery, never links out.
                            if (!url.scheme.startsWith('http')) {
                              return NavigationActionPolicy.ALLOW;
                            }
                            if (_isAppUrl(url) ||
                                navigationAction.isForMainFrame != true) {
                              return NavigationActionPolicy.ALLOW;
                            }

                            debugPrint('[chat_page] Launching URL: $url');
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                            return NavigationActionPolicy.CANCEL;
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
                  ),
                  // Laid over the WebView rather than replacing it, so retrying is a reload of the
                  // existing session instead of a fresh page load.
                  if (_loadError) Positioned.fill(child: _buildErrorView()),
                ],
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    Text(context.t.app.loadingWebview),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildErrorView() {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                context.t.app.failedToLoadWebview,
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),
              Text(_errorMessage, style: TextStyle(fontSize: 16)),
              const SizedBox(height: 5),
              Text('Server: $_serverUri', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 56),
              FilledButton(
                onPressed: () {
                  setState(() => _loadError = false);
                  controller?.reload();
                },
                child: Text(context.t.app.retry),
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
                child: Text(context.t.app.changeServer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
