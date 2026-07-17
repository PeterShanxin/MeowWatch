import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/motion.dart';

/// Pop-in scale for a reaction burst at animation progress [t] (0..1). It
/// overshoots past 1.0 — the one squash-&-stretch beat the app allows
/// ([Motion.elasticPop]) — then settles to 1.0. The pop happens in the first
/// quarter of the rise. Reduce motion skips this path entirely (the burst is
/// presented settled), so there's no reduce-motion variant here.
double reactionPopScale(double t) {
  final pop = (t / 0.25).clamp(0.0, 1.0);
  return Motion.elasticPop.transform(pop);
}

/// Horizontal arc drift at progress [t] (0..1): the emoji eases sideways toward
/// [drift] as it rises, tracing an arc rather than a straight vertical line.
double reactionArcX(double t, double drift) =>
    drift * Curves.easeOut.transform(t.clamp(0.0, 1.0));

/// Overlay that renders emoji "reactions" floating up over the video, like a
/// live-stream's heart burst. Each emoji pushed onto [emojis] spawns one
/// rising, fading, gently swaying glyph that removes itself when done.
class FloatingReactionsOverlay extends StatefulWidget {
  const FloatingReactionsOverlay({required this.emojis, super.key});

  /// Each event is an emoji string to launch.
  final Stream<String> emojis;

  @override
  State<FloatingReactionsOverlay> createState() =>
      _FloatingReactionsOverlayState();
}

class _FloatingReactionsOverlayState extends State<FloatingReactionsOverlay> {
  StreamSubscription<String>? _sub;
  final List<_Reaction> _active = <_Reaction>[];
  int _nextId = 0;

  // Deterministic-enough horizontal scatter without Math.random (which is
  // unavailable in some harnesses): cycle a few offsets.
  static const _laneFractions = <double>[0.30, 0.5, 0.70, 0.42, 0.6];
  int _lane = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.emojis.listen(_launch);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _launch(String emoji) {
    if (!mounted) return;
    final id = _nextId++;
    final lane = _laneFractions[_lane % _laneFractions.length];
    _lane++;
    setState(() => _active.add(_Reaction(id: id, emoji: emoji, lane: lane)));
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _active.removeWhere((r) => r.id == id));
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: bursts animate every frame; without it each frame
    // dirties the full-screen layer this overlay sits above (#199).
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                for (final r in _active)
                  _FloatingEmoji(
                    key: ValueKey<int>(r.id),
                    emoji: r.emoji,
                    startLeft: constraints.maxWidth * r.lane,
                    riseBy: constraints.maxHeight * 0.45,
                    // Lanes left of centre drift left, right drift right — a
                    // gentle fountain spread instead of every burst rising
                    // dead straight.
                    arcDrift: (r.lane - 0.5) * constraints.maxWidth * 0.30,
                    onDone: () => _remove(r.id),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Reaction {
  const _Reaction({required this.id, required this.emoji, required this.lane});
  final int id;
  final String emoji;
  final double lane;
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({
    required this.emoji,
    required this.startLeft,
    required this.riseBy,
    required this.arcDrift,
    required this.onDone,
    super.key,
  });

  final String emoji;
  final double startLeft;
  final double riseBy;
  final double arcDrift;
  final VoidCallback onDone;

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    // Hold fully opaque until 85% of the rise, then fade linearly out — the
    // same shape the old per-frame `Opacity(opacity: …)` math produced, but
    // driven through FadeTransition so the compositor animates the layer's
    // alpha instead of a fresh Opacity widget forcing a saveLayer per emoji
    // per frame (#199).
    _fade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.85, 1.0)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) {
      // Reduce motion: present the reaction settled — no rise, pop, drift, or
      // fade. The controller still runs purely to schedule onDone (self-removal),
      // so the burst appears, holds, and clears without any animated movement.
      return Positioned(
        left: widget.startLeft,
        bottom: 90,
        child:
            Text(widget.emoji, style: const TextStyle(fontSize: Glyphs.burst)),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Rise straight up, drift sideways along an arc, and pop in with an
        // elastic overshoot (the one squash-&-stretch beat). The end-of-rise
        // fade lives in the static [_fade]-driven child below.
        final rise = widget.riseBy * t;
        final drift = reactionArcX(t, widget.arcDrift);
        final scale = reactionPopScale(t);
        return Positioned(
          left: widget.startLeft + drift,
          bottom: 90 + rise,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: FadeTransition(
        opacity: _fade,
        child:
            Text(widget.emoji, style: const TextStyle(fontSize: Glyphs.burst)),
      ),
    );
  }
}
