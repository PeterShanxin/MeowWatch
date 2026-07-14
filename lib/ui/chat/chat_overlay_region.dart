import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';
import '../../core/theme/tokens/motion.dart';
import '../idle_visibility.dart';
import 'chat_corner.dart';
import 'chat_overlay.dart';
import 'chat_overlay_layout.dart';

/// The chat card's slice of the room screen, listening to its own hot state.
///
/// Chat lines, typing signals, peek pulses, and unread flips are the room's
/// highest-frequency events; when the room screen held them as plain fields,
/// every one forced a setState that rebuilt the entire room Stack — player
/// menu, banner, reaction bar and all (#196). This region subscribes to them
/// as [ValueListenable]s instead, so an event dirties only the card's own
/// subtree; the parent passes the rare, user-driven state (layout, idle,
/// settings) as plain fields and still rebuilds normally when those change.
///
/// Structure note: [ChatOverlay] is mounted under `AnimatedOpacity >
/// IgnorePointer` — NOT a Stack — and its render path must stay legal there
/// (#50); this widget preserves that exact mount.
class ChatOverlayRegion extends StatelessWidget {
  const ChatOverlayRegion({
    required this.messages,
    required this.typingLabel,
    required this.pulsing,
    required this.hasUnread,
    required this.layout,
    required this.isUiIdle,
    required this.isUiDeepIdle,
    required this.autoDim,
    required this.wakeOnMessage,
    required this.idleDimOpacity,
    required this.onSend,
    required this.onTypingChanged,
    required this.onToggleCollapsed,
    required this.onSnap,
    required this.onDraggingChanged,
    required this.onUnreadChanged,
    required this.onResize,
    required this.onResetSize,
    super.key,
  });

  /// Hot event state — changes rebuild only this region.
  final ValueListenable<List<ChatMessage>> messages;
  final ValueListenable<String?> typingLabel;
  final ValueListenable<bool> pulsing;
  final ValueListenable<bool> hasUnread;

  /// Rare, user-driven state — supplied per parent rebuild.
  final ChatOverlayLayout layout;
  final bool isUiIdle;
  final bool isUiDeepIdle;
  final bool autoDim;
  final bool wakeOnMessage;
  final double idleDimOpacity;

  final void Function(String text) onSend;
  final ValueChanged<bool> onTypingChanged;
  final VoidCallback onToggleCollapsed;
  final void Function(SnapResult result) onSnap;
  final ValueChanged<bool> onDraggingChanged;
  final ValueChanged<bool> onUnreadChanged;
  final void Function(Size newSize) onResize;
  final VoidCallback onResetSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([messages, typingLabel, pulsing, hasUnread]),
      builder: (context, _) {
        final opacity = chatOverlayOpacity(
          idle: isUiIdle,
          deepIdle: isUiDeepIdle,
          collapsed: layout.collapsed,
          autoDim: autoDim,
          hasUnread: hasUnread.value,
          wakeToFullyVisible: wakeOnMessage,
          ghostOpacity: idleDimOpacity,
        );
        return AnimatedOpacity(
          opacity: opacity,
          duration: Motion.base,
          child: IgnorePointer(
            ignoring: opacity == 0.0,
            child: ChatOverlay(
              messages: messages.value,
              collapsed: layout.collapsed,
              isUiIdle: isUiIdle,
              corner: layout.corner,
              pulsing: pulsing.value,
              onSend: onSend,
              typingLabel: typingLabel.value,
              onTypingChanged: onTypingChanged,
              onToggleCollapsed: onToggleCollapsed,
              onSnap: onSnap,
              onDraggingChanged: onDraggingChanged,
              onUnreadChanged: onUnreadChanged,
              widthPx: layout.widthPx,
              heightPx: layout.heightPx,
              onResize: onResize,
              onResetSize: onResetSize,
            ),
          ),
        );
      },
    );
  }
}
