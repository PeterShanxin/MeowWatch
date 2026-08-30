part of 'home_screen.dart';

/// The chat seam of [_HomeScreenState] (#182): message/reaction/typing stream
/// wiring, notification chimes, the collapsed tab's peek pulse, card layout
/// toggling, and the load-screen Tab hint.
mixin _HomeChatState on _HomeScreenStateBase, _HomeIdleState {
  // Notification chime: bundled assets (portable, no dependency on a
  // system-specific sound file), throttled so a burst of messages doesn't
  // stack overlapping playbacks. Which preset plays is chosen in Settings and
  // resolved via [resolvePrimary]/[resolveSecondary].
  static const Duration _notifyThrottle = Duration(seconds: 2);
  final Stopwatch _notifyClock = Stopwatch();

  late ChatOverlayLayout _chatLayout;
  bool _chatDragging = false;

  // Hot chat-card state: every incoming chat line, typing signal, and peek
  // pulse used to force a setState that rebuilt the entire room Stack (#196).
  // As notifiers they dirty only ChatOverlayRegion's subtree instead.
  final ValueNotifier<List<ChatMessage>> _messages =
      ValueNotifier<List<ChatMessage>>(const <ChatMessage>[]);
  final ValueNotifier<String?> _typingLabel = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _peekPulsing = ValueNotifier<bool>(false);
  Timer? _peekTimer;

  /// Non-null while the load-screen "Press Tab" hint toast is on screen; its
  /// value re-keys [_FadingToast] so each show replays the fade animation.
  int? _chatHintToken;

  StreamSubscription<List<ChatMessage>>? _chatSub;
  StreamSubscription<ReactionEvent>? _reactionSub;
  StreamSubscription<TypingEvent>? _typingSub;

  /// Feeds the floating-reactions overlay. Both our own and peers' reactions
  /// flow through here (via the chat echo) so everyone sees the same burst.
  final StreamController<String> _reactionFeed =
      StreamController<String>.broadcast();

  /// Peers currently typing, each with a watchdog timer that clears them if a
  /// "stopped" signal is lost.
  final Set<String> _typingUsers = <String>{};
  final Map<String, Timer> _typingTimers = <String, Timer>{};

  bool _chatAutoDim = true;
  final ValueNotifier<bool> _chatHasUnread = ValueNotifier<bool>(false);
  bool _chatWakeOnMessage = false;
  double _chatIdleDim = kChatIdleGhostOpacity;

  /// Wires the chat store's message, reaction, and typing streams. Called once
  /// from initState; the handler bodies are unchanged from the pre-split
  /// screen (#182).
  void _initChatSubscriptions() {
    final chat = _chat;
    if (chat == null) return;
    _chatSub = chat.stream.listen((msgs) async {
      if (!mounted) return;
      // Not a length comparison: once the store's retention cap holds the list
      // at a constant length, a trim+append emission would read as "no new
      // message" and peek pulses / notifications would silently stop.
      final isNewMessage = appendedMessages(_messages.value, msgs).isNotEmpty;
      final lastMsg = isNewMessage ? msgs.last : null;

      _messages.value = msgs;

      if (_chatLayout.collapsed && isNewMessage) _pulsePeek();

      if (isNewMessage && lastMsg != null && lastMsg.username != _username) {
        // Real peer chat (not a system/sync line) wakes the dimmed card, which
        // then settles back out — so a brighten never lingers forever.
        if (!lastMsg.system) _wakeChatThenReArmDeepIdle();

        final focused = await windowManager.isFocused();
        if (!mounted) return;
        final kind = decideNotify(
          isSystem: lastMsg.system,
          isOwnMessage: lastMsg.username == _username,
          windowFocused: focused,
          chatCollapsed: _chatLayout.collapsed,
          // An expanded card the user can't read either: idle has faded it to
          // the dim ghost. `chatDimmedByIdle` defers to `chatOverlayOpacity`
          // for what's actually on screen — auto-dim off, or the wake-on-message
          // setting, keep the card fully visible, so those stay silent.
          chatDimmedByIdle: chatDimmedByIdle(
            idle: _isUiIdle,
            collapsed: _chatLayout.collapsed,
            autoDim: _chatAutoDim,
            wakeToFullyVisible: _chatWakeOnMessage,
          ),
          videoPlaying: _core.state.status == PlaybackStatus.playing,
        );
        if (kind == NotifyKind.none) return;
        if (_notifyClock.isRunning && _notifyClock.elapsed < _notifyThrottle) {
          return;
        }
        _notifyClock
          ..reset()
          ..start();
        final asset = kind == NotifyKind.primary
            ? resolvePrimary(_primarySoundId).asset
            : resolveSecondary(_secondarySoundId).asset;
        try {
          await _audioPlayer.open(Media(asset), play: true);
        } catch (e) {
          debugPrint('Failed to play notification: $e');
        }
      }
    });
    _reactionSub = chat.reactions.listen((e) {
      if (mounted && !_reactionFeed.isClosed) _reactionFeed.add(e.emoji);
    });
    _typingSub = chat.typing.listen(_onTyping);
  }

  /// Show the load-screen hint as a self-fading bottom toast (see [_FadingToast]:
  /// fades + slides in, holds, then fades + slides out — never a hard cut), plus
  /// a one-shot pulse of the collapsed chat tab. Shown each time the user lands
  /// on the load screen so chat (which starts collapsed) stays discoverable. The
  /// bumped [_chatHintSeq] re-keys the toast so a repeat show replays the
  /// animation even if one is still on screen.
  void _showChatTabHint() {
    if (!mounted) return;
    // Bump the token: a fresh value re-keys (and so replays) the toast even if a
    // previous one is still fading on screen.
    setState(() => _chatHintToken = (_chatHintToken ?? 0) + 1);
    if (_chatLayout.collapsed) _pulsePeek();
  }

  /// Tear down the hint toast once its exit animation has finished.
  void _dismissChatTabHint() {
    if (mounted) setState(() => _chatHintToken = null);
  }

  /// Track a peer's typing state (ignoring our own echoed signal). A 5s
  /// watchdog clears them in case the "stopped" signal is dropped.
  void _onTyping(TypingEvent e) {
    if (!mounted || e.username == _username) return;
    // A peer who wasn't typing now is — brighten the collapsed tab the same as
    // a fresh message would, so typing is noticeable without expanding (#53).
    final newlyTyping = e.isTyping && !_typingUsers.contains(e.username);
    _typingTimers[e.username]?.cancel();
    _typingTimers.remove(e.username);
    if (e.isTyping) {
      _typingUsers.add(e.username);
      _typingTimers[e.username] = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        _typingUsers.remove(e.username);
        _typingTimers.remove(e.username);
        _typingLabel.value = _typingLabelFor();
      });
    } else {
      _typingUsers.remove(e.username);
    }
    _typingLabel.value = _typingLabelFor();
    if (newlyTyping && _chatLayout.collapsed) _pulsePeek();
  }

  /// "lin is typing…" / "2 people are typing…", or null when nobody is.
  String? _typingLabelFor() {
    if (_typingUsers.isEmpty) return null;
    if (_typingUsers.length == 1) return '${_typingUsers.first} is typing…';
    return '${_typingUsers.length} people are typing…';
  }

  /// Toggle the chat card. When it collapses we restore focus to the player so
  /// the keyboard shortcut (Tab) and space/arrows keep working on one press.
  void _toggleChat() {
    setState(() => _chatLayout = _chatLayout.toggle());
    if (_chatLayout.collapsed) _restorePlayerFocus();
  }

  void _pulsePeek() {
    _peekPulsing.value = true;
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _peekPulsing.value = false;
    });
  }
}
