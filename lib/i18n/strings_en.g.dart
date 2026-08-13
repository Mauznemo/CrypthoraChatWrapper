///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$notifications$en notifications = Translations$notifications$en._(_root);
	late final Translations$app$en app = Translations$app$en._(_root);
	late final Translations$serverSettings$en serverSettings = Translations$serverSettings$en._(_root);
	late final Translations$common$en common = Translations$common$en._(_root);
}

// Path: notifications
class Translations$notifications$en {
	Translations$notifications$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '$count new messages in $chatName'
	String newMessageGroup({required Object count, required Object chatName}) => '${count} new messages in ${chatName}';

	/// en: '$count new messages from $username'
	String newMessageDm({required Object count, required Object username}) => '${count} new messages from ${username}';

	late final Translations$notifications$service$en service = Translations$notifications$service$en._(_root);
}

// Path: app
class Translations$app$en {
	Translations$app$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Loading webview...'
	String get loadingWebview => 'Loading webview...';

	/// en: 'Failed to load webview'
	String get failedToLoadWebview => 'Failed to load webview';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Change server address'
	String get changeServer => 'Change server address';
}

// Path: serverSettings
class Translations$serverSettings$en {
	Translations$serverSettings$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Set Server'
	String get setServer => 'Set Server';

	/// en: 'Server URL'
	String get serverUrl => 'Server URL';

	/// en: 'Notification Server URL'
	String get notificationServerUrl => 'Notification Server URL';

	/// en: 'Push Provider'
	String get pushProvider => 'Push Provider';
}

// Path: common
class Translations$common$en {
	Translations$common$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Save'
	String get save => 'Save';
}

// Path: notifications.service
class Translations$notifications$service$en {
	Translations$notifications$service$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Disconnected'
	String get disconnected => 'Disconnected';

	/// en: 'Receiving real-time notifications'
	String get receiving => 'Receiving real-time notifications';

	/// en: 'Trying to reconnect...'
	String get tryingToReconnect => 'Trying to reconnect...';

	/// en: 'Starting'
	String get starting => 'Starting';

	/// en: 'Starting notification service'
	String get startingText => 'Starting notification service';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'notifications.newMessageGroup' => ({required Object count, required Object chatName}) => '${count} new messages in ${chatName}',
			'notifications.newMessageDm' => ({required Object count, required Object username}) => '${count} new messages from ${username}',
			'notifications.service.connected' => 'Connected',
			'notifications.service.disconnected' => 'Disconnected',
			'notifications.service.receiving' => 'Receiving real-time notifications',
			'notifications.service.tryingToReconnect' => 'Trying to reconnect...',
			'notifications.service.starting' => 'Starting',
			'notifications.service.startingText' => 'Starting notification service',
			'app.loadingWebview' => 'Loading webview...',
			'app.failedToLoadWebview' => 'Failed to load webview',
			'app.retry' => 'Retry',
			'app.changeServer' => 'Change server address',
			'serverSettings.setServer' => 'Set Server',
			'serverSettings.serverUrl' => 'Server URL',
			'serverSettings.notificationServerUrl' => 'Notification Server URL',
			'serverSettings.pushProvider' => 'Push Provider',
			'common.save' => 'Save',
			_ => null,
		};
	}
}
