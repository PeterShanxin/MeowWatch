import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';
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
  });

  final List<ChatMessage> messages;
  final String myUsername;
  final bool collapsed;
  final ChatCorner corner;
  final bool pulsing;
  final void Function(String text) onSend;
  final VoidCallback onToggleCollapsed;
  final void Function(SnapResult result) onSnap;

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

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: width,
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: const Color(0xF2241B14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xCCD4A574), width: 1.5),
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
                      const Icon(Icons.drag_indicator,
                          size: 16, color: Color(0x99F5E6D3)),
                      const Spacer(),
                      const Text('Chat',
                          style: TextStyle(
                              color: Color(0xFFF5E6D3), fontSize: 13)),
                      const Spacer(),
                      GestureDetector(
                        onTap: onCollapse,
                        child: const Icon(Icons.chevron_right,
                            size: 18, color: Color(0xFFD4A574)),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: messages.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 24),
                        child: Text(
                          'No messages yet — say hi 🐾',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0x99F5E6D3), fontSize: 13),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final m in messages)
                            ChatBubble(message: m, myUsername: myUsername),
                        ],
                      ),
              ),
              ChatInput(onSend: onSend),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
