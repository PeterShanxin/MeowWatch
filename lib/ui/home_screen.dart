import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../core/audio/notify_sounds.dart';
import '../core/chat/chat_store.dart';
import '../core/connect/room_config.dart';
import '../core/connect/room_share.dart';
import '../core/data/history_mode.dart';
import '../core/data/settings_store.dart';
import '../core/data/stores.dart';
import '../core/debug/app_log.dart';
import '../core/debug/debug_log.dart';
import '../core/debug/log_archive.dart';
import '../core/debug/log_level.dart';
import '../core/debug/log_redact.dart';
import '../core/sync/auto_pause.dart';
import '../core/sync/file_match.dart';
import '../core/sync/join_prompt.dart';
import '../core/sync/loaded_file_message.dart';
import '../core/sync/loaded_notice.dart';
import '../core/sync/presence_messages.dart';
import '../core/sync/room_greeting.dart';
import '../core/sync/roster_banner.dart';
import '../core/sync/peer_files.dart';
import '../core/sync/peer_state.dart';
import '../core/sync/playback_sync_bridge.dart';
import '../core/sync/sync_activity_throttle.dart';
import '../core/sync/syncplay_client.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/motion.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/video_engine_pool.dart';
import '../core/video/await_open_result.dart';
import '../core/video/picker_initial_directory.dart';
import '../core/video/playback_screen_view.dart';
import '../core/video/playback_state.dart';
import '../core/video/seek_when_ready.dart';
import '../core/video/source_announce.dart';
import '../core/video/video_url.dart';
import 'app_close_hook.dart';
import 'chat/chat_corner.dart';
import 'chat/chat_overlay_layout.dart';
import 'chat/chat_overlay_region.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'idle_rearm_throttle.dart';
import 'idle_visibility.dart';
import 'notify_decision.dart';
import 'paste_link_dialog.dart';
import 'player_menu_button.dart';
import 'reactions/floating_reactions.dart';
import 'reactions/reaction_bar.dart';
import 'sync_activity_text.dart';
import 'sync_hint_banner.dart';
import 'video_error_state.dart';
import 'video_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.config,
    required this.history,
    required this.settings,
    required this.currentTheme,
    required this.onThemeChanged,
    this.initialWidthPx,
    this.initialHeightPx,
    this.initialCorner,
    super.key,
  });

  final RoomConfig config;
  final HistoryStore history;
  final SettingsStore settings;
  final double? initialWidthPx;
  final double? initialHeightPx;

  /// The chat card's persisted docked corner; null falls back to the default.
  final ChatCorner? initialCorner;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MediaKitVideoCore _core;
  late final SyncplayClient _sync;
  late final PlaybackSyncBridge _bridge;

  /// The process-wide rotating diagnostic log, installed once at startup in
  /// `main()` and shared by the lobby, every room, and the update service
  /// (#140). Held as a getter (not a field) so HomeScreen reads the same
  /// instance everyone else writes to — it never owns, creates, or closes it.
  /// Null only if the log dir was unavailable, in which case the gear's
  /// export/level controls degrade gracefully.
  DebugLog? get _syncLog => appLogInstance;
  LogLevel _logLevel = LogLevel.verbose;
  HistoryMode _historyMode = HistoryMode.latestPerRoom;
  late final Player _audioPlayer;

  // Notification chime: bundled assets (portable, no dependency on a
  // system-specific sound file), throttled so a burst of messages doesn't
  // stack overlapping playbacks. Which preset plays is chosen in Settings and
  // resolved via [resolvePrimary]/[resolveSecondary].
  static const Duration _notifyThrottle = Duration(seconds: 2);
  final Stopwatch _notifyClock = Stopwatch();

  // Start as "connecting", not "disconnected": entering a room immediately
  // begins a connection, so the first frame should read "Connecting to room …"
  // rather than flashing "Disconnected from room …" before the socket dials.
  SyncConnectionStatus _syncStatus = SyncConnectionStatus.connecting;
  String? _syncError;
  final Set<String> _peers = <String>{};
  StreamSubscription<SyncConnectionState>? _connSub;
  StreamSubscription<PresenceEvent>? _presenceSub;
  StreamSubscription<PlaybackState>? _noticeSub;
  StreamSubscription<PeerFile>? _peerFileSub;
  StreamSubscription<SyncActivity>? _activitySub;
  StreamSubscription<List<String>>? _rosterSub;
  StreamSubscription<String>? _leavingSub;
  bool _leavingRoom = false;

  /// Our registered window-close hook (announces a deliberate leave so peers see
  /// "left the room" not "lost connection" when the app is closed via the X
  /// rather than the Leave button — #92). Held so dispose only clears the global
  /// when it's still ours.
  Future<void> Function()? _closeHook;

  /// Previous connection status — used to detect the drop edge.
  SyncConnectionStatus _prevSyncStatus = SyncConnectionStatus.disconnected;

  /// Latched true on a local drop (connected → reconnecting) and cleared when we
  /// reconnect or stop trying. Needed because the reconnect path passes through
  /// an intermediate `handshaking` state, so the "Reconnected to room." line
  /// can't be detected from `prev` alone (issue #92).
  bool _wasReconnecting = false;

  /// Our own dropped sessions' names → when each was latched. A reconnect that
  /// comes back under a different wire identity ("meowPEOW" → "meowPEOW_") means
  /// the server wouldn't hand our prior name back, because that just-dropped
  /// session still holds it as a ghost. Each such ghost is recorded here and
  /// consumed on its [PresenceKind.left] so the departure isn't announced as a
  /// peer "lost connection" — the name was ours (#93 field report).
  ///
  /// A map, not a single slot: a burst of chained reconnects (drop → reconnect →
  /// drop → reconnect before the first ghost is reaped) can leave several of our
  /// own names lingering at once, and each must be silenced. Entries are pruned
  /// by the reconnect window — a ghost's `left` is only silenced if it lands
  /// within that window of being latched, bounding the residual case where a
  /// real peer grabbed our just-freed name during the blip (#93 ambiguity).
  final Map<String, DateTime> _pendingGhosts = <String, DateTime>{};

  /// The server-assigned wire name from our most recent *connected* state. Lets
  /// the next reconnect tell whether the server handed our prior name back (no
  /// ghost) or moved us off it because our own dropped session still holds it.
  String? _lastConnectedUsername;

  /// Peers who sent a [LeavingSignal] before their [PresenceKind.left] event;
  /// consumed once on departure to determine clean vs. connection-drop wording.
  final Set<String> _cleanlyLeaving = <String>{};

  /// When each peer last departed, so a quick rejoin reads as "reconnected"
  /// rather than "joined the room" (issue #92).
  final Map<String, DateTime> _departedAt = <String, DateTime>{};

  /// Files announced by peers, keyed by username, plus our own loaded file's
  /// byte size — together they drive the file-mismatch warning. Keying by user
  /// (rather than a single slot) means a transient ghost of our own dropped
  /// session can't wipe a real friend's file when it departs (#93). [_peerFile]
  /// surfaces only a currently-present peer's file.
  PeerFiles _peerFiles = const PeerFiles();
  int? _localFileSizeBytes;

  /// The file of the peer we're currently watching with, or null if no present
  /// peer has announced one. Derived from [_peerFiles] restricted to [_peers].
  PeerFile? get _peerFile => _peerFiles.currentAmong(_peers);

  /// Was the session in sync (connected + a peer present) at the last check?
  /// Used to detect the healthy -> unhealthy edge that triggers auto-pause.
  bool _syncHealthy = false;

  /// True while we've auto-paused because sync dropped; drives the banner.
  bool _autoPausedNotice = false;

  /// The reason text for the current auto-pause (peer left vs. connection lost),
  /// snapshotted at pause time so the banner can't later show a stale cause.
  String? _autoPausedReason;

  /// Transient banner when a friend joins/rejoins the room (auto-clears).
  /// A notifier, not a plain field: activity/presence notices are hot events
  /// and must dirty only the banner subtree, not the whole room Stack (#196).
  final ValueNotifier<String?> _presenceNotice = ValueNotifier<String?>(null);
  Timer? _presenceTimer;

  /// The name of the last peer who left the room.
  String? _lastPeerLeft;

  /// Persistent "your friend started playback — load a video to join" prompt
  /// shown on the empty (no-video) screen when a peer controls playback before
  /// we've loaded anything (#60). Cleared once we load a video or the peer
  /// leaves. The reverse direction is handled by the same code running on the
  /// friend's machine. Carries a one-click [JoinPrompt.url] when the peer's
  /// announced media is a direct link (#121), so the empty screen can offer a
  /// "Watch this too" button in addition to the text.
  JoinPrompt? _joinPrompt;

  /// The source path that the *most recent* load actually confirmed open. The
  /// connect/reconnect re-announce gates on this so a still-loading, superseded,
  /// or failed source is never re-sent to the room — and so a valid live stream
  /// (which stays `paused` with no duration) still reannounces, where the bare
  /// state alone couldn't tell it apart from the pre-error paused tick. Set on a
  /// confirmed open in [_load], invalidated when a new load starts.
  String? _loadedSource;

  /// True while a [_browse] is between its click and the file picker appearing.
  /// The picker preflight now awaits (DB read + folder probes) before the modal
  /// opens, so the UI stays live in that gap; without this guard a second Load
  /// Video click would queue a second picker (#144 review).
  bool _browsing = false;

  /// Bumped at the start of every [_load]. Browse/Paste/drop stay reachable
  /// while a load is in flight, so a newer load can supersede an older one that's
  /// still awaiting its async open result. Each [_load] captures its generation
  /// and abandons quietly at every `await` boundary once it's no longer current,
  /// so a stale load can't fail, record, announce, or chat against the source a
  /// newer load now owns.
  int _loadGeneration = 0;

  /// Debounce before auto-pausing: a brief blip (e.g. a heartbeat timeout that
  /// recovers a second later, common when two instances share one PC) should
  /// NOT pause — only a sustained loss of sync.
  Timer? _autoPauseTimer;
  static const _autoPauseDelay = Duration(seconds: 2);

  late final ChatStore _chat;
  late ChatOverlayLayout _chatLayout;
  bool _chatDragging = false;

  /// Keyboard focus for the player. Held here (not inside VideoSurface) so that
  /// after the chat collapses — which removes its auto-focused text field — we
  /// can hand focus straight back to the player. Otherwise focus falls to the
  /// root and the next Tab is wasted just re-acquiring it (the "press Tab twice"
  /// bug). With focus always on a descendant, the Tab handler fires every press.
  final FocusNode _videoFocus = FocusNode(debugLabel: 'video-surface');

  /// Fallback keyboard-focus holder for when no video is loaded (so the empty /
  /// "waiting" screen still has a focused descendant for the Tab handler to fire
  /// from). skipTraversal keeps it out of Tab focus-traversal; we only ever
  /// focus it programmatically when restoring focus with no VideoSurface mounted.
  final FocusNode _rootFocus = FocusNode(
    debugLabel: 'home-root',
    skipTraversal: true,
  );
  // Hot chat-card state: every incoming chat line, typing signal, and peek
  // pulse used to force a setState that rebuilt the entire room Stack (#196).
  // As notifiers they dirty only ChatOverlayRegion's subtree instead.
  final ValueNotifier<List<ChatMessage>> _messages =
      ValueNotifier<List<ChatMessage>>(const <ChatMessage>[]);
  final ValueNotifier<String?> _typingLabel = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _peekPulsing = ValueNotifier<bool>(false);
  late String _username;
  Timer? _peekTimer;

  /// Non-null while the load-screen "Press Tab" hint toast is on screen; its
  /// value re-keys [_FadingToast] so each show replays the fade animation.
  int? _chatHintToken;
  Timer? _historyTimer;
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

  bool _isUiIdle = false;
  Timer? _uiIdleTimer;

  /// Monotonic clock + throttle so a burst of pointer hover/move events doesn't
  /// cancel-and-reallocate the idle timers on every raw event (#182). Waking
  /// from idle stays immediate; only the re-arm is coalesced.
  final Stopwatch _interactionClock = Stopwatch()..start();
  final IdleRearmThrottle _idleRearm = IdleRearmThrottle();

  /// Second idle stage: after staying idle past the first threshold, the dimmed
  /// chat card fades fully out (issue #34) instead of lingering as a ghost.
  bool _isUiDeepIdle = false;
  Timer? _uiDeepIdleTimer;
  static const _uiIdleDelay = Duration(seconds: 3);
  static const _uiDeepIdleDelay = Duration(seconds: 3);

  bool _chatAutoDim = true;
  final ValueNotifier<bool> _chatHasUnread = ValueNotifier<bool>(false);
  bool _chatWakeOnMessage = false;
  double _chatIdleDim = kChatIdleGhostOpacity;
  String _primarySoundId = kDefaultPrimarySoundId;
  String _secondarySoundId = kDefaultSecondarySoundId;

  /// Collapses bursts of seek notifications into a single line/banner (#26).
  final SyncActivityThrottle _activityThrottle = SyncActivityThrottle();
  StreamSubscription<SyncActivity>? _activityThrottleSub;

  @override
  void initState() {
    super.initState();
    _initSettings();
    _onUserInteraction();
    // Restore the persisted corner into BOTH slots: we start collapsed, and
    // expanding restores lastCorner — corner alone would be discarded by the
    // first toggle.
    final corner = widget.initialCorner ?? ChatCorner.bottomLeft;
    _chatLayout = ChatOverlayLayout(
      // Start collapsed so the load screen stays clean (just a small chat tab in
      // the corner) instead of a big empty card crowding the load controls. Tab
      // — hinted on the load screen — expands it.
      collapsed: true,
      corner: corner,
      lastCorner: corner,
      widthPx: widget.initialWidthPx,
      heightPx: widget.initialHeightPx,
    );
    // Borrow the process-lifetime engines instead of creating per-room ones:
    // disposing a libmpv Player on leave can deadlock the UI thread on Windows
    // and permanently freeze the Connect screen (#137). See [VideoEnginePool].
    _core = VideoEnginePool.instance.videoCore;
    // Hashed label, never the raw room: a private room's name is its access
    // code, so logging it verbatim would leak the room credential (#146 review).
    appLog('life: enter ${roomLogLabel(widget.config.room)}');
    _sync = SyncplayClient(
      onLog: appLog,
      shouldLog: ({required bool verboseOnly}) {
        final level = appLogInstance?.level;
        return level == LogLevel.verbose ||
            (!verboseOnly && level == LogLevel.neat);
      },
    );
    _bridge = PlaybackSyncBridge(video: _core, sync: _sync)..start();
    _chat = ChatStore(sync: _sync);
    _audioPlayer = VideoEnginePool.instance.audioPlayer;
    _chatSub = _chat.stream.listen((msgs) async {
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
    _reactionSub = _chat.reactions.listen((e) {
      if (mounted && !_reactionFeed.isClosed) _reactionFeed.add(e.emoji);
    });
    _typingSub = _chat.typing.listen(_onTyping);
    _connSub = _sync.connectionState.listen((s) {
      if (mounted) {
        setState(() {
          _syncStatus = s.status;
          _syncError = s.message;
          // Adopt the server-assigned wire identity so chat ownership, typing
          // attribution and self-notifications all match the name peers (and the
          // chat echo) actually use for us (#40). This is the WIRE name only — it
          // can carry a transient dedupe suffix after a reconnect, so the gear
          // member list shows widget.config.username (our chosen name) instead (#107).
          if (s.username != null && s.username!.isNotEmpty) {
            _username = s.username!;
          }
          if (s.status != SyncConnectionStatus.connected) {
            // Our own connection changed — peer membership and the per-peer
            // departure/leaving bookkeeping are no longer valid. Clearing here
            // also bounds these maps across repeated local reconnect cycles.
            _peers.clear();
            _departedAt.clear();
            _cleanlyLeaving.clear();
            // NB: do NOT clear _pendingGhosts here. A fresh drop is exactly when
            // a chained reconnect adds another of our own ghosts; discarding the
            // earlier ones would leak their `left` as a peer "lost connection".
            // They are pruned by the reconnect-window expiry instead (#93).
            // Drop the cached peer files too, so they are rebuilt
            // deterministically from the post-reconnect roster rather than
            // masking a stale value (#93). _peerNoVideoHint is gated on
            // _syncHealthyNow, so this can't flash "hasn't loaded" while
            // we're disconnected.
            _peerFiles = const PeerFiles();
            // The empty-screen join prompt is pinned imperatively from peer
            // file/playback events, so it isn't gated on sync health like the
            // banner is. Clear it here too, or a "<peer> loaded …" / "started
            // playback …" nudge stays on the load screen with no peer present
            // while we reconnect or disconnect (#116 review).
            _joinPrompt = null;
          }
          _evaluateSyncHealth();
        });
      }
      // Local connection transition chat lines (issue #92). Run after setState
      // so _syncStatus is already updated; addSystem pushes its own emission.
      if (isConnectionDrop(prev: _prevSyncStatus, next: s.status)) {
        _wasReconnecting = true;
        _chat.addSystem(connectionLostMessage);
      } else if (isReconnectSuccess(
        wasReconnecting: _wasReconnecting,
        next: s.status,
      )) {
        _wasReconnecting = false;
        _chat.addSystem(reconnectedToRoomMessage);
        // If the server wouldn't hand our prior wire name back on this
        // reconnect, our just-dropped session is lingering as a ghost on it and
        // will shortly be reaped — record it so its departure is silenced, not
        // read as a peer "lost connection" (#93 field report). Uses the prior
        // assigned name (_lastConnectedUsername), set below for the next pass.
        final now = DateTime.now();
        // Prune expired ghosts first so the map can't grow without bound when a
        // ghost is never reaped (no `left` ever arrives).
        _pendingGhosts.removeWhere(
          (_, at) => !isPeerReconnect(departedAt: at, now: now),
        );
        final ghost = ownGhostNameOnReconnect(
          reconnected: true,
          previousAssignedName: _lastConnectedUsername,
          assignedName: s.username,
        );
        if (ghost != null) _pendingGhosts[ghost] = now;
      }
      // A deliberate leave or fatal error ends the reconnect attempt — drop the
      // latch so a later fresh connect isn't mistaken for a reconnect, and clear
      // pending ghosts (we're leaving this room; they're moot).
      if (s.status == SyncConnectionStatus.disconnected ||
          s.status == SyncConnectionStatus.error) {
        _wasReconnecting = false;
        _pendingGhosts.clear();
      }
      // Remember the wire name we connected under, so the next reconnect can
      // tell a server-forced rename (our ghost holds the old name) from getting
      // the same name back. Updated after the arm above, which reads the prior.
      if (s.status == SyncConnectionStatus.connected) {
        _lastConnectedUsername = s.username;
      }
      _prevSyncStatus = s.status;
      if (s.status == SyncConnectionStatus.connected &&
          _shouldReannounceOnConnect()) {
        _announceLoadedFile(_loadedSource);
      }
    });
    // Track peers who announced a deliberate leave so the presence listener can
    // distinguish "left the room" from "lost connection" (issue #92).
    _leavingSub = _chat.leaving.listen((name) => _cleanlyLeaving.add(name));
    _presenceSub = _sync.presence.listen((e) {
      if (!mounted) return;
      // Our own lingering ghost (a post-reconnect roster entry under a name the
      // server renamed us off) must never be treated as a peer — otherwise it
      // enters _peers and its eventual `left` flips sync health, auto-pausing us
      // for our own old session (#93). Skip its *join* outright; its `left` is
      // consumed silently in the departure handler below to clear the latch.
      if (e.kind == PresenceKind.joined && _isOwnGhost(e.username)) return;
      setState(() {
        if (e.kind == PresenceKind.joined) {
          final isNew = _peers.add(e.username);
          // Roster entries (people already here when we arrived) update
          // membership silently; only a live join gets a banner + event line.
          if (isNew && !e.fromRoster) {
            final reconnected = isPeerReconnect(
              departedAt: _departedAt[e.username],
              now: DateTime.now(),
            );
            _departedAt.remove(e.username);
            final banner = reconnected
                ? '🐾 ${e.username} reconnected'
                : '🐾 ${e.username} joined';
            _showTransientNotice(banner);
            _chat.addSystem(
              peerJoinMessage(username: e.username, reconnected: reconnected),
            );
            if (_shouldReannounceOnConnect()) {
              _announceLoadedFile(_loadedSource);
            }
          }
        } else {
          _peers.remove(e.username);
          _peerFiles = _peerFiles.remove(e.username);
          // The "load a video to join" prompt is stale once they've left (#60).
          _joinPrompt = null;
          // Our own lingering ghost from a server-forced rename, but only if its
          // `left` lands within the reconnect window — a much later departure of
          // the same name is a real peer that grabbed it, not our ghost (#93).
          final isOwnGhost = _isOwnGhost(e.username);
          // Consume the latch (whether or not in-window) so a stale ghost can't
          // keep shadowing this name.
          _pendingGhosts.remove(e.username);
          if (isOwnGhost) {
            // The ghost was skipped at join, so it was never in _peers and the
            // _evaluateSyncHealth() below sees no change. Just clear its
            // bookkeeping and stay silent — the name was ours (#93).
            _departedAt.remove(e.username);
            _cleanlyLeaving.remove(e.username);
          } else {
            _lastPeerLeft = e.username;
            final clean = _cleanlyLeaving.remove(e.username);
            // Only a *drop* makes a quick return read as "reconnected"; a
            // deliberate leave that comes back is a fresh "joined", not a network
            // blip recovering (#92 follow-up).
            if (clean) {
              _departedAt.remove(e.username);
            } else {
              _departedAt[e.username] = DateTime.now();
            }
            final banner = clean
                ? '👋 ${e.username} left'
                : '📵 ${e.username} lost connection';
            _showTransientNotice(banner);
            _chat.addSystem(
              peerDepartureMessage(username: e.username, clean: clean),
            );
          }
        }
        _evaluateSyncHealth();
      });
    });
    _peerFileSub = _sync.peerFile.listen((f) {
      if (!mounted) return;
      setState(() {
        _peerFiles = _peerFiles.set(f);
        // A peer announced a loaded file while we have nothing loaded: pin the
        // "load the same video to join" prompt on the empty screen so the side
        // still picking a file knows which one — the mirror of the loader's
        // "hasn't loaded a video yet" heads-up (#116). The play-triggered prompt
        // below takes over if/when they actually start playback. When the
        // peer's media is a direct link, offer a one-click "Watch this too"
        // load instead of the plain text — same trigger, richer action (#121).
        final localHasFile = _core.state.fileName != null;
        JoinPrompt? prompt;
        if (isHttpUrl(f.name)) {
          prompt = peerLoadedUrlJoinPrompt(
            localHasFile: localHasFile,
            localUsername: _username,
            peerUsername: f.username,
            peerFileUrl: f.name,
          );
        } else {
          final message = peerLoadedJoinPrompt(
            localHasFile: localHasFile,
            localUsername: _username,
            peerUsername: f.username,
            // Show the short/redacted label — a peer's raw URL (with any
            // signed token) must never render verbatim in our join prompt.
            peerFileName: mediaDisplayName(f.name),
          );
          if (message != null) prompt = JoinPrompt(message);
        }
        if (prompt != null) _joinPrompt = prompt;
      });
    });
    // Sync activities (peer + our own) flow through the throttle so a scrub
    // burst collapses to one line/banner (#26); the throttled output drives the
    // banner + chat history. We gate on sync health at BOTH ends: at intake to
    // avoid buffering lonely activity, and again at output because the throttle
    // debounce can outlast a peer leaving — without the second gate, an activity
    // queued while healthy would still surface after sync is gone (#41).
    _activitySub = _sync.activity.listen((a) {
      if (!_syncHealthyNow) return;
      _activityThrottle.add(a);
    });
    _activityThrottleSub = _activityThrottle.stream.listen((a) {
      if (!mounted || !_syncHealthyNow) return;
      final t = syncActivityText(a, selfUsername: _username);
      // The banner is a notifier write — a scrub burst must not rebuild the
      // whole Stack (#196). Only the (usually absent) join prompt, which the
      // empty screen consumes, still needs a setState.
      _showTransientNotice(t.banner);
      // A peer drove playback while we have no video loaded: the transient
      // banner is easy to miss on the empty screen, so also pin a persistent
      // "load a video to join" prompt there (#60).
      // Carry an active one-click URL offer through the play-start prompt:
      // the peer pressing play on the link they announced must not downgrade
      // the "Watch this too" button to plain text (#121 follow-up).
      final prompt = peerStartedPlaybackPrompt(
        localHasFile: _core.state.fileName != null,
        localUsername: _username,
        peerUsername: a.username,
        offeredUrl: _joinPrompt?.url,
      );
      if (prompt != null) {
        setState(() => _joinPrompt = prompt);
      }
      _chat.addSystem(t.chatLine);
    });
    _rosterSub = _sync.initialRoster.listen((members) {
      if (!mounted) return;
      _chat.addSystem(roomGreeting(members));
      // Friends already in the room when you arrive get a banner too, not just
      // the chat greeting (easy to miss on the video). Live joins after this are
      // handled by the presence handler above.
      final banner = rosterPresenceBanner(members);
      if (banner != null) _showTransientNotice(banner);
    });
    _noticeSub = _core.stateStream.listen((s) {
      if (!mounted) return;
      if (_autoPausedNotice && s.status == PlaybackStatus.playing) {
        setState(() => _autoPausedNotice = false);
      }
      if ((_isUiIdle || _isUiDeepIdle) && s.status != PlaybackStatus.playing) {
        _uiDeepIdleTimer?.cancel();
        setState(() {
          _isUiIdle = false;
          _isUiDeepIdle = false;
        });
      }
    });

    _username = widget.config.username;
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveResumePosition());
    });
    unawaited(
      _sync.connect(
        server: widget.config.server,
        port: widget.config.port,
        username: widget.config.username,
        room: widget.config.room,
        password: widget.config.password,
      ),
    );
    // Announce a deliberate leave if the window is closed (X button) while we're
    // in the room — disconnect() sends the leaving signal with a bounded flush
    // (#92). The Leave button already does this directly via _leave().
    _closeHook = () async {
      appLog('life: window-close hook fired (announcing leave)');
      await _sync.disconnectForAppClose();
      appLog('life: window-close leave sent');
    };
    appCloseHook.value = _closeHook;
    final resume = widget.config.resumeFilePath;
    if (resume != null) {
      unawaited(_resume(resume, widget.config.resumePositionMs));
    }
    // Landing on the load screen (no video yet): nudge the user that chat lives
    // behind Tab — a quick fading toast plus a pulse of the collapsed chat tab.
    // Skipped if we're resuming straight into a video.
    if (resume == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _core.state.fileName != null) return;
        // Give the invisible root holder focus so the FIRST Tab bubbles to the
        // chat toggle instead of being swallowed by default focus traversal —
        // otherwise the load screen needs two Tab presses to open chat.
        _rootFocus.requestFocus();
        _showChatTabHint();
      });
    }
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

  Future<void> _initSettings() async {
    // Restore the chat card's persisted size + corner NOW, not from the
    // app-startup snapshot the constructor carries: that snapshot goes stale
    // the moment the user resizes/moves the card, so re-entering a room used
    // to reset the card. The card starts collapsed, so this async read always
    // lands before it is first shown.
    final sizeValue = await widget.settings.get(kChatCardSizeSettingKey);
    final cornerValue = await widget.settings.get(kChatCardCornerSettingKey);
    if (mounted) {
      setState(
        () => _chatLayout = restoredLayout(
          base: _chatLayout,
          sizeValue: sizeValue,
          cornerValue: cornerValue,
        ),
      );
    }
    await _loadLogLevel();
    final dimSetting = await widget.settings.get(kChatAutoDimSettingKey);
    if (dimSetting == 'false' && mounted) {
      setState(() => _chatAutoDim = false);
    }
    final wakeSetting = await widget.settings.get(
      kChatWakeOnNewMessageSettingKey,
    );
    if (wakeSetting == 'true' && mounted) {
      setState(() => _chatWakeOnMessage = true);
    }
    final dimSettingRaw = await widget.settings.get(kChatIdleDimSettingKey);
    final dim = double.tryParse(dimSettingRaw ?? '');
    if (dim != null && mounted) {
      setState(
        () => _chatIdleDim = dim.clamp(kChatIdleDimMin, kChatIdleDimMax),
      );
    }
    final primary = await widget.settings.get(kNotifyPrimarySoundKey);
    final secondary = await widget.settings.get(kNotifySecondarySoundKey);
    if (mounted) {
      setState(() {
        _primarySoundId = resolvePrimary(primary).id;
        _secondarySoundId = resolveSecondary(secondary).id;
      });
    }
    final historyMode = historyModeFromName(
      await widget.settings.get(kHistoryModeSettingKey),
    );
    if (mounted) setState(() => _historyMode = historyMode);
  }

  /// Read the persisted diagnostic-log level into [_logLevel] so the gear menu
  /// shows the right selection. The live log itself was already opened at this
  /// level in `main()` (#140) — this only mirrors it into the UI state.
  Future<void> _loadLogLevel() async {
    final level = logLevelFromName(
      await widget.settings.get(kLogLevelSettingKey),
    );
    if (mounted) setState(() => _logLevel = level);
  }

  /// Apply a new diagnostic-log level live and persist it.
  void _onLogLevelChanged(LogLevel level) {
    // Log the change at the *current* level first — switching to `off` closes
    // the sink, so a line emitted afterward would be dropped.
    appLog('settings: log level=${level.storageName}');
    setState(() => _logLevel = level);
    _syncLog?.level = level;
    widget.settings.set(kLogLevelSettingKey, level.storageName);
  }

  /// Bundle the rotating logs into a single zip the user picks a location for,
  /// so they can send us the evidence after a laggy session.
  Future<void> _exportLogs() async {
    final dir = _syncLog?.dir;
    if (dir == null) {
      _showLogSnack('No diagnostic logs to export yet.');
      return;
    }
    // Push the live session's buffered lines to disk first, or the zip would
    // omit the most recent (and most relevant) trace.
    await _syncLog?.flush();
    // Zip in a background isolate — this can run mid-playback (#197 P4).
    final zipBytes = await zipLogFilesInBackground(dir.path);
    if (zipBytes == null) {
      _showLogSnack('No diagnostic logs to export yet.');
      return;
    }
    try {
      final location = await getSaveLocation(
        suggestedName: 'meowwatch-logs.zip',
      );
      if (location == null) return; // user cancelled
      await File(location.path).writeAsBytes(zipBytes);
      _showLogSnack('Saved diagnostic logs.');
    } on Object {
      _showLogSnack('Could not save the logs.');
    }
  }

  void _showLogSnack(String text) {
    if (!mounted) return;
    final m = context.meow;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: m.surface,
          content: Text(text, style: TextStyle(color: m.textPrimary)),
        ),
      );
  }

  void _onUserInteraction() {
    if (_isUiIdle || _isUiDeepIdle) {
      setState(() {
        _isUiIdle = false;
        _isUiDeepIdle = false;
      });
      // Waking must re-arm the countdown now, not wait out the throttle window.
      _idleRearm.reset();
    }
    // Pointer hover/move fires hundreds of times a second; only re-arm the idle
    // timers at most once per throttle window. The (rare) wake above always
    // re-arms via reset(); the still-running timer covers the skipped events.
    if (!_idleRearm.shouldRearm(_interactionClock.elapsed)) return;
    _uiIdleTimer?.cancel();
    _uiDeepIdleTimer?.cancel();
    _uiIdleTimer = Timer(_uiIdleDelay, () {
      if (!mounted || _core.state.status != PlaybackStatus.playing) return;
      setState(() => _isUiIdle = true);
      // Stage two: once idle persists, fully hide the dimmed chat card (#34).
      _uiDeepIdleTimer = Timer(_uiDeepIdleDelay, _enterDeepIdle);
    });
  }

  void _enterDeepIdle() {
    if (!mounted || _core.state.status != PlaybackStatus.playing) return;
    setState(() => _isUiDeepIdle = true);
  }

  /// A fresh peer message during idle should wake the dimmed chat and then let
  /// it settle out again, instead of lingering on screen forever. Drop deep
  /// idle so the card brightens (ghost, or full per the wake setting) and
  /// restart the deep-idle countdown so it fades back out if ignored. We keep
  /// `_isUiIdle` as-is — only the chat wakes, the controls/gear stay hidden.
  void _wakeChatThenReArmDeepIdle() {
    if (!_isUiIdle) return;
    _uiDeepIdleTimer?.cancel();
    if (_isUiDeepIdle) setState(() => _isUiDeepIdle = false);
    _uiDeepIdleTimer = Timer(_uiDeepIdleDelay, _enterDeepIdle);
  }

  @override
  void dispose() {
    appLog('life: dispose home (tearing down room)');
    // Drop the window-close hook (only if it's still ours) so a closed room
    // doesn't keep preventing the OS fast-close path.
    if (identical(appCloseHook.value, _closeHook)) appCloseHook.value = null;
    _uiIdleTimer?.cancel();
    _uiDeepIdleTimer?.cancel();
    _historyTimer?.cancel();
    unawaited(_saveResumePosition());
    _peekTimer?.cancel();
    unawaited(_chatSub?.cancel());
    unawaited(_reactionSub?.cancel());
    unawaited(_typingSub?.cancel());
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    unawaited(_reactionFeed.close());
    unawaited(_chat.dispose());
    unawaited(_connSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_noticeSub?.cancel());
    unawaited(_peerFileSub?.cancel());
    unawaited(_activitySub?.cancel());
    unawaited(_rosterSub?.cancel());
    unawaited(_leavingSub?.cancel());
    unawaited(_activityThrottleSub?.cancel());
    unawaited(_activityThrottle.dispose());
    _presenceTimer?.cancel();
    _autoPauseTimer?.cancel();
    // Notifier teardown: their timers and stream subscriptions are all
    // cancelled above, so nothing writes them after this point.
    _messages.dispose();
    _typingLabel.dispose();
    _peekPulsing.dispose();
    _chatHasUnread.dispose();
    _presenceNotice.dispose();
    unawaited(_bridge.dispose());
    unawaited(_sync.dispose());
    // Reset, don't dispose: the engines are shared (process-lifetime) and a
    // libmpv dispose here can deadlock-freeze the next screen on Windows (#137).
    // The bridge above already cancelled its subscriptions to _core, and each
    // new room re-subscribes to the reused engine. See [VideoEnginePool].
    unawaited(_core.reset());
    unawaited(_audioPlayer.stop());
    // Flush, don't close: the session log is process-wide (#140) and the lobby
    // (and any next room) keep writing to it. Pushing buffered lines to disk
    // here means a freeze right after leaving still has this room's trace on
    // disk. The log is closed only on app exit (the window-close handler).
    unawaited(_syncLog?.flush() ?? Future<void>.value());
    _videoFocus.dispose();
    _rootFocus.dispose();
    // Synchronous exit checkpoint (#176). `_core.reset()` above is unawaited and
    // its `_player.stop()` is async (media_kit dispatches via mpv_command_async),
    // so reset() yields at `await stop()` and this line runs right after —
    // meaning the crash-markers sidecar normally reads `reset stop begin`,
    // `dispose home done`, then (once stop acks) `reset stop done`. So this
    // checkpoint marks only that dispose()'s SYNCHRONOUS body finished; it does
    // NOT imply the engine stopped. Read the tail by `reset stop done`, not this
    // line: `reset stop done` present ⇒ stop completed and any freeze is later
    // (post-dispose native render/raster teardown of the held frame); `reset stop
    // begin` with no `reset stop done` ⇒ wedged in/around libmpv `stop()`,
    // regardless of `dispose home done`. Written with appLogSync (not appLog)
    // because dispose() can't await and a queued async flush would never run if
    // the freeze lands in or right after super.dispose().
    appLogSync('life: dispose home done');
    super.dispose();
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

  /// True only while a real [VideoSurface] is on screen — not on the empty/load
  /// screen and not on the load-error screen (which shows [VideoErrorState], so
  /// `_videoFocus` is attached to nothing). Mirrors the `videoVisible` gate in
  /// [build] so focus is always requested on a node that actually exists.
  bool get _videoSurfaceMounted =>
      _core.state.fileName != null &&
      _core.state.status != PlaybackStatus.error;

  /// Put keyboard focus on whichever node is live for the current screen so the
  /// top-level Tab handler always has a focused descendant to bubble from and
  /// Tab toggles chat on a *single* press. The video surface when one is
  /// mounted, else the invisible root holder. Called on load-screen entry and
  /// whenever the chat collapses (chevron toggle AND drag-to-hide snap — the
  /// drag path used to skip this, which is why hiding-by-drag needed two Taps).
  void _restorePlayerFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_videoSurfaceMounted) {
        _videoFocus.requestFocus();
      } else {
        _rootFocus.requestFocus();
      }
    });
  }

  /// Play a preset on demand for the Settings preview. Bypasses the notify
  /// throttle so a preview always sounds, but reuses the same player.
  Future<void> _previewSound(String asset) async {
    try {
      await _audioPlayer.open(Media(asset), play: true);
    } catch (e) {
      debugPrint('Failed to preview sound: $e');
    }
  }

  void _pulsePeek() {
    _peekPulsing.value = true;
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _peekPulsing.value = false;
    });
  }

  /// Show a transient banner (friend joined/left, or a sync action); auto-clears
  /// after a few seconds. Writes the notifier directly — no setState needed;
  /// only the banner subtree rebuilds (#196).
  void _showTransientNotice(String text) {
    _presenceNotice.value = text;
    _presenceTimer?.cancel();
    _presenceTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _presenceNotice.value = null;
    });
  }

  bool get _syncHealthyNow => SyncHealth(
    connected: _syncStatus == SyncConnectionStatus.connected,
    hasPeer: _peers.isNotEmpty,
  ).healthy;

  /// True when [name] is one of our own pending ghosts still inside the
  /// reconnect window — a post-reconnect roster/`left` event for our just-renamed
  /// prior session, not a real peer (#93). Non-consuming; the departure handler
  /// removes the entry from [_pendingGhosts] when the `left` actually fires.
  bool _isOwnGhost(String name) {
    final at = _pendingGhosts[name];
    return at != null && isPeerReconnect(departedAt: at, now: DateTime.now());
  }

  /// Recompute sync health and (after a debounce) auto-pause on a sustained
  /// healthy -> unhealthy drop. Call inside setState after [_syncStatus] /
  /// [_peers] change.
  void _evaluateSyncHealth() {
    final nowHealthy = _syncHealthyNow;
    final isPlaying = _core.state.status == PlaybackStatus.playing;

    if (nowHealthy) {
      // Recovered (or never lost) — cancel any pending pause, clear banner.
      // Also forget who last left: keeping it would let a later *connection*
      // drop wrongly blame a friend who left a different session ago.
      _autoPauseTimer?.cancel();
      _autoPauseTimer = null;
      _autoPausedNotice = false;
      _lastPeerLeft = null;
    } else if (decideAutoPause(
          wasHealthy: _syncHealthy,
          nowHealthy: nowHealthy,
          isPlaying: isPlaying,
        ) &&
        _autoPauseTimer == null) {
      // Edge into unhealthy while playing — arm the debounce, confirm later.
      _autoPauseTimer = Timer(_autoPauseDelay, _confirmAutoPause);
    }
    _syncHealthy = nowHealthy;
  }

  /// Fires after the debounce: pause only if sync is STILL down and we're
  /// still playing. A blip that already recovered cancelled this timer.
  void _confirmAutoPause() {
    _autoPauseTimer = null;
    if (!mounted) return;
    final stillDown = !_syncHealthyNow;
    final playing = _core.state.status == PlaybackStatus.playing;
    if (stillDown && playing) {
      // Phrase the reason by actual cause: a friend leaving (still connected,
      // empty room) names them; any other drop is a connection loss and must
      // not claim someone left (#41 follow-up).
      final reason = autoPauseMessage(
        cause: autoPauseCause(
          connected: _syncStatus == SyncConnectionStatus.connected,
          hasPeer: _peers.isNotEmpty,
        ),
        peerName: _lastPeerLeft,
      );
      unawaited(_core.pause());
      setState(() {
        _autoPausedNotice = true;
        _autoPausedReason = reason;
      });
      _chat.addSystem(reason);
    }
  }

  /// Banner text derived from setState-managed state, or null when nothing to
  /// say — everything below the transient [_presenceNotice], which is a
  /// notifier and layered on top in [build] (#196). Priority: a file-mismatch
  /// warning, then the auto-pause reason, then a "friend hasn't loaded a
  /// video" heads-up, then the plain waiting/connect hint.
  String? get _banner {
    // Once leaving is committed, suppress every hint — the socket teardown can
    // briefly flip status to "Connecting…/Disconnected" and we don't want that
    // flashing over the video during the leave + route-exit animation.
    if (_leavingRoom) return null;
    final mismatch = _fileMismatchBanner;
    if (mismatch != null) return mismatch;
    if (_autoPausedNotice) {
      return '⏸ ${_autoPausedReason ?? 'Paused — lost sync with your friend'}';
    }
    final waitingForPeerVideo = _peerNoVideoHint;
    if (waitingForPeerVideo != null) return waitingForPeerVideo;
    return _syncHint;
  }

  /// The flip side of the empty-screen join prompt (#60): once WE have a video
  /// loaded and a friend is in the room but hasn't loaded one yet (no announced
  /// peer file), tell us they can't follow along until they load it — so a
  /// one-sided session isn't silent on our end either.
  String? get _peerNoVideoHint {
    if (_core.state.fileName == null) return null; // their concern, not ours
    if (!_syncHealthyNow) return null; // need a connected friend present
    if (_peerFile != null) return null; // they've announced a file
    final peer = _peers.isNotEmpty ? _peers.first : null;
    if (peer == null) return null;
    return '⏳ $peer hasn\'t loaded a video yet';
  }

  /// Warn when the peer's loaded file clearly differs from ours.
  String? get _fileMismatchBanner {
    final peer = _peerFile;
    if (peer == null) return null;
    final result = compareFiles(
      localName: _core.state.fileName,
      localSize: _localFileSizeBytes,
      peerName: peer.name,
      peerSize: peer.sizeBytes,
    );
    if (result != FileMatch.mismatch) return null;
    // Match on the raw name above; show the short/redacted label in the banner.
    return '⚠ Different file — ${peer.username} has "${mediaDisplayName(peer.name)}"';
  }

  /// Advisory hint shown over the video, or null when everything is ready.
  /// Reflects the live connection status (so the user sees "Connecting to room
  /// X…" instead of a generic prompt while the socket is still negotiating).
  String? get _syncHint {
    final room = widget.config.room;
    switch (_syncStatus) {
      case SyncConnectionStatus.connecting:
      case SyncConnectionStatus.handshaking:
        return 'Connecting to room $room…';
      case SyncConnectionStatus.reconnecting:
        // Surface the concrete failure reason when we have one (e.g. "Could not
        // reach server…" from a failed dial); otherwise the generic line.
        return _syncError != null
            ? '${_syncError!} — reconnecting…'
            : 'Connection lost — reconnecting to room $room…';
      case SyncConnectionStatus.error:
        return _syncError ?? 'Couldn\'t connect to room $room';
      case SyncConnectionStatus.disconnected:
        return 'Disconnected from room $room';
      case SyncConnectionStatus.connected:
        if (_peers.isEmpty) return 'Waiting for a friend to join…';
        return null;
    }
  }

  /// Load (but do not auto-play). In a room, hitting play yourself starts both
  /// of you in sync; auto-playing on load made the two clients fight at 0.
  ///
  /// Returns `true` only if *this* load opened and is still the current source —
  /// callers (e.g. resume) can then act on it; a `false` means it failed, timed
  /// out, or was superseded by a newer load.
  Future<bool> _load(String path) async {
    // We now have a video, so the "load a video to join" prompt is moot (#60).
    if (_joinPrompt != null && mounted) setState(() => _joinPrompt = null);
    // This load's generation. A newer load bumps it; we abandon at every await
    // boundary below once we're no longer current, so a stale/slow load can't act
    // on a core state that now belongs to a different source.
    final gen = ++_loadGeneration;
    // Redacted name only (a URL's signed token must never hit disk). A "load"
    // line with no matching "opened"/"open failed" line localizes a load-time
    // freeze (#139) the old sync-only log couldn't see (#140).
    appLog('video: load ${mediaDisplayName(path)}');
    // Invalidate the accepted-source marker until this load is confirmed, so a
    // reconnect mid-load can't re-announce the previous source.
    _loadedSource = null;
    // Drop the previous file's byte size now, before the new load opens. Until
    // _recordOpen commits the new size, a stale positive size would let
    // _fileMismatchBanner / compareFiles judge match-by-size against a source
    // that never opened (compareFiles trusts equal sizes ahead of URL identity),
    // so the load/error screen could wrongly show a peer as matching.
    if (_localFileSizeBytes != null && mounted) {
      setState(() => _localFileSizeBytes = null);
    }
    await _core.load(path);
    // A source can fail asynchronously — mpv reports an unreachable / non-video
    // / expired URL, *and* a moved or unreadable local file, on its error stream
    // after load() returns. Don't record it to history, announce it to the room,
    // or post a "Loaded …" chat line until it actually opens, or a failed source
    // would surface to peers and history as loaded while we show the error
    // screen. Applies to local files too, not just URLs.
    final opened = await awaitOpenResult(_core, source: path);
    // Superseded while we awaited: a newer load owns the core now, so do nothing
    // here (no failLoad, no announce) — the newer load reports its own outcome.
    if (gen != _loadGeneration) {
      appLog('video: load superseded ${mediaDisplayName(path)}');
      return false;
    }
    if (!opened) {
      appLog('video: open failed ${mediaDisplayName(path)} (timed out)');
      // A load that never confirmed open must be surfaced as an error, or the
      // user is stuck on a frozen surface with no recovery buttons (those only
      // show on PlaybackStatus.error). This covers both a plain `loading` hang
      // and a source forced to `playing`/`paused` over a never-opened URL (e.g. a
      // peer heartbeat applying play() while we were still loading). Guard on the
      // path so we never force the error onto a different source, and `failLoad`
      // itself no-ops if the source did genuinely open.
      if (_core.state.filePath == path) {
        _core.failLoad('Timed out waiting for the video to open.');
      }
      return false;
    }
    if (!mounted || _core.state.filePath != path) return false;
    appLog('video: opened ${mediaDisplayName(path)}');
    final size = await _recordOpen(path);
    // _recordOpen awaits file-size/DB work; a newer load could have started and
    // swapped the core state (and _localFileSizeBytes) meanwhile.
    if (gen != _loadGeneration || !mounted) return false;
    _loadedSource = path;
    // Tell the sync bridge this source is confirmed open so its heartbeat
    // accepts the source's ticks — essential for a live/direct stream that never
    // reports a duration (the bridge can't infer "open" from such a stream).
    _bridge.markSourceOpen(path);
    _announceLoadedFile(path, sizeBytes: size);
    // `dispose()` doesn't bump the generation, so guard on `mounted` too.
    if (gen != _loadGeneration || !mounted) return false;
    // Compare against the peer's announced file once; both the chat line and the
    // over-video banner key off the same verdict so they can't contradict (#178).
    final match = compareFiles(
      localName: _core.state.fileName,
      localSize: _localFileSizeBytes,
      peerName: _peerFile?.name,
      peerSize: _peerFile?.sizeBytes,
    );
    _addLoadedFileMessage(match);
    // Brief over-video confirmation that the load landed and we're in sync with
    // a friend (the chat line is easy to miss on the video). Silent solo, while a
    // friend hasn't loaded yet, or on a mismatch — see [loadedInSyncNotice].
    final notice = loadedInSyncNotice(match: match);
    if (notice != null && mounted) {
      setState(() => _showTransientNotice(notice));
    }
    return true;
  }

  /// Append a "Loaded …" system line to chat. Shows "in sync!" when the peer's
  /// file matches ours; otherwise just names the file. Replaces the misleading
  /// "jumped to 00:00" that appeared on first load (#91).
  void _addLoadedFileMessage(FileMatch match) {
    final fileName = _core.state.fileName;
    if (fileName == null) return;
    // Match on the full name (URL identity); show the short label in chat.
    _chat.addSystem(
      loadedFileMessage(fileName: mediaDisplayName(fileName), match: match),
    );
  }

  Future<void> _resume(String path, int positionMs) async {
    // Only seek if this resume load actually opened and is still current —
    // otherwise a superseded/failed load would apply the old position to
    // whatever the user picked instead. seekWhenReady is also scoped to [path]
    // so a load that supersedes it during the duration-wait can't inherit this
    // resume position.
    if (await _load(path)) {
      await seekWhenReady(
        _core,
        Duration(milliseconds: positionMs),
        source: path,
      );
    }
  }

  Future<int> _recordOpen(String path) async {
    final state = _core.state;
    // A stream URL has no byte size — don't stat it as a file (the URL isn't a
    // valid path, and on Windows the ':' would throw a different error).
    final size = isHttpUrl(path) ? 0 : await _fileSize(path);
    // `_localFileSizeBytes` is the *current* file's size, used for the
    // file-match comparison. Only commit it while this load is still current —
    // a slow stat for a superseded file would otherwise overwrite the new
    // file's size and trigger a false mismatch against a peer on the same file.
    if (mounted && _core.state.filePath == path) {
      setState(() => _localFileSizeBytes = size);
    }
    // Best-effort + logged: a history write must never crash a load, and a
    // recordOpen line with no match localizes a DB stall (#140).
    try {
      await widget.history.recordOpen(
        filePath: path,
        fileName: state.fileName ?? path,
        fileSizeBytes: size,
        durationMs: state.duration.inMilliseconds,
        room: widget.config.room,
        username: widget.config.username,
        server: widget.config.server,
        port: widget.config.port,
      );
      appLog('db: recordOpen ok ${mediaDisplayName(path)}');
    } catch (e) {
      appLog(
        'db: recordOpen FAILED ${mediaDisplayName(path)}: ${redactUrls('$e')}',
      );
    }
    return size;
  }

  Future<void> _saveResumePosition() async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    // Only persist a resume point for a source that actually opened. A failed or
    // still-loading load leaves filePath set at position 0 (e.g. an expired URL
    // or a moved local file retried from history), and saving that would erase
    // the real saved position for that history row.
    if (!isPlaybackOpen(state)) return;
    // `trace:` — this runs every few seconds, so it's firehose kept only at
    // verbose; neat drops it (#140).
    try {
      await widget.history.updatePosition(
        filePath: path,
        positionMs: state.position.inMilliseconds,
        durationMs: state.duration.inMilliseconds,
      );
      if (appLogInstance?.level == LogLevel.verbose) {
        appLog(
          'trace: db updatePosition ${mediaDisplayName(path)} '
          '@${state.position.inMilliseconds}ms',
        );
      }
    } catch (e) {
      appLog(
        'db: updatePosition FAILED ${mediaDisplayName(path)}: ${redactUrls('$e')}',
      );
    }
  }

  Future<void> _leave() async {
    if (_leavingRoom) return;
    // setState so the banner clears this frame (see [_banner]) — the resume-save
    // await below holds the room on screen for up to 600ms before we pop.
    if (mounted) {
      setState(() => _leavingRoom = true);
    } else {
      _leavingRoom = true;
    }
    appLog('life: leave room (button)');
    _historyTimer?.cancel();
    if (isPlaybackOpen(_core.state)) {
      try {
        await _saveResumePosition().timeout(const Duration(milliseconds: 600));
      } on Object catch (e) {
        appLog('life: leave resume-save skipped: ${redactUrls('$e')}');
      }
    }
    final cleanup = _finishLeaveCleanup();
    if (mounted) Navigator.of(context).pop();
    appLog('life: returned to connect screen');
    unawaited(cleanup);
  }

  Future<void> _finishLeaveCleanup() async {
    try {
      await _sync.disconnect().timeout(const Duration(milliseconds: 800));
    } on Object catch (e) {
      appLog('life: leave disconnect cleanup skipped: ${redactUrls('$e')}');
    }
    try {
      await (_syncLog?.flush() ?? Future<void>.value()).timeout(
        const Duration(milliseconds: 500),
      );
    } on Object catch (e) {
      appLog('life: leave log flush skipped: ${redactUrls('$e')}');
    }
  }

  /// Whether the just-(re)connected room should be told about the current
  /// source — see [canAnnounceOnConnect] for the rule.
  bool _shouldReannounceOnConnect() => canAnnounceOnConnect(
    currentPath: _core.state.filePath,
    acceptedPath: _loadedSource,
    status: _core.state.status,
  );

  void _announceLoadedFile(String? path, {int? sizeBytes}) {
    if (path == null) return;
    // For a URL, size is unknown (streams have no byte length) and the URL
    // itself is the name we share — matching official Syncplay.
    if (_loadedSource != path || !mounted) return;
    final size = isHttpUrl(path) ? 0 : (sizeBytes ?? _localFileSizeBytes ?? 0);
    final state = _core.state;
    final fallbackName = isHttpUrl(path) ? path : mediaDisplayName(path);
    appLog('sync: announce file ${mediaDisplayName(path)}');
    _sync.announceFile(
      name: state.filePath == path
          ? (state.fileName ?? fallbackName)
          : fallbackName,
      size: size,
      duration: state.filePath == path ? state.duration : Duration.zero,
    );
  }

  /// Byte size of a local file, or 0 if it can't be read.
  Future<int> _fileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _browse() async {
    // A preflight or picker is already in flight: a second click would queue a
    // duplicate picker now that the preflight awaits before the modal opens
    // (#144 review).
    if (_browsing) return;
    _browsing = true;
    String? path;
    try {
      final typeGroup = XTypeGroup(
        label: 'Video',
        extensions: videoExtensions.toList(),
      );
      // Open the picker in a concrete local folder, never the Windows
      // Quick-access view whose recent/cloud scan can hang the
      // (UI-thread-blocking) dialog and freeze the whole app (#139).
      final initialDirectory = await _pickerInitialDirectory();
      // The preflight awaits (DB read + folder probes); if the screen went away
      // meanwhile, a stale click must not open a dialog or load into reset
      // state (#144 review).
      if (!mounted) return;
      final file = await openFile(
        acceptedTypeGroups: [typeGroup],
        initialDirectory: initialDirectory,
      );
      if (file == null || !mounted) return;
      path = file.path;
    } finally {
      // Release the guard once the picker closes — only the preflight+picker
      // window can queue a duplicate. Holding it through _load would block the
      // user from picking a replacement while a slow/stuck open runs, breaking
      // the load-generation supersede flow (#144 review r3).
      _browsing = false;
    }
    // Outside the guard: a newer browse may now supersede this load. `path` is
    // promoted non-null here — every no-file/unmounted branch above returns
    // inside the try (after the finally clears the guard).
    await _load(path);
  }

  /// Best-effort folder to open the file picker in (#139): the last-watched
  /// video's folder, else the most recent history entry's folder, else Videos /
  /// home.
  ///
  /// Each candidate is probed by [_isDirResponsive] before use. Existence alone
  /// is not enough: a history folder on a disconnected mapped drive or a
  /// cloud-backed (OneDrive) folder can still `exists()` yet stall when
  /// `IFileDialog::Show` synchronously navigates into it on the UI thread —
  /// reintroducing the freeze this fixes (#144 review). The probe runs off the
  /// UI isolate under a timeout, so a slow/stale candidate is skipped (never
  /// awaited to completion) and we fall through to the next, local one.
  Future<String?> _pickerInitialDirectory() async {
    String? recentFilePath;
    try {
      final recent = await widget.history
          .watchRecent(limit: 1)
          .first
          .timeout(const Duration(seconds: 1));
      if (recent.isNotEmpty) recentFilePath = recent.first.filePath;
    } catch (_) {
      // DB slow or unavailable — fall through to the env folders.
    }
    return resolvePickerInitialDirectory(
      lastLoadedFilePath: _loadedSource,
      recentFilePath: recentFilePath,
      environment: Platform.environment,
      isDirectoryUsable: _isDirResponsive,
    );
  }

  /// Whether [path] is a directory the file picker can open *without stalling*.
  ///
  /// We don't just check existence: a UNC / mapped-drive / cloud-backed folder
  /// can answer `exists()` but then hang the shell while it enumerates, which
  /// would freeze `IFileDialog::Show` on the UI thread (#144 review). So we
  /// actually enumerate one entry — `dart:io` async listing runs off the UI
  /// isolate, and the timeout caps a stalled folder so the UI never blocks. A
  /// folder that responds quickly here is one the picker can navigate quickly.
  /// A non-existent folder, a permission error, or a timeout all read as
  /// unusable.
  Future<bool> _isDirResponsive(String path) {
    return Directory(path)
        .list(followLinks: false)
        .isEmpty
        .then((_) => true)
        .timeout(const Duration(milliseconds: 800), onTimeout: () => false)
        .catchError((_) => false);
  }

  /// Prompt for a direct video link and load it through the same path as a
  /// local file. The URL is validated inside the dialog before it resolves.
  Future<void> _promptPasteLink() async {
    final url = await showPasteLinkDialog(context);
    if (url != null) await _load(url);
  }

  void _handleDropped(String path) {
    unawaited(_load(path));
  }

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
          if (event is KeyDownEvent &&
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
                    if (state.fileName == null)
                      EmptyState(
                        key: const ValueKey<String>('empty-state'),
                        onBrowse: _browse,
                        onLeave: () => unawaited(_leave()),
                        onLoadUrl: (url) => unawaited(_load(url)),
                        notice: _joinPrompt?.message,
                        onWatchPeerUrl: _joinPrompt?.url == null
                            ? null
                            : () => unawaited(_load(_joinPrompt!.url!)),
                      )
                    else if (state.status == PlaybackStatus.error)
                      VideoErrorState(
                        key: const ValueKey<String>('video-error'),
                        message: friendlyPlaybackError(
                          isUrl: isHttpUrl(state.filePath ?? ''),
                        ),
                        detail: state.errorMessage,
                        onBrowse: _browse,
                        onPasteLink: () => unawaited(_promptPasteLink()),
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
                    if (videoVisible)
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
                      // Transient notices (join/leave, throttled sync actions)
                      // are the banner's hottest source; they flow through
                      // their own notifier so a scrub burst dirties only this
                      // subtree (#196). A live notice wins over the derived
                      // banner; _leavingRoom (via _banner's guard) silences
                      // both.
                      child: ValueListenableBuilder<String?>(
                        valueListenable: _presenceNotice,
                        builder: (context, notice, _) => SyncHintBanner(
                          text: _leavingRoom || notice == null
                              ? _banner
                              : notice,
                        ),
                      ),
                    ),
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
                      onSend: _chat.send,
                      onTypingChanged: (t) => _chat.sendTyping(isTyping: t),
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
                        setState(
                          () => _chatLayout = _chatLayout.resetSize(),
                        );
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
                            onLoadVideo: _browse,
                            onPasteLink: () => unawaited(_promptPasteLink()),
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
                    if (videoVisible)
                      Positioned(
                        key: const ValueKey<String>('reaction-bar'),
                        right: 16,
                        bottom: 84,
                        child: AnimatedOpacity(
                          opacity: overlayOpacity(idle: _isUiIdle),
                          duration: Motion.base,
                          child: IgnorePointer(
                            ignoring: _isUiIdle,
                            child: ReactionBar(onReact: _chat.sendReaction),
                          ),
                        ),
                      ),
                    // Load-screen "Press Tab" hint — a self-fading bottom toast.
                    if (_chatHintToken != null)
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
