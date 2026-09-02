part of 'home_screen.dart';

/// The UI idle/dim state machine seam of [_HomeScreenState] (#182): two idle
/// stages (controls fade out, then the dimmed chat ghost fades out too), the
/// throttled re-arm on high-frequency pointer traffic, and the chat wake path.
mixin _HomeIdleState on _HomeScreenStateBase {
  bool _isUiIdle = false;
  Timer? _uiIdleTimer;
  StreamSubscription<PlaybackState>? _playbackWakeSub;

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

  /// Clears idle when playback stops (EOF, pause). Lives outside the
  /// collaboration subscription lifecycle so a local session keeps it.
  void _initPlaybackWakeSubscription() {
    _playbackWakeSub = _core.stateStream.listen((s) {
      if (!mounted) return;
      if ((_isUiIdle || _isUiDeepIdle) && s.status != PlaybackStatus.playing) {
        _uiDeepIdleTimer?.cancel();
        setState(() {
          _isUiIdle = false;
          _isUiDeepIdle = false;
        });
      }
    });
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
}
