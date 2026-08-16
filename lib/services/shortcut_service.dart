import 'dart:convert';

import 'package:crypthora_chat_wrapper/utils/avatar_cache.dart';
import 'package:crypthora_chat_wrapper/utils/disk_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:person_shortcut_creator/person_shortcut_creator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the Android conversation shortcuts in step with the web app's chat list.
///
/// The shortcuts are what back launcher search, the conversation section of the shade and the
/// direct share row, so they have to exist for chats the user has simply not been messaged by
/// recently. The web app pushes its list over the bridge, this turns it into shortcuts.
class ShortcutService {
  /// Has to match the category declared in `res/xml/shortcuts.xml`, otherwise nothing shows up in
  /// the share sheet.
  static const shareTargetCategory =
      'dev.mauznemo.crypthora_chat_wrapper.category.SHARE_TARGET';

  /// Sharesheet guidance is 4-5 targets. Devices report anywhere from 5 to 15, so this is a cap on
  /// top of whatever the system allows.
  static const _preferredCount = 8;
  static const _fallbackCount = 4;
  static const _syncHashKey = 'shortcut_sync_hash';

  /// The push isolate writes this too, so it cannot go through the caching prefs API.
  static final _prefs = SharedPreferencesAsync();

  static const _categories = [
    PersonShortcutCreator.conversationCategory,
    shareTargetCategory,
  ];

  /// Replaces the published shortcuts with [chats], which arrive from the web app as
  /// `{id, label, imageUrl}` ordered most recent first.
  static Future<void> sync(List<dynamic> chats) async {
    try {
      final hash = jsonEncode(chats).hashCode.toString();
      // The web app resyncs on every chat list refresh, which is far more often than the list
      // actually changes.
      if (await _prefs.getString(_syncHashKey) == hash) return;

      final max = await PersonShortcutCreator.getMaxShortcutCount();
      final limit = (max > 0 ? max : _fallbackCount).clamp(1, _preferredCount);

      final avatarCache = AvatarCache();
      final specs = <ShortcutSpec>[];

      for (final chat in chats.take(limit)) {
        final map = (chat as Map).cast<String, dynamic>();
        final id = map['id'] as String?;
        final label = map['label'] as String?;
        if (id == null || label == null || label.isEmpty) continue;

        specs.add(
          ShortcutSpec(
            shortcutId: id,
            shortLabel: label,
            imagePath: await avatarCache.getImagePath(
              map['imageUrl'] as String?,
            ),
            categories: _categories,
            rank: specs.length,
          ),
        );
      }

      await PersonShortcutCreator.setShortcuts(specs);
      await _prefs.setString(_syncHashKey, hash);
      debugPrint('[shortcut_service] Synced ${specs.length} shortcuts');
    } catch (e) {
      DiskLogger.error('[shortcut_service] Sync failed: $e');
    }
  }

  /// Publishes a single shortcut so an incoming notification can bind to it.
  ///
  /// Runs in the push isolate, where the web app's list is not available.
  static Future<void> pushForChat({
    required String chatId,
    required String label,
    String? imagePath,
  }) async {
    try {
      await PersonShortcutCreator.pushDynamicShortcut(
        ShortcutSpec(
          shortcutId: chatId,
          shortLabel: label,
          imagePath: imagePath,
          categories: _categories,
        ),
      );
      // This can evict a shortcut the last sync published, so the next sync has to actually run.
      await invalidateSyncCache();
    } catch (e) {
      DiskLogger.error('[shortcut_service] Error creating shortcut: $e');
    }
  }

  /// Tells Android the chat was opened, which is what ranks it in the share sheet over time.
  static Future<void> reportUsed(String chatId) async {
    try {
      await PersonShortcutCreator.reportShortcutUsed(chatId);
    } catch (e) {
      debugPrint('[shortcut_service] Report used failed: $e');
    }
  }

  /// Drops every published shortcut, for when the chats they point at are no longer reachable.
  static Future<void> clearAll() async {
    try {
      await PersonShortcutCreator.removeShortcutsExcept(const []);
      await invalidateSyncCache();
    } catch (e) {
      DiskLogger.error('[shortcut_service] Clear failed: $e');
    }
  }

  static Future<void> invalidateSyncCache() => _prefs.remove(_syncHashKey);
}
