import 'package:crypthora_chat_wrapper/i18n/strings.g.dart';
import 'package:crypthora_chat_wrapper/pages/chat_page.dart';
import 'package:crypthora_chat_wrapper/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sets up whichever push transport the user selected (UnifiedPush or FCM)
  await PushService().init();

  if (!args.contains("--unifiedpush-bg")) {
    await LocaleSettings.useDeviceLocale();

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
  } else {
    debugPrint(
      "Running in unifiedpush-bg mode, skipping Flutter initialization.",
    );
  }
}
