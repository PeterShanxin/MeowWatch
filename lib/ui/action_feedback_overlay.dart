import 'package:flutter/material.dart';

import 'playback_action.dart';

/// Flashes a translucent icon in the center of the video when an action is
/// triggered, then fades + scales out — like the play/pause feedback in
/// YouTube or mpv.
///
/// Drive it by passing the latest [action] together with a monotonically
/// increasing [trigger]. Bumping [trigger] replays the animation even when the
/// same action repeats (e.g. two pauses in a row).
class ActionFeedbackOverlay extends StatefulWidget {
  const ActionFeedbackOverlay({
    required this.action,
    required this.trigger,
    super.key,
  });

  final PlaybackAction? action;
  final int trigger;

  @override
  State<ActionFeedbackOverlay> createState() => _ActionFeedbackOverlayState();
}

class _ActionFeedbackOverlayState extends State<ActionFeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void didUpdateWidget(ActionFeedbackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.action != null) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    if (action == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            if (t == 0 || t == 1) return const SizedBox.shrink();
            final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.85;
            final scale = 0.7 + t * 0.5;
            return Opacity(
              opacity: opacity,
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: Color(0x99000000),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconForAction(action),
              size: 56,
              color: const Color(0xFFF5E6D3),
            ),
          ),
        ),
      ),
    );
  }
}
