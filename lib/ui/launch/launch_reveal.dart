import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/spacing.dart';
import '../brand/meow_logo_mark.dart';
import '../brand/meow_wordmark.dart';
import 'launch_tips.dart';

/// The cold-start launch reveal. Overlays a one-shot splash — the active
/// theme's gradient washing in, the logo mark settling, the "MeowWatch"
/// wordmark easing in, and a late skip tip — over [child] (the lobby), then
/// dissolves as the lobby rises in behind it. Calls [onComplete] exactly once
/// when it settles, so the caller can sequence what comes next (e.g. the
/// post-update "What's new" modal) AFTER the animation rather than over it.
///
/// Skippable on any click or key. When [enabled] is false or the OS / app
/// "reduce motion" setting is on, the child is shown immediately and
/// [onComplete] fires after the first frame — no splash, no wait.
class LaunchReveal extends StatefulWidget {
  const LaunchReveal({
    required this.child,
    required this.onComplete,
    this.enabled = true,
    this.tip,
    super.key,
  });

  final Widget child;
  final VoidCallback onComplete;
  final bool enabled;

  /// The line shown late under the wordmark. Defaults to the skip hint.
  final String? tip;

  @override
  State<LaunchReveal> createState() => _LaunchRevealState();
}

class _LaunchRevealState extends State<LaunchReveal>
    with SingleTickerProviderStateMixin {
  // Built eagerly in initState (not lazily) so the vsync TickerMode lookup
  // happens while the element is active — the disabled / reduce-motion paths
  // never reference it in build, so a lazy field would first initialize inside
  // dispose() and throw "ancestor lookup is unsafe".
  late final AnimationController _c;
  final FocusNode _skipFocus = FocusNode(debugLabel: 'launch-reveal-skip');
  // A stable key for the lobby so it keeps its element (and State) when the
  // reveal settles. Without it, `build` swaps a Stack-wrapped child for the raw
  // child — a structural change that tears down and rebuilds the lobby, resetting
  // its StreamBuilders to empty and flashing a half-laid-out "mini" lobby for a
  // frame. With the key, Flutter reparents the same element instead.
  final GlobalKey _lobbyKey = GlobalKey(debugLabel: 'launch-reveal-lobby');
  bool _started = false;
  bool _done = false;

  // The one line shown under the wordmark this launch. Chosen once here — not in
  // build — so it stays put across the many per-frame rebuilds of the splash. An
  // explicit [LaunchReveal.tip] wins; otherwise we rotate the pool by a per-run
  // seed so successive launches show different nudges.
  late final String _tip;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Motion.reveal);
    _tip = widget.tip ?? launchTip(DateTime.now().microsecondsSinceEpoch);
  }

  // Timeline intervals over [Motion.reveal] (2800ms). The lockup assembles
  // mark-then-word, the tip lands by ~0.48 (~1.3s), then everything HOLDS
  // through a readable dwell until the dissolve begins at 0.80 (~2.24s) — so the
  // tip sits fully still for ~0.9s before it starts to fade. The mark enters on
  // the springy curve with a scale overshoot; the word eases in just behind it.
  static const _washIn = Interval(0.0, 0.11, curve: Motion.emphasized);
  static const _markIn = Interval(0.07, 0.33, curve: Motion.springy);
  static const _wordIn = Interval(0.15, 0.40, curve: Motion.emphasized);
  static const _tipIn = Interval(0.34, 0.48, curve: Motion.emphasized);
  static const _dissolve =
      Interval(0.80, 1.0, curve: Motion.emphasizedAccelerate);
  static const _lobbyRise = Interval(0.78, 1.0, curve: Motion.emphasized);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || context.reduceMotion) {
      _finishAfterFrame();
      return;
    }
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _c.forward();
  }

  void _finishAfterFrame() {
    // Skip the splash entirely, but still complete after a frame so callers
    // sequence the same way they would after a real reveal.
    _done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onComplete();
    });
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    widget.onComplete();
  }

  void _skip() {
    if (_done || _c.status == AnimationStatus.completed) return;
    // Jump quickly to the settled lobby rather than a hard cut.
    _c.animateTo(1.0,
        duration: Motion.fast, curve: Motion.emphasizedAccelerate);
  }

  @override
  void dispose() {
    _c.dispose();
    _skipFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same KeyedSubtree instance in both branches so the lobby element is
    // reparented (State preserved) when `_done` flips, not rebuilt.
    final lobby = KeyedSubtree(key: _lobbyKey, child: widget.child);
    if (_done) return lobby;
    final m = context.meow;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The lobby underneath, rising + fading in during the dissolve.
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = _lobbyRise.transform(_c.value);
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 16),
                child: child,
              ),
            );
          },
          child: lobby,
        ),
        // The splash overlay: tap/key anywhere skips.
        Positioned.fill(
          child: Focus(
            focusNode: _skipFocus,
            autofocus: true,
            onKeyEvent: (_, _) {
              _skip();
              return KeyEventResult.handled;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _skip,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final wash = _washIn.transform(_c.value);
                  final exit = _dissolve.transform(_c.value); // 0 → 1 leaving
                  return Opacity(
                    opacity: (1 - exit).clamp(0.0, 1.0), // splash fades out
                    child: Transform.scale(
                      // A gentle lift as it dissolves — the lockup floats up and
                      // away rather than just dropping its opacity.
                      scale: 1 + exit * 0.04,
                      child: _splash(m, wash),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _splash(MeowColors m, double wash) {
    final gradient = m.backgroundGradient;
    return DecoratedBox(
      key: const Key('launch-reveal-splash'),
      decoration: BoxDecoration(
        color: gradient == null
            ? Color.lerp(m.background.withValues(alpha: 0), m.background, wash)
            : null,
        gradient: gradient is LinearGradient
            ? LinearGradient(
                begin: gradient.begin,
                end: gradient.end,
                colors: [
                  for (final col in gradient.colors)
                    Color.lerp(col.withValues(alpha: 0), col, wash)!,
                ],
              )
            : gradient,
      ),
      // A transparent Material so the splash text renders normally — the
      // overlay is a Stack sibling of the lobby's Scaffold, so without this its
      // Text widgets fall back to the debug yellow-underline default style.
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mark — settles in with the springy character beat: scales up
              // from 0.82 with a slight overshoot past full size, then settles.
              _phase(
                _markIn,
                scaleFrom: 0.82,
                rise: 16,
                child: const MeowLogoMark(size: 88),
              ),
              const SizedBox(height: Spacing.lg),
              // Wordmark — eases in just behind the mark with a gentle scale, so
              // the lockup assembles with a little depth instead of flat-fading.
              _phase(
                _wordIn,
                scaleFrom: 0.94,
                rise: 12,
                child: const MeowWordmark(fontSize: 34),
              ),
              const SizedBox(height: Spacing.xxl),
              // Tip — fades in late so it never competes with the hero beat.
              _phase(
                _tipIn,
                rise: 6,
                child: Text(
                  _tip,
                  style: TextStyle(color: m.textDim, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fade + small rise (and optional scale) of one splash element, driven by its
  /// [interval]. With [scaleFrom] < 1 the element grows into place; on the
  /// springy curve `t` overshoots past 1 mid-flight, so the scale pops slightly
  /// past full size before settling — the lively "character" beat.
  Widget _phase(
    Interval interval, {
    required Widget child,
    double rise = 12,
    double scaleFrom = 1.0,
  }) {
    final t = interval.transform(_c.value);
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scaleFrom + (1 - scaleFrom) * t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * rise),
          child: child,
        ),
      ),
    );
  }
}
