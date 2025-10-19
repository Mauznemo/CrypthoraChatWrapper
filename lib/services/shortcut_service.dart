import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class ShortcutService {
  static const MethodChannel _shortcutChannel = MethodChannel(
    'dev.mauznemo.crypthora_chat_wrapper/shortcuts',
  );

  static Future<void> pushDynamicShortcut({
    required String shortcutId, // Unique per chat, e.g., 'chat_123'
    required String
    shortLabel, // Chat name/username, max ~10 chars for launcher
    required Uint8List? imageBytes, // Profile/group image bytes
  }) async {
    if (imageBytes == null) return;

    try {
      await _shortcutChannel.invokeMethod('pushShortcut', {
        'shortcutId': shortcutId,
        'shortLabel': shortLabel,
        'imageBytes': imageBytes,
      });
    } catch (e) {
      debugPrint('[shortcut_service] Error pushing shortcut: $e');
    }
  }
}
