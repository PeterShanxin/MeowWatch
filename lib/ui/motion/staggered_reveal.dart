import 'package:flutter/material.dart';

import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';
import 'reveal_in.dart';

/// A one-shot, top-to-bottom entrance cascade for a column of [children].
///
/// When [play] turns true it ripples each child in with a staggered [RevealIn]
/// (fade + small rise), once. Before [play] the children are either held
/// invisible ([holdHidden] true — used while the launch reveal still covers
/// them, so the cascade reads as a clean *second* beat) or shown present
/// ([holdHidden] false — the no-reveal case: tests, or returning to the lobby).
/// Reduce motion shows every child present instantly, ignoring [play].
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    required this.play,
    required this.children,
    this.holdHidden = false,
    this.stagger = Motion.stagger,
    this.itemDuration = Motion.expressive,
    this.offset = 20,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    super.key,
  });

  final bool play;
  final bool holdHidden;
  final List<Widget> children;
  final Duration stagger;
  final Duration itemDuration;
  final double offset;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _started = widget.play;
  }

  @override
  void didUpdateWidget(StaggeredReveal old) {
    super.didUpdateWidget(old);
    // Latch on the rising edge of [play]; the framework rebuilds us right after.
    if (!_started && widget.play) _started = true;
  }

  Widget _column(List<Widget> children) => Column(
        crossAxisAlignment: widget.crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );

  @override
  Widget build(BuildContext context) {
    // Present instantly: reduce motion, or not-yet-playing in the no-reveal case.
    if (context.reduceMotion || (!_started && !widget.holdHidden)) {
      return _column(widget.children);
    }
    // One stable tree from the held state through the cascade, so stateful
    // descendants (e.g. the continue-watching StreamBuilder) survive the
    // hidden->playing handoff instead of being torn down and repopulating from
    // their initialData. Each RevealIn holds its child invisible until [play]
    // ([_started]), then ripples it in, staggered top-to-bottom.
    return _column([
      for (var i = 0; i < widget.children.length; i++)
        RevealIn(
          play: _started,
          delay: widget.stagger * i,
          offset: widget.offset,
          duration: widget.itemDuration,
          child: widget.children[i],
        ),
    ]);
  }
}
