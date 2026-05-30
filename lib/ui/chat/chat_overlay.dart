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
    this.onDraggingChanged,
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

  /// Fires true while the card is being dragged (or gliding to its dock), false
  /// once it settles — lets the parent hide controls (e.g. the gear) that would
  /// otherwise sit under the dock hints.
  final ValueChanged<bool>? onDraggingChanged;

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay>
    with SingleTickerProviderStateMixin {
  // While dragging, a free top-left offset (relative to this overlay's own
  // box) overrides corner placement. Captured from the card's real rect at
  // drag start so the first grab never teleports. Also driven by [_snapCtrl]
  // during the post-release glide to a corner.
  Offset? _dragTopLeft;
  // Real card + overlay sizes captured at drag start, used for snap math.
  Size? _dragCardSize;
  Size? _overlaySize;
  final GlobalKey _cardKey = GlobalKey();

  // Post-release snap glide: tween _dragTopLeft from where it was dropped to
  // the resting corner, so docking eases in instead of teleporting.
  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Offset? _snapFrom;
  Offset? _snapTo;

  // Focus the message box when the card is opened (peek tab → card).
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _snapCtrl
      ..addListener(_onSnapTick)
      ..addStatusListener(_onSnapStatus);
  }

  @override
  void didUpdateWidget(ChatOverlay old) {
    super.didUpdateWidget(old);
    if (old.collapsed && !widget.collapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

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

  /// Resting top-left for [c], matching the Align + padding used below so the
  /// glide ends exactly where the docked card will sit (no settle-jump).
  Offset _cornerTopLeft(ChatCorner c, Size card, Size win) {
    const pad = 12.0;
    const bottomPad = 64.0;
    final left = pad;
    final right = win.width - pad - card.width;
    final top = pad;
    final bottom = win.height - bottomPad - card.height;
    switch (c) {
      case ChatCorner.topLeft:
        return Offset(left, top);
      case ChatCorner.topRight:
        return Offset(right, top);
      case ChatCorner.bottomLeft:
        return Offset(left, bottom);
      case ChatCorner.bottomRight:
        return Offset(right, bottom);
    }
  }

  void _onSnapTick() {
    final from = _snapFrom;
    final to = _snapTo;
    if (from == null || to == null) return;
    setState(() => _dragTopLeft =
        Offset.lerp(from, to, Curves.easeOutCubic.transform(_snapCtrl.value)));
  }

  void _onSnapStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _clearDrag();
  }

  void _clearDrag() {
    setState(() {
      _dragTopLeft = null;
      _dragCardSize = null;
      _overlaySize = null;
      _snapFrom = null;
      _snapTo = null;
    });
    widget.onDraggingChanged?.call(false);
  }

  /// Seed the free-drag offset from where the card actually sits right now.
  /// Converts the card's global top-left into this overlay's local space so
  /// the following [Positioned] keeps it under the cursor (no jump).
  void _startHeaderDrag() {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    final cardBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (cardBox == null || selfBox == null) return;
    final origin = selfBox.localToGlobal(Offset.zero);
    setState(() {
      _dragTopLeft = cardBox.localToGlobal(Offset.zero) - origin;
      _dragCardSize = cardBox.size;
      _overlaySize = selfBox.size;
    });
    widget.onDraggingChanged?.call(true);
  }

  void _endHeaderDrag() {
    final topLeft = _dragTopLeft;
    final card = _dragCardSize;
    final window = _overlaySize;
    if (topLeft == null || card == null || window == null) {
      _clearDrag();
      return;
    }
    final result = computeSnap(
      dropTopLeft: topLeft,
      cardSize: card,
      windowSize: window,
    );
    widget.onSnap(result);
    final corner = result.corner;
    _snapFrom = topLeft;
    if (corner != null) {
      // Glide to the docked corner, then settle into the Align placement.
      _snapTo = _cornerTopLeft(corner, card, window);
    } else {
      // Collapse: slide the card off the right edge, then it becomes the peek
      // tab — so docking to the edge isn't an abrupt disappearance.
      _snapTo = Offset(window.width, topLeft.dy);
    }
    _snapCtrl.forward(from: 0);
  }

  Widget _buildCard(Size cardSize) => _GlassCard(
        key: _cardKey,
        width: cardSize.width,
        maxHeight: cardSize.height,
        onHeaderDragStart: _startHeaderDrag,
        onHeaderDragUpdate: (delta) {
          final base = _dragTopLeft;
          if (base == null) return;
          setState(() => _dragTopLeft = base + delta);
        },
        onHeaderDragEnd: _endHeaderDrag,
        onCollapse: widget.onToggleCollapsed,
        messages: widget.messages,
        myUsername: widget.myUsername,
        onSend: widget.onSend,
        inputFocusNode: _inputFocus,
        typingLabel: widget.typingLabel,
        onTypingChanged: widget.onTypingChanged,
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final cardSize = Size(media.width * 0.3, media.height * 0.5);

    // Active drag, or the post-release snap glide, renders a free-floating card.
    final topLeft = _dragTopLeft;
    if (topLeft != null) {
      // Dock hints show only during the live drag, not the settling glide.
      final showHints = !_snapCtrl.isAnimating &&
          _overlaySize != null &&
          _dragCardSize != null;
      return Positioned.fill(
        child: Stack(
          children: [
            if (showHints)
              _DropZoneHints(
                overlaySize: _overlaySize!,
                cardSize: _dragCardSize!,
                dragTopLeft: topLeft,
              ),
            Positioned(left: topLeft.dx, top: topLeft.dy, child: _buildCard(cardSize)),
          ],
        ),
      );
    }

    // Resting: cross-fade between the peek tab and the docked card so
    // collapse/expand eases instead of snapping instantly.
    final Widget resting = widget.collapsed
        ? Align(
            key: const ValueKey<String>('peek'),
            alignment: Alignment.centerRight,
            child:
                PeekTab(pulsing: widget.pulsing, onTap: widget.onToggleCollapsed),
          )
        : Align(
            key: const ValueKey<String>('card'),
            alignment: _alignmentFor(widget.corner),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
              child: _buildCard(cardSize),
            ),
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: resting,
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
    required this.inputFocusNode,
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
  final FocusNode inputFocusNode;
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
              ChatInput(
                onSend: onSend,
                focusNode: inputFocusNode,
                onTypingChanged: onTypingChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The five landing targets shown while the chat card is being dragged: four
/// big quadrant areas (one per corner) plus a slim, tall bar on the right edge
/// for the collapse dock. Whichever zone the current drop would snap to (per
/// [computeSnap]) is highlighted, so the outcome is clear before release.
class _DropZoneHints extends StatelessWidget {
  const _DropZoneHints({
    required this.overlaySize,
    required this.cardSize,
    required this.dragTopLeft,
  });

  final Size overlaySize;
  final Size cardSize;
  final Offset dragTopLeft;

  @override
  Widget build(BuildContext context) {
    final snap = computeSnap(
      dropTopLeft: dragTopLeft,
      cardSize: cardSize,
      windowSize: overlaySize,
    );
    final corner = snap.corner;
    final w = overlaySize.width;
    final h = overlaySize.height;

    const margin = 16.0;
    const gap = 14.0;
    const barW = 52.0; // slim right-edge collapse bar
    const bottomClear = 72.0; // keep clear of the auto-hiding control bar

    final top = margin;
    final bottom = h - bottomClear;
    final left = margin;
    final right = w - barW - gap; // quadrants stop before the collapse bar
    final midX = (left + right) / 2;
    final midY = (top + bottom) / 2;

    Widget zone(double l, double t, double r, double b, IconData icon,
            bool active) =>
        Positioned(
          left: l,
          top: t,
          width: (r - l).clamp(0, w),
          height: (b - t).clamp(0, h),
          child: _HintZone(icon: icon, active: active),
        );

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            zone(left, top, midX - gap / 2, midY - gap / 2, Icons.north_west,
                corner == ChatCorner.topLeft),
            zone(midX + gap / 2, top, right, midY - gap / 2, Icons.north_east,
                corner == ChatCorner.topRight),
            zone(left, midY + gap / 2, midX - gap / 2, bottom, Icons.south_west,
                corner == ChatCorner.bottomLeft),
            zone(midX + gap / 2, midY + gap / 2, right, bottom,
                Icons.south_east, corner == ChatCorner.bottomRight),
            // Slim, tall collapse bar hugging the right edge.
            zone(w - barW, top, w - 8, bottom, Icons.chevron_right,
                snap.collapsed),
          ],
        ),
      ),
    );
  }
}

/// One dock target region. A soft translucent panel that fills with the accent
/// when it is the active drop target.
class _HintZone extends StatelessWidget {
  const _HintZone({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? m.accent.withValues(alpha: 0.30)
            : m.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: m.accent.withValues(alpha: active ? 1.0 : 0.40),
          width: active ? 2.5 : 1,
        ),
      ),
      child: Icon(
        icon,
        size: active ? 40 : 30,
        color: m.accent.withValues(alpha: active ? 1.0 : 0.65),
      ),
    );
  }
}
