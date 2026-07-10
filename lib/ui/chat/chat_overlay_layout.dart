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
    this.widthPx,
    this.heightPx,
  });

  final ChatCorner corner;
  final bool collapsed;
  final ChatCorner lastCorner;

  /// Card width/height in logical px. Null = use the default size. Stored in px
  /// (not a window fraction) so the card keeps a stable physical size when the
  /// window is resized/maximized; the view clamps it to the viewport.
  final double? widthPx;
  final double? heightPx;

  ChatOverlayLayout copyWith({
    ChatCorner? corner,
    bool? collapsed,
    ChatCorner? lastCorner,
    double? widthPx,
    double? heightPx,
  }) =>
      ChatOverlayLayout(
        corner: corner ?? this.corner,
        collapsed: collapsed ?? this.collapsed,
        lastCorner: lastCorner ?? this.lastCorner,
        widthPx: widthPx ?? this.widthPx,
        heightPx: heightPx ?? this.heightPx,
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

  /// Record a new px size.
  ChatOverlayLayout applyResize(Size px) => copyWith(
        widthPx: px.width,
        heightPx: px.height,
      );

  /// Clear the custom size (back to the default px size).
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
      other.widthPx == widthPx &&
      other.heightPx == heightPx;

  @override
  int get hashCode =>
      Object.hash(corner, collapsed, lastCorner, widthPx, heightPx);
}

/// Smallest/largest px a stored card dimension may take. A value outside this
/// range (e.g. a legacy fraction string like "0.30") is treated as invalid so
/// it falls back to the default size.
const double _kMinStoredPx = 50;
const double _kMaxStoredPx = 10000;

/// Serialize a px size for [kChatCardSizeSettingKey] storage (rounded ints).
String formatCardSize(double widthPx, double heightPx) =>
    '${widthPx.round()},${heightPx.round()}';

/// Parse a stored size value into (widthPx, heightPx). Returns (null, null) for
/// missing, empty, malformed, or out-of-range values (including legacy fraction
/// strings, which are below the px floor and so ignored → default size).
(double?, double?) parseCardSize(String? value) {
  if (value == null || value.isEmpty) return (null, null);
  final parts = value.split(',');
  if (parts.length != 2) return (null, null);
  final w = double.tryParse(parts[0]);
  final h = double.tryParse(parts[1]);
  if (w == null || h == null) return (null, null);
  if (w < _kMinStoredPx || w > _kMaxStoredPx) return (null, null);
  if (h < _kMinStoredPx || h > _kMaxStoredPx) return (null, null);
  return (w, h);
}

/// Apply the persisted card size and corner (their raw stored strings) onto
/// [base], keeping everything else — used on every room entry so the card
/// comes back where and how big it was left, not as the app-startup snapshot.
/// Missing/invalid stored values keep the base's values.
///
/// The corner fills BOTH corner slots: the card enters a room collapsed, and
/// expanding restores `lastCorner` — corner alone would be discarded by the
/// first toggle.
ChatOverlayLayout restoredLayout({
  required ChatOverlayLayout base,
  required String? sizeValue,
  required String? cornerValue,
}) {
  final (w, h) = parseCardSize(sizeValue);
  final corner = parseCardCorner(cornerValue);
  return ChatOverlayLayout(
    collapsed: base.collapsed,
    corner: corner ?? base.corner,
    lastCorner: corner ?? base.lastCorner,
    widthPx: w ?? base.widthPx,
    heightPx: h ?? base.heightPx,
  );
}

/// Serialize a corner for [kChatCardCornerSettingKey] storage (the enum name,
/// e.g. `"bottomLeft"`).
String formatCardCorner(ChatCorner corner) => corner.name;

/// Parse a stored corner name. Returns null for missing or unknown values so
/// the caller falls back to the default corner.
ChatCorner? parseCardCorner(String? value) {
  if (value == null || value.isEmpty) return null;
  for (final corner in ChatCorner.values) {
    if (corner.name == value) return corner;
  }
  return null;
}
