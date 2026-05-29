import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    return IgnorePointer(
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
                  onDone: () => _remove(r.id),
                ),
            ],
          );
        },
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
    required this.onDone,
    super.key,
  });

  final String emoji;
  final double startLeft;
  final double riseBy;
  final VoidCallback onDone;

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Rise, fade out near the end, pop-in scale at the start, gentle sway.
        final rise = widget.riseBy * t;
        final sway = math.sin(t * math.pi * 3) * 14;
        final opacity = t < 0.85 ? 1.0 : (1.0 - (t - 0.85) / 0.15);
        final scale = t < 0.18 ? (t / 0.18) : 1.0;
        return Positioned(
          left: widget.startLeft + sway,
          bottom: 90 + rise,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: Text(widget.emoji, style: const TextStyle(fontSize: 34)),
            ),
          ),
        );
      },
    );
  }
}
