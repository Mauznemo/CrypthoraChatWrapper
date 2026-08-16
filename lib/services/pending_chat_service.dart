import 'dart:async';

import 'package:flutter/foundation.dart';

enum PendingChatSource { notification, shortcut, share }

/// A chat the app should open, and anything that came along with it.
class PendingChat {
  final String? chatId;
  final String? sharedText;
  final PendingChatSource source;

  const PendingChat({this.chatId, this.sharedText, required this.source});

  @override
  String toString() =>
      'PendingChat(chatId: $chatId, sharedText: ${sharedText != null}, source: $source)';
}

/// The single answer to "which chat should be open".
///
/// Notification taps, shortcut taps and shares all funnel through here, and every one of them is
/// consumed exactly once. Nothing is persisted on purpose: a stored target outlives the launch that
/// created it, which is how the app used to jump back into a stale chat on every resume.
class PendingChatService {
  static PendingChat? _pending;
  static final _controller = StreamController<PendingChat>.broadcast();

  /// Fires as soon as a target arrives, for when the web app is already up and can be told
  /// directly. Listeners still have to [take] it so it is not delivered twice.
  static Stream<PendingChat> get stream => _controller.stream;

  static void offer(PendingChat pending) {
    if (pending.chatId == null && pending.sharedText == null) return;
    debugPrint('[pending_chat] Offered $pending');
    _pending = pending;
    _controller.add(pending);
  }

  /// Returns the pending target and clears it, so it can only ever be delivered once.
  static PendingChat? take() {
    final pending = _pending;
    _pending = null;
    return pending;
  }
}
