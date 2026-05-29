import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';
import 'chat_bubble.dart';
import 'chat_corner.dart';
import 'chat_input.dart';
import 'peek_tab.dart';

/// The floating chat card. Presentational: the parent owns the layout state
/// (corner + collapsed) and supplies callbacks. Dragging the header reports a
/// drag-release decision through [onSnap]; collapse/expand goes through
/// [onToggleCollapsed].
class ChatOverlay extends StatefulWidget {
  const ChatOverlay({
    super.key,
    required this.messages,
    required this.myUsername,
    required this.collapsed,
    required this.onSend,
    required this.onToggleCollapsed,
    required this.onSnap,
    this.corner = ChatCorner.bottomLeft,
    this.pulsing = false,
    this.typingLabel,
    this.onTypingChanged,
  });

  final List<ChatMessage> messages;
  final String myUsername;
  final bool collapsed;
  final ChatCorner corner;
  final bool pulsing;
  final void Function(String text) onSend;
  final VoidCallback onToggleCollapsed;
  final void Function(SnapResult result) onSnap;

  /// e.g. "lin is typing…"; null when nobody is typing.
  final String? typingLabel;
  final ValueChanged<bool>? onTypingChanged;

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  // While dragging, a free top-left offset (relative to this overlay's own
  // box) overrides corner placement. Captured from the card's real rect at
  // drag start so the first grab never teleports.
  Offset? _dragTopLeft;
  // Real card + overlay sizes captured at drag start, used for snap math.
  Size? _dragCardSize;
  Size? _overlaySize;
  final GlobalKey _cardKey = GlobalKey();

  Alignment _alignmentFor(ChatCorner c) {
    switch (c) {
      case ChatCorner.topLeft:
        return Alignment.topLeft;
      case ChatCorner.topRight:
        return Alignment.topRight;
      case ChatCorner.bottomLeft:
        return Alignment.bottomLeft;
      case ChatCorner.bottomRight:
        return Alignment.bottomRight;
    }
  }

  /// Seed the free-drag offset from where the card actually sits right now.
  /// Converts the card's global top-left into this overlay's local space so
  /// the following [Positioned] keeps it under the cursor (no jump).
  void _startHeaderDrag() {
    final cardBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (cardBox == null || selfBox == null) return;
    final origin = selfBox.localToGlobal(Offset.zero);
    setState(() {
      _dragTopLeft = cardBox.localToGlobal(Offset.zero) - origin;
      _dragCardSize = cardBox.size;
      _overlaySize = selfBox.size;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      return Align(
        alignment: Alignment.centerRight,
        child:
            PeekTab(pulsing: widget.pulsing, onTap: widget.onToggleCollapsed),
      );
    }

    final media = MediaQuery.of(context).size;
    final cardSize = Size(media.width * 0.3, media.height * 0.5);

    final card = _GlassCard(
      key: _cardKey,
      width: cardSize.width,
      maxHeight: cardSize.height,
      onHeaderDragStart: _startHeaderDrag,
      onHeaderDragUpdate: (delta) {
        final base = _dragTopLeft;
        if (base == null) return;
        setState(() => _dragTopLeft = base + delta);
      },
      onHeaderDragEnd: () {
        final topLeft = _dragTopLeft;
        final card = _dragCardSize;
        final window = _overlaySize;
        if (topLeft != null && card != null && window != null) {
          widget.onSnap(computeSnap(
            dropTopLeft: topLeft,
            cardSize: card,
            windowSize: window,
          ));
        }
        setState(() {
          _dragTopLeft = null;
          _dragCardSize = null;
          _overlaySize = null;
        });
      },
      onCollapse: widget.onToggleCollapsed,
      messages: widget.messages,
      myUsername: widget.myUsername,
      onSend: widget.onSend,
      typingLabel: widget.typingLabel,
      onTypingChanged: widget.onTypingChanged,
    );

    final topLeft = _dragTopLeft;
    if (topLeft != null) {
      return Positioned(left: topLeft.dx, top: topLeft.dy, child: card);
    }
    return Align(
      alignment: _alignmentFor(widget.corner),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
        child: card,
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    super.key,
    required this.width,
    required this.maxHeight,
    required this.onHeaderDragStart,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onCollapse,
    required this.messages,
    required this.myUsername,
    required this.onSend,
    required this.typingLabel,
    required this.onTypingChanged,
  });

  final double width;
  final double maxHeight;
  final VoidCallback onHeaderDragStart;
  final void Function(Offset delta) onHeaderDragUpdate;
  final VoidCallback onHeaderDragEnd;
  final VoidCallback onCollapse;
  final List<ChatMessage> messages;
  final String myUsername;
  final void Function(String text) onSend;
  final String? typingLabel;
  final ValueChanged<bool>? onTypingChanged;

  /// Wrap [child] in a frosted-glass blur when the active theme asks for it
  /// (`glassBlur > 0`, e.g. Aurora). Returns [child] unchanged otherwise, so
  /// Cozy/Noir render with no BackdropFilter at all.
  Widget _frosted(BuildContext context, Widget child) {
    final blur = context.meow.glassBlur;
    if (blur <= 0) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: m.scrim.withValues(alpha: 0.60),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _frosted(
        context,
        Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: m.surface,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: m.accent.withValues(alpha: 0.80), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (_) => onHeaderDragStart(),
                onPanUpdate: (d) => onHeaderDragUpdate(d.delta),
                onPanEnd: (_) => onHeaderDragEnd(),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.drag_indicator, size: 16, color: m.textDim),
                      const Spacer(),
                      Text('Chat',
                          style: TextStyle(color: m.textPrimary, fontSize: 13)),
                      const Spacer(),
                      GestureDetector(
                        onTap: onCollapse,
                        child: Icon(Icons.chevron_right,
                            size: 18, color: m.accent),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: messages.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 24),
                        child: Text(
                          'No messages yet — say hi 🐾',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: m.textDim, fontSize: 13),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final msg in messages)
                            ChatBubble(message: msg, myUsername: myUsername),
                        ],
                      ),
              ),
              if (typingLabel != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                    child: Text(
                      typingLabel!,
                      style: TextStyle(
                        color: m.textDim,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ChatInput(onSend: onSend, onTypingChanged: onTypingChanged),
            ],
          ),
        ),
      ),
    );
  }
}
