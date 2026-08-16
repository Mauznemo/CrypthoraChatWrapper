///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsDe with BaseTranslations<AppLocale, Translations> implements Translations {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsDe({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.de,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <de>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key);

	late final TranslationsDe _root = this; // ignore: unused_field

	@override 
	TranslationsDe $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsDe(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$notifications$de notifications = _Translations$notifications$de._(_root);
	@override late final _Translations$app$de app = _Translations$app$de._(_root);
	@override late final _Translations$common$de common = _Translations$common$de._(_root);
	@override late final _Translations$serverSettings$de serverSettings = _Translations$serverSettings$de._(_root);
}

// Path: notifications
class _Translations$notifications$de implements Translations$notifications$en {
	_Translations$notifications$de._(this._root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String newMessageDm({required Object count, required Object username}) => '${count} neue Nachrichten von ${username}';
	@override String newMessageGroup({required Object count, required Object chatName}) => '${count} neue Nachrichten in ${chatName}';
	@override String get you => 'Du';
	@override String get channelName => 'Nachrichten';
	@override String get channelDescription => 'Benachrichtigungen über neue Nachrichten';
	@override late final _Translations$notifications$service$de service = _Translations$notifications$service$de._(_root);
}

// Path: app
class _Translations$app$de implements Translations$app$en {
	_Translations$app$de._(this._root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get changeServer => 'Serveradresse ändern';
	@override String get failedToLoadWebview => 'Webview konnte nicht geladen werden';
	@override String get loadingWebview => 'Webview wird geladen...';
	@override String get retry => 'Wiederholen';
}

// Path: common
class _Translations$common$de implements Translations$common$en {
	_Translations$common$de._(this._root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get save => 'Speichern';
}

// Path: serverSettings
class _Translations$serverSettings$de implements Translations$serverSettings$en {
	_Translations$serverSettings$de._(this._root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get notificationServerUrl => 'URL des Benachrichtigungsservers';
	@override String get serverUrl => 'Server-URL';
	@override String get setServer => 'Server festlegen';
	@override String get pushProvider => 'Push-Anbieter';
	@override String get pushProviderFcm => 'Firebase (Google FCM)';
	@override String get checkingServer => 'Server wird geprüft...';
	@override String get fcmUnavailable => 'Auf diesem Server ist kein Firebase eingerichtet, daher sind nur ntfy-Anbieter verfügbar.';
}

// Path: notifications.service
class _Translations$notifications$service$de implements Translations$notifications$service$en {
	_Translations$notifications$service$de._(this._root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get connected => 'Verbunden';
	@override String get receiving => 'Empfangen von Echtzeit-Benachrichtigungen';
	@override String get disconnected => 'Getrennt';
	@override String get tryingToReconnect => 'Versuche, die Verbindung wiederherzustellen...';
	@override String get starting => 'Wird gestartet';
	@override String get startingText => 'Benachrichtigungsdienst wird gestartet';
}

/// The flat map containing all translations for locale <de>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsDe {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'notifications.newMessageDm' => ({required Object count, required Object username}) => '${count} neue Nachrichten von ${username}',
			'notifications.newMessageGroup' => ({required Object count, required Object chatName}) => '${count} neue Nachrichten in ${chatName}',
			'notifications.you' => 'Du',
			'notifications.channelName' => 'Nachrichten',
			'notifications.channelDescription' => 'Benachrichtigungen über neue Nachrichten',
			'notifications.service.connected' => 'Verbunden',
			'notifications.service.receiving' => 'Empfangen von Echtzeit-Benachrichtigungen',
			'notifications.service.disconnected' => 'Getrennt',
			'notifications.service.tryingToReconnect' => 'Versuche, die Verbindung wiederherzustellen...',
			'notifications.service.starting' => 'Wird gestartet',
			'notifications.service.startingText' => 'Benachrichtigungsdienst wird gestartet',
			'app.changeServer' => 'Serveradresse ändern',
			'app.failedToLoadWebview' => 'Webview konnte nicht geladen werden',
			'app.loadingWebview' => 'Webview wird geladen...',
			'app.retry' => 'Wiederholen',
			'common.save' => 'Speichern',
			'serverSettings.notificationServerUrl' => 'URL des Benachrichtigungsservers',
			'serverSettings.serverUrl' => 'Server-URL',
			'serverSettings.setServer' => 'Server festlegen',
			'serverSettings.pushProvider' => 'Push-Anbieter',
			'serverSettings.pushProviderFcm' => 'Firebase (Google FCM)',
			'serverSettings.checkingServer' => 'Server wird geprüft...',
			'serverSettings.fcmUnavailable' => 'Auf diesem Server ist kein Firebase eingerichtet, daher sind nur ntfy-Anbieter verfügbar.',
			_ => null,
		};
	}
}
