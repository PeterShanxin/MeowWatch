import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/video/media_kit_video_core.dart';

class VideoSurface extends StatefulWidget {
  const VideoSurface({required this.core, super.key});

  final MediaKitVideoCore core;

  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  late final VideoController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = VideoController(widget.core.player);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final core = widget.core;
    final s = core.state;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      core.togglePlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      core.seek(s.position + const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      core.seek(s.position - const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      core.setVolume((s.volume + 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      core.setVolume((s.volume - 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      autofocus: true,
      child: Container(
        color: Colors.black,
        child: Video(controller: _controller),
      ),
    );
  }
}
