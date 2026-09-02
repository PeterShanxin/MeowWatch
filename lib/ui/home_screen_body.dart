part of 'home_screen.dart';

/// The widget-tree seam of [_HomeScreenState] (#182): the room's Stack
/// composition over the video surface, plus the load-screen hint toast.
///
/// Widget-tree invariant (#50): [ChatOverlayRegion] mounts `ChatOverlay` under
/// `AnimatedOpacity > IgnorePointer` — NOT a Stack — so never introduce a
/// `Positioned` here that isn't a *direct* child of a `Stack`, or release
/// builds paint a translucent white wash over the whole window. Regression
/// guard: test/ui/chat/chat_overlay_repaint_test.dart.
mixin _HomeBody
    on
        _HomeScreenStateBase,
        _HomeIdleState,
        _HomeSyncState,
        _HomeChatState,
        _HomeMediaState {
  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Scaffold(
      backgroundColor: m.background,
      // A non-focusable ancestor handler: it must NOT autofocus, or it
      // would steal primary focus from VideoSurface and kill its
      // space/arrow keys. Tab still reaches it by bubbling up from the
      // focused video surface, and skipTraversal stops the framework's
      // default Tab focus-traversal from swallowing it first.
      body: Focus(
        // Holds focus only when no VideoSurface is mounted (empty/waiting
        // screen) so the Tab handler always has a focused descendant. Never
        // autofocuses, so it won't steal the video's space/arrow keys.
        focusNode: _rootFocus,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          _onUserInteraction();
          if (_chrome.chat &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            _toggleChat();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerDown: (_) => _onUserInteraction(),
          onPointerMove: (_) => _onUserInteraction(),
          onPointerUp: (_) => _onUserInteraction(),
          onPointerHover: (_) => _onUserInteraction(),
          onPointerSignal: (_) => _onUserInteraction(),
          child: VideoDropTarget(
            onFileDropped: _handleDropped,
            // Narrowed, de-duplicated view: mpv's per-frame position ticks
            // must NOT rebuild this whole Stack (#181). Widgets that need
            // position (playback bar inside VideoSurface) subscribe to the raw
            // stateStream themselves.
            child: StreamBuilder<PlaybackScreenView>(
              stream: _core.screenViewStream,
              initialData: _core.screenView,
              builder: (context, snapshot) {
                final state = snapshot.data!;
                // Capture the offered URL from THIS build: the button's tap
                // closure must load exactly the link the visible notice
                // describes, even if _joinPrompt is cleared or replaced
                // before the tap lands (#214 review).
                final peerOfferUrl = _chrome.peerLoadPrompt
                    ? _joinPrompt?.url
                    : null;
                // True only while a video surface is actually on screen — not on
                // the empty/load screen, and not on the load-error screen.
                final videoVisible =
                    state.fileName != null &&
                    state.status != PlaybackStatus.error;
                return Stack(
                  fit: StackFit.expand,
                  // Every child carries a stable key. The conditional children
                  // (reactions overlay, reaction bar) insert/remove as a video
                  // loads/unloads, shifting later children's positions; without
                  // keys Flutter re-matches by index and destroys+rebuilds the
                  // shifted elements — which reset SyncHintBanner's AnimatedSwitcher
                  // (notices then hard-cut in) and ChatOverlay's state on every
                  // load. Keys keep each element's identity across the reshuffle.
                  children: [
                    DecoratedBox(
                      key: const ValueKey<String>('room-bg'),
                      decoration: m.backgroundGradient != null
                          ? BoxDecoration(gradient: m.backgroundGradient)
                          : BoxDecoration(color: m.background),
                    ),
                    if (state.fileName == null &&
                        !(_leavingRoom && !_everRoomConnected))
                      EmptyState(
                        key: const ValueKey<String>('empty-state'),
                        onBrowse: _browse,
                        onLeave: () => unawaited(_leave()),
                        leaveLabel: _isSynced ? 'Leave room' : 'Back',
                        onLoadUrl: (url) => unawaited(_load(url)),
                        notice: _chrome.peerLoadPrompt
                            ? _joinPrompt?.message
                            : null,
                        onWatchPeerUrl: peerOfferUrl == null
                            ? null
                            : () => unawaited(_load(peerOfferUrl)),
                      )
                    else if (state.status == PlaybackStatus.error)
                      VideoErrorState(
                        key: const ValueKey<String>('video-error'),
                        message: friendlyPlaybackError(
                          isUrl: isHttpUrl(state.filePath ?? ''),
                        ),
                        detail: state.errorMessage,
                        onLoadVideo: () => unawaited(_promptLoadVideo()),
                        // A repeat failure repaints an identical surface, so
                        // the attempt count is what makes it re-announce (#232).
                        attempt: _loadFailures,
                        onRetry: state.filePath != null
                            ? () => unawaited(_load(state.filePath!))
                            : null,
                      )
                    else
                      VideoSurface(
                        key: const ValueKey<String>('video-surface'),
                        core: _core,
                        focusNode: _videoFocus,
                        isUiIdle: _isUiIdle,
                        onUserInteraction: _onUserInteraction,
                      ),
                    if (videoVisible && _chrome.reactions)
                      Positioned.fill(
                        key: const ValueKey<String>('reactions-overlay'),
                        child: FloatingReactionsOverlay(
                          emojis: _reactionFeed.stream,
                        ),
                      ),
                    // Banner + chat show even before a video is loaded, so the
                    // "waiting / friend joined" notices and chat history are
                    // visible on the load-video screen (not just while watching).
                    // Always mounted: SyncHintBanner animates the notice in, out,
                    // and between changes (null = nothing shown).
                    Align(
                      key: const ValueKey<String>('sync-hint'),
                      alignment: const Alignment(0, -0.8),
                      // Transient notices (join/leave, throttled sync actions,
                      // and media/load failures) flow through their own
                      // notifier so a scrub burst dirties only this subtree
                      // (#196). Resolve progress outranks them; derived sync
                      // banners (waiting / connecting) only mount in synced
                      // sessions. Local still shows media-side notices — a
                      // bad paste during playback has no other failure
                      // surface (#254).
                      child: ValueListenableBuilder<String?>(
                        valueListenable: _resolveNotice,
                        builder: (context, resolving, _) =>
                            ValueListenableBuilder<String?>(
                              valueListenable: _presenceNotice,
                              builder: (context, notice, _) => SyncHintBanner(
                                text: selectSessionBanner(
                                  leavingRoom: _leavingRoom,
                                  resolving: resolving,
                                  notice: notice,
                                  derivedSync: _banner,
                                  syncBanners: _chrome.syncBanners,
                                ),
                              ),
                            ),
                      ),
                    ),
                    if (_chrome.chat)
                      ChatOverlayRegion(
                        key: const ValueKey<String>('chat-overlay'),
                        messages: _messages,
                        typingLabel: _typingLabel,
                        pulsing: _peekPulsing,
                        hasUnread: _chatHasUnread,
                        layout: _chatLayout,
                        isUiIdle: _isUiIdle,
                        isUiDeepIdle: _isUiDeepIdle,
                        autoDim: _chatAutoDim,
                        wakeOnMessage: _chatWakeOnMessage,
                        idleDimOpacity: _chatIdleDim,
                        onSend: _chat!.send,
                        onTypingChanged: (t) => _chat!.sendTyping(isTyping: t),
                        onToggleCollapsed: _toggleChat,
                        onSnap: (result) {
                          setState(
                            () => _chatLayout = _chatLayout.applySnap(result),
                          );
                          if (_chatLayout.collapsed) _restorePlayerFocus();
                          // Persist the docked corner like the size, so the
                          // card comes back where it was left. A collapse
                          // keeps .corner unchanged, so it is always the
                          // docked corner.
                          widget.settings.set(
                            kChatCardCornerSettingKey,
                            formatCardCorner(_chatLayout.corner),
                          );
                        },
                        onDraggingChanged: (d) =>
                            setState(() => _chatDragging = d),
                        onUnreadChanged: (has) => _chatHasUnread.value = has,
                        onResize: (size) {
                          setState(
                            () => _chatLayout = _chatLayout.applyResize(size),
                          );
                          widget.settings.set(
                            kChatCardSizeSettingKey,
                            formatCardSize(
                              _chatLayout.widthPx!,
                              _chatLayout.heightPx!,
                            ),
                          );
                        },
                        onResetSize: () {
                          setState(() => _chatLayout = _chatLayout.resetSize());
                          widget.settings.set(kChatCardSizeSettingKey, '');
                        },
                      ),
                    Positioned(
                      key: const ValueKey<String>('player-menu'),
                      top: 12,
                      left: 12,
                      // Fade the gear out while the chat card is being dragged so
                      // it never covers the top-left dock hint.
                      child: AnimatedOpacity(
                        opacity: _chatDragging || _isUiIdle ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: _chatDragging || _isUiIdle,
                          child: PlayerMenuButton(
                            sessionMode: _session.mode,
                            localPlayerMode: _isLocal,
                            onLocalPlayerModeChanged: (enabled) {
                              unawaited(_setEffectiveLocalMode(enabled));
                            },
                            historyMode: _historyMode,
                            onHistoryModeChanged: (mode) {
                              appLog(
                                'settings: history mode=${mode.storageName}',
                              );
                              setState(() => _historyMode = mode);
                              widget.settings.set(
                                kHistoryModeSettingKey,
                                mode.storageName,
                              );
                            },
                            // Self-contained share code: bare sentence on the
                            // default server, `room@host[:port]` when the host
                            // is non-default, so copying from the in-room gear
                            // hands a friend everything they need (#110).
                            roomCode: encodeShareCode(
                              room: widget.config.room,
                              server: widget.config.server,
                              port: widget.config.port,
                            ),
                            // Short/redacted label for a URL so a signed token
                            // isn't shown (and a long link doesn't bloat the menu).
                            nowPlaying: state.fileName == null
                                ? null
                                : mediaDisplayName(state.fileName!),
                            // Wire identities for the roster + isMe match; the
                            // "you" row shows our chosen name, not a transient
                            // reconnect dedupe suffix the server may assign (#107).
                            members: <String>[_username, ..._peers],
                            myUsername: _username,
                            myDisplayName: widget.config.username,
                            currentTheme: widget.currentTheme,
                            onThemeChanged: (theme) {
                              appLog('settings: theme=${theme.name}');
                              widget.onThemeChanged(theme);
                            },
                            // Inline inside the gear — picking a source here
                            // shouldn't throw a modal over the menu (#222).
                            onBrowse: () => unawaited(_browse()),
                            onLoadUrl: (url) => unawaited(_load(url)),
                            onLeave: _leave,
                            chatAutoDim: _chatAutoDim,
                            onChatAutoDimChanged: (val) {
                              setState(() => _chatAutoDim = val);
                              widget.settings.set(
                                kChatAutoDimSettingKey,
                                val.toString(),
                              );
                            },
                            chatWakeOnMessage: _chatWakeOnMessage,
                            onChatWakeOnMessageChanged: (val) {
                              setState(() => _chatWakeOnMessage = val);
                              widget.settings.set(
                                kChatWakeOnNewMessageSettingKey,
                                val.toString(),
                              );
                            },
                            chatIdleDim: _chatIdleDim,
                            onChatIdleDimChanged: (val) {
                              setState(() => _chatIdleDim = val);
                              widget.settings.set(
                                kChatIdleDimSettingKey,
                                val.toStringAsFixed(2),
                              );
                            },
                            primarySoundId: _primarySoundId,
                            onPrimarySoundChanged: (id) {
                              appLog('settings: primary sound=$id');
                              setState(() => _primarySoundId = id);
                              widget.settings.set(kNotifyPrimarySoundKey, id);
                            },
                            secondarySoundId: _secondarySoundId,
                            onSecondarySoundChanged: (id) {
                              appLog('settings: secondary sound=$id');
                              setState(() => _secondarySoundId = id);
                              widget.settings.set(kNotifySecondarySoundKey, id);
                            },
                            onPreviewSound: _previewSound,
                            logLevel: _logLevel,
                            onLogLevelChanged: _onLogLevelChanged,
                            onExportLogs: _exportLogs,
                          ),
                        ),
                      ),
                    ),
                    if (videoVisible && _chrome.reactionBar)
                      Positioned(
                        key: const ValueKey<String>('reaction-bar'),
                        right: 16,
                        bottom: 84,
                        child: AnimatedOpacity(
                          opacity: overlayOpacity(idle: _isUiIdle),
                          duration: Motion.base,
                          child: IgnorePointer(
                            ignoring: _isUiIdle,
                            child: ReactionBar(onReact: _chat!.sendReaction),
                          ),
                        ),
                      ),
                    // Load-screen "Press Tab" hint — a self-fading bottom toast.
                    if (_chrome.chatTabHint && _chatHintToken != null)
                      Align(
                        key: const ValueKey<String>('chat-tab-hint'),
                        alignment: const Alignment(0, 0.92),
                        child: _FadingToast(
                          key: ValueKey<int>(_chatHintToken!),
                          icon: Icons.chat_bubble_outline,
                          text: 'Press Tab to show or hide chat',
                          onDismissed: _dismissChatTabHint,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom toast that fades + slides itself in, holds, then fades + slides out
/// — so a transient hint is never removed with a hard cut. Calls [onDismissed]
/// once the exit animation finishes so the parent can drop it from the tree.
/// Enter and exit both use the shared [Motion] tokens (`base` duration,
/// `standard` curve); see the Motion section of the design-system spec.
class _FadingToast extends StatefulWidget {
  const _FadingToast({
    super.key,
    required this.icon,
    required this.text,
    required this.onDismissed,
  });

  final IconData icon;
  final String text;
  final VoidCallback onDismissed;

  /// How long the toast stays fully visible between its fade-in and fade-out.
  static const Duration hold = Duration(seconds: 3);

  @override
  State<_FadingToast> createState() => _FadingToastState();
}

class _FadingToastState extends State<_FadingToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.base, // fade/slide in
    reverseDuration: Motion.base, // fade/slide out
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.standard,
    reverseCurve: Motion.standard,
  );
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _holdTimer = Timer(_FadingToast.hold, _fadeOut);
  }

  void _fadeOut() {
    if (!mounted) return;
    _controller.reverse().whenComplete(() {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return IgnorePointer(
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(_curve),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            decoration: BoxDecoration(
              color: m.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: m.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: IconSizes.md, color: m.accent),
                const SizedBox(width: Spacing.md),
                Text(
                  widget.text,
                  style: TextStyle(
                    color: m.textPrimary,
                    fontSize: TypeScale.label,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
