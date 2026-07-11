import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../core/chat/chat_store.dart' show appendedMessages;
import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/opacities.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/shadows.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';
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
  // While dragging, the card renders free-floating at this rect (top-left
  // relative to this overlay's own box, plus the live size — a grip resize
  // changes it mid-gesture). Captured from the card's real rect at drag start
  // so the first grab never teleports; also driven by [_snapCtrl] during the
  // post-release glide to a corner. Held in a ValueNotifier so per-pointer-move
  // updates flow through a ValueListenableBuilder that only repositions the
  // card — its contents keep their widget identity instead of rebuilding every
  // message bubble per frame. Null while docked.
  final ValueNotifier<Rect?> _floatRect = ValueNotifier<Rect?>(null);
  // Overlay size captured at drag start, used for snap math.
  Size? _overlaySize;
  final GlobalKey _cardKey = GlobalKey();

  // Active resize: rect captured at grip-drag start + accumulated grip delta +
  // which corner is being dragged.
  Size? _resizeStartSize;
  Offset? _resizeStartTopLeft;
  Offset _resizeDelta = Offset.zero;
  ChatCorner _resizeGrip = ChatCorner.bottomRight;

  // Post-release snap glide: tween the float rect from where it was dropped to
  // the resting corner, so docking eases in instead of teleporting.
  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Offset? _snapFrom;
  Offset? _snapTo;

  // Focus the message box when the card is opened (peek tab → card).
  final FocusNode _inputFocus = FocusNode();

  // The composer's draft, owned here (not in ChatInput) so a typed-but-unsent
  // message survives the input subtree being torn down — collapse swaps the card
  // for the peek tab, and a focus loss / window minimize can rebuild it (#59).
  final TextEditingController _draftController = TextEditingController();

  // Keeps the newest message visible: animates on a new message while open,
  // jumps to the bottom when the card reopens.
  final ScrollController _scrollController = ScrollController();

  // How close (in px) to the bottom still counts as "at the bottom" — within
  // this slack a new message auto-scrolls instead of bumping the unread badge.
  static const double _bottomSlack = 20;

  int _unreadCount = 0;
  int? _dividerIndex;
  Timer? _dividerTimer;

  void _setUnreadCount(int count, {int? firstUnreadIndex}) {
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
      // Pin the divider just before the first unread message. The list is
      // append-only until the store's retention cap kicks in; once trims start
      // shifting indices, didUpdateWidget slides this index along with them.
      _dividerIndex = firstUnreadIndex ?? (widget.messages.length - count);
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
    final appended = appendedMessages(old.messages, widget.messages);
    // Lines the store trimmed off the front this update (only happens once its
    // retention cap is hit). Slide the pinned divider with the content so it
    // stays above the same message instead of drifting to a stale index.
    final trimmed =
        old.messages.length + appended.length - widget.messages.length;
    if (trimmed > 0 && _dividerIndex != null) {
      final oldDivider = _dividerIndex!;
      final shifted = oldDivider - trimmed;
      if (shifted >= 0) {
        // The first unread line survived the trim — just slide the marker down.
        _dividerIndex = shifted;
      } else if (_unreadCount > 0) {
        // The oldest unread line(s) themselves aged out under the cap. Drop
        // the trimmed unread lines from the badge (otherwise it over-reports
        // messages that no longer exist) and re-pin the divider to the oldest
        // unread line still retained. Leaving _unreadCount untouched here also
        // wedges the divider: a later _setUnreadCount sees wasUnread == true,
        // so neither pin branch fires and the marker never comes back.
        var trimmedUnread = 0;
        final end = trimmed < old.messages.length
            ? trimmed
            : old.messages.length;
        for (var i = oldDivider; i < end; i++) {
          final m = old.messages[i];
          if (!m.system && !m.isMine) trimmedUnread++;
        }
        final remaining = _unreadCount - trimmedUnread;
        if (remaining > 0) {
          int? firstRetainedUnread;
          for (var i = 0; i < widget.messages.length; i++) {
            final m = widget.messages[i];
            if (!m.system && !m.isMine) {
              firstRetainedUnread = i;
              break;
            }
          }
          _unreadCount = remaining;
          _dividerIndex = firstRetainedUnread;
        } else {
          // Every counted unread line aged out — clear the marker and badge,
          // and tell the parent the unread flag dropped (peek pulse, etc.).
          _unreadCount = 0;
          _dividerIndex = null;
          _dividerTimer?.cancel();
          _dividerTimer = null;
          final cb = widget.onUnreadChanged;
          if (cb != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) cb(false);
            });
          }
        }
      } else {
        // No active unread run — a lingering (post-read) divider whose message
        // aged out; just drop it.
        _dividerIndex = null;
      }
    }

    // Reopening jumps straight to the latest (messages can pile up while
    // collapsed, when the list is unmounted and a scroll would no-op); a new
    // message while already open animates into view.
    if (justOpened) {
      if (_unreadCount > 0) setState(() => _setUnreadCount(0));
      _scrollToBottom(animate: false);
    } else if (appended.isNotEmpty) {
      final isMyMessage = appended.last.isMine;

      int newUnread = 0;
      int? firstUnreadIndex;
      final appendStart = widget.messages.length - appended.length;
      for (int i = 0; i < appended.length; i++) {
        final m = appended[i];
        if (!m.system && !m.isMine) {
          newUnread++;
          firstUnreadIndex ??= appendStart + i;
        }
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
          if (newUnread > 0) setState(() => _setUnreadCount(_unreadCount + newUnread, firstUnreadIndex: firstUnreadIndex));
        }
      } else {
        if (newUnread > 0) setState(() => _setUnreadCount(_unreadCount + newUnread, firstUnreadIndex: firstUnreadIndex));
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
          curve: Motion.standard,
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
    _floatRect.dispose();
    _inputFocus.dispose();
    _draftController.dispose();
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
    const pad = Spacing.md;
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
    final rect = _floatRect.value;
    if (from == null || to == null || rect == null) return;
    final at = Offset.lerp(
      from,
      to,
      Motion.standard.transform(_snapCtrl.value),
    )!;
    _floatRect.value = at & rect.size;
  }

  void _onSnapStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _clearDrag();
  }

  void _clearDrag() {
    setState(() {
      _floatRect.value = null;
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
        if (mounted && _floatRect.value == null) _inputFocus.requestFocus();
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
      _overlaySize = selfBox.size;
      _floatRect.value =
          (cardBox.localToGlobal(Offset.zero) - origin) & cardBox.size;
    });
    widget.onDraggingChanged?.call(true);
  }

  /// Live move-drag: shift the floating rect only — no setState, so the card's
  /// contents are not rebuilt per pointer move.
  void _moveBy(Offset delta) {
    final rect = _floatRect.value;
    if (rect == null) return;
    _floatRect.value = rect.shift(delta);
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
      _overlaySize = selfBox.size;
      _floatRect.value = topLeft & cardBox.size;
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
    // Notifier-only, like _moveBy: the card relayouts to its new size but its
    // contents keep their widget identity.
    _floatRect.value = r.topLeft & r.size;
  }

  /// End the resize: report the new size, then glide back to the docked corner.
  void _endResize() {
    final rect = _floatRect.value;
    final window = _overlaySize;
    _resizeStartSize = null;
    _resizeStartTopLeft = null;
    _resizeDelta = Offset.zero;
    if (rect == null || window == null) {
      _clearDrag();
      return;
    }
    widget.onResize?.call(rect.size);
    // setState: the glide is a mode change (hints hide, resize ends) that the
    // float-rect notifier alone can't signal — its first tick re-emits the
    // same rect, which a ValueNotifier swallows.
    setState(() {
      _snapFrom = rect.topLeft;
      _snapTo = _cornerTopLeft(widget.corner, rect.size, window);
    });
    _snapCtrl.forward(from: 0);
  }

  void _endHeaderDrag() {
    final rect = _floatRect.value;
    final window = _overlaySize;
    if (rect == null || window == null) {
      _clearDrag();
      return;
    }
    final result = computeSnap(
      dropTopLeft: rect.topLeft,
      cardSize: rect.size,
      windowSize: window,
    );
    widget.onSnap(result);
    final corner = result.corner;
    // setState: hints must hide the moment the drag releases, and the
    // float-rect notifier can't signal that — its first glide tick re-emits
    // the same rect, which a ValueNotifier swallows.
    setState(() {
      _snapFrom = rect.topLeft;
      if (corner != null) {
        // Glide to the docked corner, then settle into the Align placement.
        _snapTo = _cornerTopLeft(corner, rect.size, window);
      } else {
        // Collapse: slide the card off the right edge, then it becomes the
        // peek tab — so docking to the edge isn't an abrupt disappearance.
        _snapTo = Offset(window.width, rect.top);
      }
    });
    _snapCtrl.forward(from: 0);
  }

  Widget _buildCard() => _GlassCard(
    key: _cardKey,
    onHeaderDragStart: _startHeaderDrag,
    onHeaderDragUpdate: _moveBy,
    onHeaderDragEnd: _endHeaderDrag,
    onCollapse: widget.onToggleCollapsed,
    messages: widget.messages,
    unreadCount: _unreadCount,
    dividerIndex: _dividerIndex,
    onScrollToBottom: () {
      if (_unreadCount > 0) setState(() => _setUnreadCount(0));
      _scrollToBottom(animate: true);
    },
    onSend: widget.onSend,
    inputFocusNode: _inputFocus,
    draftController: _draftController,
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
    // Active drag, or the post-release snap glide, renders a free-floating
    // card. Pointer moves and glide ticks write [_floatRect] only — the
    // ValueListenableBuilder repositions/resizes the card while its contents
    // (the cached [child]) keep their widget identity, so no bubble rebuilds.
    if (_floatRect.value != null) {
      // Fill the overlay's box with a plain SizedBox.expand — NOT Positioned.fill.
      // ChatOverlay is mounted under IgnorePointer/AnimatedOpacity (see
      // HomeScreen), not directly inside a Stack, so a Positioned here is a
      // misused ParentDataWidget. In release that mis-annotation made the engine
      // composite the whole screen wrong → a translucent pale-white wash for the
      // entire drag (#50; debug tolerated it, release didn't). The inner Stack
      // (below) is the real Stack the card's Positioned belongs to.
      return SizedBox.expand(
        // Isolate the moving/resizing card in its own compositor layer so its
        // per-frame drag/resize repaints stay local instead of repainting the
        // whole screen.
        child: RepaintBoundary(
          child: ValueListenableBuilder<Rect?>(
            valueListenable: _floatRect,
            builder: (context, rect, card) {
              if (rect == null) return const SizedBox.shrink();
              // Dock hints show only during the live move-drag: not the
              // settling glide (isAnimating), and not during a grip resize
              // (_resizeStartSize) — the resize reuses this free-floating
              // render path, where the full-screen hint layer just adds noise
              // (it's a move affordance, not a resize one).
              final showHints =
                  !_snapCtrl.isAnimating &&
                  _resizeStartSize == null &&
                  _overlaySize != null;
              return Stack(
                children: [
                  if (showHints)
                    _DropZoneHints(
                      overlaySize: _overlaySize!,
                      cardSize: rect.size,
                      dragTopLeft: rect.topLeft,
                    ),
                  Positioned(
                    left: rect.left,
                    top: rect.top,
                    child: SizedBox(
                      width: rect.width,
                      height: rect.height,
                      child: card,
                    ),
                  ),
                ],
              );
            },
            child: _buildCard(),
          ),
        ),
      );
    }

    final media = MediaQuery.of(context).size;
    // Stored px size, clamped to the current viewport (so it never overflows a
    // small window) but otherwise stable when the window is resized/maximized.
    final cardSize = clampCardSize(
      Size(
        widget.widthPx ?? kDefaultCardWidth,
        widget.heightPx ?? kDefaultCardHeight,
      ),
      media,
    );

    // Resting: cross-fade between the peek tab and the docked card so
    // collapse/expand eases instead of snapping instantly.
    final Widget resting = widget.collapsed
        ? Align(
            key: const ValueKey<String>('peek'),
            alignment: Alignment.centerRight,
            child: PeekTab(
              pulsing: widget.pulsing,
              typing: widget.typingLabel != null,
              unreadCount: _unreadCount,
              onTap: widget.onToggleCollapsed,
            ),
          )
        : Align(
            key: const ValueKey<String>('card'),
            alignment: _alignmentFor(widget.corner),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.md, Spacing.md, 64),
              child: SizedBox(
                width: cardSize.width,
                height: cardSize.height,
                child: _buildCard(),
              ),
            ),
          );
    // Same isolation as the drag path: the docked card's own repaints (new
    // message, typing strip, scroll, collapse cross-fade) stay in their own
    // layer instead of repainting the player behind it.
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: resting,
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    super.key,
    required this.onHeaderDragStart,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onCollapse,
    required this.messages,
    required this.unreadCount,
    required this.dividerIndex,
    required this.onScrollToBottom,
    required this.onSend,
    required this.inputFocusNode,
    required this.draftController,
    required this.scrollController,
    required this.typingLabel,
    required this.onTypingChanged,
    required this.onResetSize,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final VoidCallback onHeaderDragStart;
  final void Function(Offset delta) onHeaderDragUpdate;
  final VoidCallback onHeaderDragEnd;
  final VoidCallback onCollapse;
  final List<ChatMessage> messages;
  final int unreadCount;
  final int? dividerIndex;
  final VoidCallback onScrollToBottom;
  final void Function(String text) onSend;
  final FocusNode inputFocusNode;
  final TextEditingController draftController;
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
      borderRadius: BorderRadius.circular(Radii.lg),
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
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: Shadows.overlay(m.scrim),
          ),
          child: _frosted(
            context,
            Container(
              // Fills the SizedBox the caller wraps the card in — the size
              // lives outside so a live resize relayouts without a rebuild.
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: m.surface,
                borderRadius: BorderRadius.circular(Radii.lg),
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
                      // Asymmetric left inset: the 22px top-left resize grip
                      // (see _grip) overlays this header's top-left corner.
                      // left:24 pushes the drag-to-move icon clear of that grip
                      // so its hint and hit-center land on the move gesture,
                      // not the resize Listener.
                      padding:
                          const EdgeInsets.only(left: Spacing.xxl, right: Spacing.md),
                      child: Row(
                        children: [
                          Tooltip(
                            message: 'Drag to move',
                            waitDuration: _kTooltipWait,
                            child: Icon(
                              Icons.drag_indicator,
                              size: IconSizes.sm,
                              color: m.textDim,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Chat',
                            style: context.meowText.body,
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
                                  horizontal: Spacing.sm,
                                  vertical: Spacing.sm,
                                ),
                                child: Icon(
                                  Icons.crop_free,
                                  size: IconSizes.sm,
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
                                  horizontal: Spacing.md,
                                  vertical: Spacing.sm,
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: IconSizes.md,
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
                                horizontal: Spacing.lg,
                                vertical: Spacing.xxl,
                              ),
                              child: Text(
                                'No messages yet — say hi 🐾',
                                textAlign: TextAlign.center,
                                style: context.meowText.body.copyWith(
                                  color: m.textDim,
                                ),
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              // Wrap the message list in a SelectionArea so the
                              // user can drag-select and copy message text —
                              // links, timestamps, quotes (#54). The plain Text
                              // bubbles become selectable without changing how
                              // they render.
                              SelectionArea(
                                // A builder list only constructs the bubbles
                                // that scroll into view — a children:[...] list
                                // rebuilt every message widget on every card
                                // rebuild, which grew with session length.
                                child: ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: Spacing.xs,
                                  ),
                                  itemCount: messages.length,
                                  itemBuilder: (context, i) {
                                    final bubble =
                                        ChatBubble(message: messages[i]);
                                    if (i != dividerIndex) return bubble;
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const _NewMessagesDivider(),
                                        bubble,
                                      ],
                                    );
                                  },
                                ),
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  bottom: Spacing.sm,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: onScrollToBottom,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: Spacing.md,
                                          vertical: Spacing.sm,
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
                                            fontSize: TypeScale.caption,
                                            fontWeight: TypeScale.bold,
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
                    controller: draftController,
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

/// The "New Messages" boundary line, rendered just above the first unread
/// message while the unread marker is pinned.
class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final line = Divider(
      color: m.accent.withValues(alpha: Opacities.scrim),
      thickness: 1,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Spacing.sm,
        horizontal: Spacing.lg,
      ),
      child: Row(
        children: [
          Expanded(child: line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            child: Text(
              'New Messages',
              style: context.meowText.caption.copyWith(
                color: m.accent,
                fontWeight: TypeScale.bold,
              ),
            ),
          ),
          Expanded(child: line),
        ],
      ),
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
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, 0, Spacing.lg, Spacing.xxs),
            child: Text(
              _shown,
              style: context.meowText.body.copyWith(
                color: m.textDim,
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
      duration: Motion.fast,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? m.accent.withValues(alpha: 0.30)
            : m.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(Radii.lg),
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
