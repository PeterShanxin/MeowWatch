import 'dart:ui' as ui;

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
  // While dragging, a free top-left offset overrides corner placement.
  Offset? _dragTopLeft;

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

  Offset _cornerTopLeft(ChatCorner c, Size window, Size card) {
    const m = 12.0;
    final left = (c == ChatCorner.topLeft || c == ChatCorner.bottomLeft)
        ? m
        : window.width - card.width - m;
    final top = (c == ChatCorner.topLeft || c == ChatCorner.topRight)
        ? m
        : window.height - card.height - m;
    return Offset(left, top);
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
      width: cardSize.width,
      maxHeight: cardSize.height,
      onHeaderDragUpdate: (delta) {
        setState(() {
          final base = _dragTopLeft ??
              _cornerTopLeft(widget.corner, media, cardSize);
          _dragTopLeft = base + delta;
        });
      },
      onHeaderDragEnd: () {
        final topLeft = _dragTopLeft;
        if (topLeft != null) {
          widget.onSnap(computeSnap(
            dropTopLeft: topLeft,
            cardSize: cardSize,
            windowSize: media,
          ));
        }
        setState(() => _dragTopLeft = null);
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
    required this.width,
    required this.maxHeight,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onCollapse,
    required this.messages,
    required this.myUsername,
    required this.onSend,
  });

  final double width;
  final double maxHeight;
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
