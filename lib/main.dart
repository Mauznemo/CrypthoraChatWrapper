import 'package:crypthora_chat_wrapper/i18n/strings.g.dart';
import 'package:crypthora_chat_wrapper/pages/chat_page.dart';
import 'package:crypthora_chat_wrapper/services/pending_chat_service.dart';
import 'package:crypthora_chat_wrapper/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:person_shortcut_creator/person_shortcut_creator.dart';

final _notifications = FlutterLocalNotificationsPlugin();

/// Fires when a notification is tapped while the app is already running.
///
/// Registering this is what replaced polling `getNotificationAppLaunchDetails()` on every resume:
/// that call keeps returning the intent the activity was launched with, so it re-opened the same
/// chat every time the app came back to the foreground.
@pragma('vm:entry-point')
void _onNotificationResponse(NotificationResponse response) {
  final chatId = response.payload;
  if (chatId == null || chatId.isEmpty) return;

  PendingChatService.offer(
    PendingChat(chatId: chatId, source: PendingChatSource.notification),
  );
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sets up whichever push transport the user selected (UnifiedPush or FCM)
  await PushService().init();

  if (args.contains("--unifiedpush-bg")) {
    debugPrint(
      "Running in unifiedpush-bg mode, skipping Flutter initialization.",
    );
    return;
  }

  await LocaleSettings.useDeviceLocale();

  await _notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: _onNotificationResponse,
  );
  await _createNotificationChannel();
  await _readInitialLaunch();

  runApp(
    TranslationProvider(
      child: Builder(
        builder: (context) {
          return MaterialApp(
            home: ChatPage(),
            theme: ThemeData(
              brightness: Brightness.light,
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.light,
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.dark,
              ),
            ),
            themeMode: ThemeMode.system,
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            locale: TranslationProvider.of(context).flutterLocale,
            supportedLocales: AppLocaleUtils.supportedLocales,
          );
        },
      ),
    ),
  );
}

/// Declares the channel up front instead of letting whichever isolate posts first define it.
Future<void> _createNotificationChannel() async {
  await _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        AndroidNotificationChannel(
          PushService.channelId,
          t.notifications.channelName,
          description: t.notifications.channelDescription,
          importance: Importance.high,
        ),
      );
}

/// Works out whether this launch came from a notification, a person shortcut or a share.
///
/// Read once, at startup, and never again: both sources keep answering with the original launch
/// for as long as the activity lives.
Future<void> _readInitialLaunch() async {
  final details = await _notifications.getNotificationAppLaunchDetails();
  final payload = details?.didNotificationLaunchApp == true
      ? details!.notificationResponse?.payload
      : null;

  if (payload != null && payload.isNotEmpty) {
    PendingChatService.offer(
      PendingChat(chatId: payload, source: PendingChatSource.notification),
    );
    return;
  }

  final launch = await PersonShortcutCreator.getInitialLaunch();
  if (launch == null) return;

  PendingChatService.offer(
    PendingChat(
      chatId: launch.shortcutId,
      sharedText: launch.sharedText,
      source: launch.sharedText != null
          ? PendingChatSource.share
          : PendingChatSource.shortcut,
    ),
  );
}
