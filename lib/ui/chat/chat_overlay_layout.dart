import 'package:flutter/foundation.dart';

import 'chat_corner.dart';

/// Immutable placement state for the chat card: which corner it sits in,
/// whether it is collapsed to the peek tab, and the corner to restore to.
@immutable
class ChatOverlayLayout {
  const ChatOverlayLayout({
    this.corner = ChatCorner.bottomLeft,
    this.collapsed = false,
    this.lastCorner = ChatCorner.bottomLeft,
  });

  final ChatCorner corner;
  final bool collapsed;
  final ChatCorner lastCorner;

  ChatOverlayLayout copyWith({
    ChatCorner? corner,
    bool? collapsed,
    ChatCorner? lastCorner,
  }) =>
      ChatOverlayLayout(
        corner: corner ?? this.corner,
        collapsed: collapsed ?? this.collapsed,
        lastCorner: lastCorner ?? this.lastCorner,
      );

  /// Apply a drag-release result: snap to a corner, or collapse (remembering
  /// the current corner so [toggle] can restore it).
  ChatOverlayLayout applySnap(SnapResult result) {
    if (result.collapsed) {
      return copyWith(collapsed: true, lastCorner: corner);
    }
    return copyWith(corner: result.corner, collapsed: false);
  }

  /// Collapse↔expand. Collapsing remembers the corner; expanding restores it.
  ChatOverlayLayout toggle() {
    if (collapsed) {
      return copyWith(collapsed: false, corner: lastCorner);
    }
    return copyWith(collapsed: true, lastCorner: corner);
  }

  @override
  bool operator ==(Object other) =>
      other is ChatOverlayLayout &&
      other.corner == corner &&
      other.collapsed == collapsed &&
      other.lastCorner == lastCorner;

  @override
  int get hashCode => Object.hash(corner, collapsed, lastCorner);
}
