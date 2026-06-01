import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';
import 'chat_bubble.dart';
import 'chat_corner.dart';
import 'chat_input.dart';
import 'peek_tab.dart';
import 'resize_math.dart';

/// Hover delay before any chat-card tooltip appears. A short beat so tooltips
/// don't pop instantly on every passing hover (felt twitchy at 0ms).
const Duration _kTooltipWait = Duration(milliseconds: 700);

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
    this.onResize,
    this.onResetSize,
    this.widthPx,
    this.heightPx,
    this.isUiIdle = false,
    this.corner = ChatCorner.bottomLeft,
    this.pulsing = false,
    this.typingLabel,
    this.onTypingChanged,
    this.onDraggingChanged,
    this.onUnreadChanged,
  });

  final List<ChatMessage> messages;
  final String myUsername;
  final bool collapsed;
  final bool isUiIdle;
  final ChatCorner corner;
  final bool pulsing;
  final void Function(String text) onSend;
  final VoidCallback onToggleCollapsed;
  final void Function(SnapResult result) onSnap;

  /// Reports the card's new px size when a resize grip drag ends.
  final void Function(Size newSize)? onResize;

  /// Resets the card to its default size.
  final VoidCallback? onResetSize;

  /// Card size in logical px; null falls back to the default. The view clamps
  /// it to the viewport, so it never overflows even on a small window.
  final double? widthPx;
  final double? heightPx;

  /// e.g. "lin is typing…"; null when nobody is typing.
  final String? typingLabel;
  final ValueChanged<bool>? onTypingChanged;

  /// Fires true while the card is being dragged (or gliding to its dock), false
  /// once it settles — lets the parent hide controls (e.g. the gear) that would
  /// otherwise sit under the dock hints.
  final ValueChanged<bool>? onDraggingChanged;

  /// Called when the chat transitions between having unread messages and having none.
  final ValueChanged<bool>? onUnreadChanged;

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

  // Active resize: rect captured at grip-drag start + accumulated grip delta +
  // which corner is being dragged.
  Size? _resizeStartSize;
  Offset? _resizeStartTopLeft;
  Offset _resizeDelta = Offset.zero;
  ChatCorner _resizeGrip = ChatCorner.bottomRight;

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

  // Keeps the newest message visible: animates on a new message while open,
  // jumps to the bottom when the card reopens.
  final ScrollController _scrollController = ScrollController();

  // How close (in px) to the bottom still counts as "at the bottom" — within
  // this slack a new message auto-scrolls instead of bumping the unread badge.
  static const double _bottomSlack = 20;

  int _unreadCount = 0;
  int? _dividerIndex;
  Timer? _dividerTimer;

  void _setUnreadCount(int count) {
    if (_unreadCount == count) return;
    final wasUnread = _unreadCount > 0;
    _unreadCount = count;
    final isUnread = _unreadCount > 0;

    if (wasUnread && !isUnread) {
      _dividerTimer?.cancel();
      _dividerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _dividerIndex = null);
      });
    } else if (!wasUnread && isUnread) {
      // Pin the divider just before the first unread message. Safe as an
      // absolute index only because the message list is append-only — existing
      // indices never shift, so the boundary stays put as more arrive.
      _dividerIndex = widget.messages.length - count;
      _dividerTimer?.cancel();
      _dividerTimer = null;
    }

    if (wasUnread != isUnread) {
      // Defer past the current frame: _setUnreadCount runs inside
      // didUpdateWidget (the parent's build phase), and onUnreadChanged drives
      // a parent setState — calling it synchronously throws "setState() called
      // during build". The post-frame hop also coalesces if the flag flips back
      // before the frame ends.
      final cb = widget.onUnreadChanged;
      if (cb != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) cb(_unreadCount > 0);
        });
      }
    }
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_unreadCount > 0 && !widget.isUiIdle) {
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - _bottomSlack) {
        setState(() => _setUnreadCount(0));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _inputFocus.addListener(_onInputFocusChanged);
    _snapCtrl
      ..addListener(_onSnapTick)
      ..addStatusListener(_onSnapStatus);
  }

  void _onInputFocusChanged() {
    // Only clear on focus when the divider isn't already on its post-read
    // linger timer. Opening the overlay auto-focuses the input (see
    // didUpdateWidget); without this guard that programmatic focus would wipe
    // the "New Messages" divider the instant the user reopens to catch up —
    // exactly when they want to see it. A manual focus while messages are still
    // unread (no timer scheduled) still clears it.
    if (_inputFocus.hasFocus && _dividerIndex != null && _dividerTimer == null) {
      setState(() => _dividerIndex = null);
    }
  }

  @override
  void didUpdateWidget(ChatOverlay old) {
    super.didUpdateWidget(old);
    final justOpened = old.collapsed && !widget.collapsed;
    if (justOpened) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
    // Reopening jumps straight to the latest (messages can pile up while
    // collapsed, when the list is unmounted and a scroll would no-op); a new
    // message while already open animates into view.
    if (justOpened) {
      if (_unreadCount > 0) setState(() => _setUnreadCount(0));
      _scrollToBottom(animate: false);
    } else if (old.messages.length < widget.messages.length) {
      final newMsgs = widget.messages.sublist(old.messages.length);
      final isMyMessage = newMsgs.isNotEmpty && newMsgs.last.username == widget.myUsername;

      int newUnread = 0;
      for (final m in newMsgs) {
        if (!m.system && m.username != widget.myUsername) newUnread++;
      }

      bool isAtBottom = false;
      if (!widget.collapsed && _scrollController.hasClients) {
        final pos = _scrollController.position;
        isAtBottom = pos.pixels >= pos.maxScrollExtent - _bottomSlack;
      }

      if (isMyMessage || (isAtBottom && !widget.collapsed)) {
        if (!widget.collapsed) _scrollToBottom(animate: true);
        
        if (!widget.isUiIdle || isMyMessage) {
          if (_unreadCount != 0) setState(() => _setUnreadCount(0));
        } else {
          if (newUnread > 0) setState(() => _setUnreadCount(_unreadCount + newUnread));
        }
      } else {
        if (newUnread > 0) setState(() => _setUnreadCount(_unreadCount + newUnread));
      }
    }

    if (old.isUiIdle && !widget.isUiIdle) {
      if (_unreadCount > 0 && !widget.collapsed && _scrollController.hasClients) {
        final pos = _scrollController.position;
        if (pos.pixels >= pos.maxScrollExtent - _bottomSlack) {
          setState(() => _setUnreadCount(0));
        }
      }
    }
  }

  // Scroll the message list to the newest message. A live new-message scroll
  // (animate) runs once — the list is already laid out, so maxScrollExtent is
  // known on the next frame. A reopen jump re-pins across frames; see
  // [_jumpToBottom].
  void _scrollToBottom({required bool animate}) {
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      });
      return;
    }
    _jumpToBottom(8, null);
  }

  // Reopen pins the list hard to the bottom. The list is freshly mounted inside
  // the AnimatedSwitcher, so the first post-frame often reports
  // hasClients=false, or maxScrollExtent=0 because the bubbles haven't laid out
  // yet — a one-shot jump then lands at the top (the bug in #17). So we re-pin
  // across several frames: each pass jumps to the *current* extent and the
  // final pass lands correctly once layout settles. We stop early once the
  // extent stops changing (settled) or the frame budget runs out.
  void _jumpToBottom(int remaining, double? lastExtent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        if (remaining > 0) _jumpToBottom(remaining - 1, lastExtent);
        return;
      }
      final extent = _scrollController.position.maxScrollExtent;
      if (_scrollController.offset != extent) _scrollController.jumpTo(extent);
      if (extent != lastExtent && remaining > 0) {
        _jumpToBottom(remaining - 1, extent);
      }
    });
  }

  @override
  void dispose() {
    _dividerTimer?.cancel();
    _inputFocus.removeListener(_onInputFocusChanged);
    _snapCtrl.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
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
    setState(
      () => _dragTopLeft = Offset.lerp(
        from,
        to,
        Curves.easeOutCubic.transform(_snapCtrl.value),
      ),
    );
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
    // A corner-dock leaves the card open but un-focused, so the next Tab was
    // wasted re-acquiring focus ("press twice"). Hand focus back to the input
    // so Tab toggles on one press (and the user can type straight away). On a
    // collapse the parent restores player focus instead, so skip it here.
    if (!widget.collapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dragTopLeft == null) _inputFocus.requestFocus();
      });
    }
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

  /// Begin a grip resize from corner [grip]: pin the card's current rect and
  /// remember which corner is being dragged.
  void _startResize(ChatCorner grip) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    final cardBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (cardBox == null || selfBox == null) return;
    final origin = selfBox.localToGlobal(Offset.zero);
    final topLeft = cardBox.localToGlobal(Offset.zero) - origin;
    setState(() {
      _dragTopLeft = topLeft;
      _dragCardSize = cardBox.size;
      _overlaySize = selfBox.size;
      _resizeStartSize = cardBox.size;
      _resizeStartTopLeft = topLeft;
      _resizeDelta = Offset.zero;
      _resizeGrip = grip;
    });
    widget.onDraggingChanged?.call(true);
  }

  void _updateResize(Offset delta) {
    final start = _resizeStartSize;
    final startTL = _resizeStartTopLeft;
    final window = _overlaySize;
    if (start == null || startTL == null || window == null) return;
    _resizeDelta += delta;
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: start,
      dragDelta: _resizeDelta,
      grip: _resizeGrip,
      windowSize: window,
    );
    setState(() {
      _dragTopLeft = r.topLeft;
      _dragCardSize = r.size;
    });
  }

  /// End the resize: report the new size, then glide back to the docked corner.
  void _endResize() {
    final size = _dragCardSize;
    final topLeft = _dragTopLeft;
    final window = _overlaySize;
    _resizeStartSize = null;
    _resizeStartTopLeft = null;
    _resizeDelta = Offset.zero;
    if (size == null || topLeft == null || window == null) {
      _clearDrag();
      return;
    }
    widget.onResize?.call(size);
    _snapFrom = topLeft;
    _snapTo = _cornerTopLeft(widget.corner, size, window);
    _snapCtrl.forward(from: 0);
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
    height: cardSize.height,
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
    unreadCount: _unreadCount,
    dividerIndex: _dividerIndex,
    onScrollToBottom: () {
      if (_unreadCount > 0) setState(() => _setUnreadCount(0));
      _scrollToBottom(animate: true);
    },
    onSend: widget.onSend,
    inputFocusNode: _inputFocus,
    scrollController: _scrollController,
    typingLabel: widget.typingLabel,
    onTypingChanged: widget.onTypingChanged,
    onResetSize: widget.onResetSize ?? () {},
    onResizeStart: _startResize,
    onResizeUpdate: _updateResize,
    onResizeEnd: _endResize,
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    // Stored px size, clamped to the current viewport (so it never overflows a
    // small window) but otherwise stable when the window is resized/maximized.
    final cardSize =
        _dragCardSize ??
        clampCardSize(
          Size(
            widget.widthPx ?? kDefaultCardWidth,
            widget.heightPx ?? kDefaultCardHeight,
          ),
          media,
        );

    // Active drag, or the post-release snap glide, renders a free-floating card.
    final topLeft = _dragTopLeft;
    if (topLeft != null) {
      // Dock hints show only during the live move-drag: not the settling glide
      // (isAnimating), and not during a grip resize (_resizeStartSize) — the
      // resize reuses this free-floating render path, and the hint layer over a
      // resizing card flashed a white screen (issue #42).
      final showHints =
          !_snapCtrl.isAnimating &&
          _resizeStartSize == null &&
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
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              child: _buildCard(cardSize),
            ),
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
            child: PeekTab(
              pulsing: widget.pulsing,
              unreadCount: _unreadCount,
              onTap: widget.onToggleCollapsed,
            ),
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
    required this.height,
    required this.onHeaderDragStart,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onCollapse,
    required this.messages,
    required this.myUsername,
    required this.unreadCount,
    required this.dividerIndex,
    required this.onScrollToBottom,
    required this.onSend,
    required this.inputFocusNode,
    required this.scrollController,
    required this.typingLabel,
    required this.onTypingChanged,
    required this.onResetSize,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final double width;
  final double height;
  final VoidCallback onHeaderDragStart;
  final void Function(Offset delta) onHeaderDragUpdate;
  final VoidCallback onHeaderDragEnd;
  final VoidCallback onCollapse;
  final List<ChatMessage> messages;
  final String myUsername;
  final int unreadCount;
  final int? dividerIndex;
  final VoidCallback onScrollToBottom;
  final void Function(String text) onSend;
  final FocusNode inputFocusNode;
  final ScrollController scrollController;
  final String? typingLabel;
  final ValueChanged<bool>? onTypingChanged;
  final VoidCallback onResetSize;
  final void Function(ChatCorner corner) onResizeStart;
  final void Function(Offset delta) onResizeUpdate;
  final VoidCallback onResizeEnd;

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

  /// An invisible corner resize grip. No icon — hovering shows the diagonal
  /// resize cursor instead, which reads cleaner than four icons in the corners.
  /// Reports its own [corner] on drag start so the controller can pin the
  /// opposite corner.
  ///
  /// Uses a raw [Listener] rather than a pan [GestureDetector]: the bottom grips
  /// sit over the chat input, and a focused `TextField` would otherwise win the
  /// gesture arena and steal the drag (selecting text instead of resizing).
  /// Listener pointer events bypass the arena, so the grip always resizes.
  Widget _grip(BuildContext context, ChatCorner corner) {
    return Listener(
      key: ValueKey('chat-resize-grip-${corner.name}'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onResizeStart(corner),
      onPointerMove: (e) => onResizeUpdate(e.delta),
      onPointerUp: (_) => onResizeEnd(),
      onPointerCancel: (_) => onResizeEnd(),
      child: MouseRegion(
        cursor: _cursorFor(corner),
        child: const Tooltip(
          message: 'Drag to resize',
          waitDuration: _kTooltipWait,
          child: SizedBox(width: 22, height: 22),
        ),
      ),
    );
  }

  /// Diagonal resize cursor matching the dragged corner: a "\" cursor for the
  /// top-left/bottom-right pair, a "/" cursor for the top-right/bottom-left pair.
  MouseCursor _cursorFor(ChatCorner corner) {
    switch (corner) {
      case ChatCorner.topLeft:
      case ChatCorner.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case ChatCorner.topRight:
      case ChatCorner.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
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
              height: height,
              decoration: BoxDecoration(
                color: m.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: m.accent.withValues(alpha: 0.80),
                  width: 1.5,
                ),
              ),
              child: Column(
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
                          Tooltip(
                            message: 'Drag to move',
                            waitDuration: _kTooltipWait,
                            child: Icon(
                              Icons.drag_indicator,
                              size: 16,
                              color: m.textDim,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Chat',
                            style: TextStyle(
                              color: m.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            key: const ValueKey('chat-reset-size'),
                            behavior: HitTestBehavior.opaque,
                            onTap: onResetSize,
                            child: Tooltip(
                              message: 'Reset size',
                              waitDuration: _kTooltipWait,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Icon(
                                  Icons.crop_free,
                                  size: 16,
                                  color: m.textDim,
                                ),
                              ),
                            ),
                          ),
                          // Opaque, padded hit target — an 18px icon alone is too
                          // small to reliably tap (it read as "had to click twice").
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onCollapse,
                            child: Tooltip(
                              message: 'Hide chat',
                              waitDuration: _kTooltipWait,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: m.accent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 24,
                              ),
                              child: Text(
                                'No messages yet — say hi 🐾',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: m.textDim,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              ListView(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                children: [
                                  for (int i = 0; i < messages.length; i++) ...[
                                    if (i == dividerIndex)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                        child: Row(
                                          children: [
                                            Expanded(child: Divider(color: m.accent.withValues(alpha: 0.5), thickness: 1)),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                'New Messages',
                                                style: TextStyle(
                                                  color: m.accent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Expanded(child: Divider(color: m.accent.withValues(alpha: 0.5), thickness: 1)),
                                          ],
                                        ),
                                      ),
                                    ChatBubble(
                                      message: messages[i],
                                      myUsername: myUsername,
                                    ),
                                  ],
                                ],
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  bottom: 8,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: onScrollToBottom,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: m.accent,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: m.scrim.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          '↓ $unreadCount new message${unreadCount > 1 ? 's' : ''}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  _TypingStrip(label: typingLabel),
                  ChatInput(
                    onSend: onSend,
                    focusNode: inputFocusNode,
                    onTypingChanged: onTypingChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(left: 0, top: 0, child: _grip(context, ChatCorner.topLeft)),
        Positioned(
          right: 0,
          top: 0,
          child: _grip(context, ChatCorner.topRight),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: _grip(context, ChatCorner.bottomLeft),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: _grip(context, ChatCorner.bottomRight),
        ),
      ],
    );
  }
}

/// Fixed-height slot for the "… is typing" line. Always occupies the same
/// vertical space whether or not anyone is typing, so toggling the indicator
/// never resizes the message list above it. Previously the line was inserted/
/// removed from the Column, which shrank the list and jolted the newest bubble
/// out of view (the #20 jitter). The label fades in/out, and the last text is
/// held during fade-out so the words dissolve instead of vanishing instantly.
class _TypingStrip extends StatefulWidget {
  const _TypingStrip({required this.label});

  final String? label;

  @override
  State<_TypingStrip> createState() => _TypingStripState();
}

class _TypingStripState extends State<_TypingStrip> {
  // Held so fade-out animates the actual words rather than blanking instantly.
  String _shown = '';

  @override
  void initState() {
    super.initState();
    _shown = widget.label ?? '';
  }

  @override
  void didUpdateWidget(_TypingStrip old) {
    super.didUpdateWidget(old);
    final label = widget.label;
    if (label != null && label != _shown) setState(() => _shown = label);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return SizedBox(
      height: 20,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedOpacity(
          opacity: widget.label == null ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Text(
              _shown,
              style: TextStyle(
                color: m.textDim,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
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

    Widget zone(
      double l,
      double t,
      double r,
      double b,
      IconData icon,
      bool active,
    ) => Positioned(
      left: l,
      top: t,
      width: (r - l).clamp(0, w),
      height: (b - t).clamp(0, h),
      child: _HintZone(icon: icon, active: active),
    );

    return Positioned.fill(
      child: IgnorePointer(
        // Ease the whole hint layer in (fade + slight scale) so it doesn't
        // pop in abruptly on grab.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
          ),
          child: Stack(
            children: [
              zone(
                left,
                top,
                midX - gap / 2,
                midY - gap / 2,
                Icons.north_west,
                corner == ChatCorner.topLeft,
              ),
              zone(
                midX + gap / 2,
                top,
                right,
                midY - gap / 2,
                Icons.north_east,
                corner == ChatCorner.topRight,
              ),
              zone(
                left,
                midY + gap / 2,
                midX - gap / 2,
                bottom,
                Icons.south_west,
                corner == ChatCorner.bottomLeft,
              ),
              zone(
                midX + gap / 2,
                midY + gap / 2,
                right,
                bottom,
                Icons.south_east,
                corner == ChatCorner.bottomRight,
              ),
              // Slim, tall collapse bar hugging the right edge.
              zone(
                w - barW,
                top,
                w - 8,
                bottom,
                Icons.chevron_right,
                snap.collapsed,
              ),
            ],
          ),
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
