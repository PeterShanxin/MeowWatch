import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'video_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MediaKitVideoCore _core;

  @override
  void initState() {
    super.initState();
    _core = MediaKitVideoCore();
  }

  @override
  void dispose() {
    unawaited(_core.dispose());
    super.dispose();
  }

  Future<void> _loadAndPlay(String path) async {
    await _core.load(path);
    await _core.play();
  }

  Future<void> _browse() async {
    const typeGroup = XTypeGroup(
      label: 'Video',
      extensions: ['mkv', 'mp4', 'avi', 'webm', 'mov', 'm4v'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await _loadAndPlay(file.path);
    }
  }

  void _handleDropped(String path) {
    unawaited(_loadAndPlay(path));
  }

  @override
  Widget build(BuildContext context) {
    return VideoDropTarget(
      onFileDropped: _handleDropped,
      child: StreamBuilder<PlaybackState>(
        stream: _core.stateStream,
        initialData: _core.state,
        builder: (context, snapshot) {
          final state = snapshot.data!;
          if (state.fileName == null) {
            return EmptyState(onBrowse: _browse);
          }
          return VideoSurface(core: _core);
        },
      ),
    );
  }
}
