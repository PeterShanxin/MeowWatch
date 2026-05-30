import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'chat_corner.dart';

/// Immutable placement + size state for the chat card.
@immutable
class ChatOverlayLayout {
  const ChatOverlayLayout({
    this.corner = ChatCorner.bottomLeft,
    this.collapsed = false,
    this.lastCorner = ChatCorner.bottomLeft,
    this.widthFrac,
    this.heightFrac,
  });

  final ChatCorner corner;
  final bool collapsed;
  final ChatCorner lastCorner;

  /// Card width/height as a fraction (0..1) of the window. Null = use default.
  final double? widthFrac;
  final double? heightFrac;

  ChatOverlayLayout copyWith({
    ChatCorner? corner,
    bool? collapsed,
    ChatCorner? lastCorner,
    double? widthFrac,
    double? heightFrac,
  }) =>
      ChatOverlayLayout(
        corner: corner ?? this.corner,
        collapsed: collapsed ?? this.collapsed,
        lastCorner: lastCorner ?? this.lastCorner,
        widthFrac: widthFrac ?? this.widthFrac,
        heightFrac: heightFrac ?? this.heightFrac,
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

  /// Record a new px size as fractions of [window].
  ChatOverlayLayout applyResize(Size px, Size window) => copyWith(
        widthFrac: px.width / window.width,
        heightFrac: px.height / window.height,
      );

  /// Clear the custom size (back to the default fractions).
  ChatOverlayLayout resetSize() => ChatOverlayLayout(
        corner: corner,
        collapsed: collapsed,
        lastCorner: lastCorner,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatOverlayLayout &&
      other.corner == corner &&
      other.collapsed == collapsed &&
      other.lastCorner == lastCorner &&
      other.widthFrac == widthFrac &&
      other.heightFrac == heightFrac;

  @override
  int get hashCode =>
      Object.hash(corner, collapsed, lastCorner, widthFrac, heightFrac);
}

/// Serialize size fractions for [kChatCardSizeSettingKey] storage.
String formatCardSizeFraction(double widthFrac, double heightFrac) =>
    '$widthFrac,$heightFrac';

/// Parse a stored size value into (widthFrac, heightFrac). Returns (null, null)
/// for missing, empty, malformed, or out-of-range (0..1) values.
(double?, double?) parseCardSizeFraction(String? value) {
  if (value == null || value.isEmpty) return (null, null);
  final parts = value.split(',');
  if (parts.length != 2) return (null, null);
  final w = double.tryParse(parts[0]);
  final h = double.tryParse(parts[1]);
  if (w == null || h == null) return (null, null);
  if (w <= 0 || w > 1 || h <= 0 || h > 1) return (null, null);
  return (w, h);
}
