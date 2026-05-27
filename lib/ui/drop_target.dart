import 'package:desktop_drop/desktop_drop.dart' as dd;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

const _videoExtensions = <String>{
  '.mkv', '.mp4', '.avi', '.webm', '.mov', '.m4v', '.flv', '.ts', '.mpg', '.mpeg',
};

bool isVideoFile(String path) {
  return _videoExtensions.contains(p.extension(path).toLowerCase());
}

class VideoDropTarget extends StatelessWidget {
  const VideoDropTarget({
    required this.child,
    required this.onFileDropped,
    super.key,
  });

  final Widget child;
  final void Function(String path) onFileDropped;

  @override
  Widget build(BuildContext context) {
    return dd.DropTarget(
      onDragDone: (detail) {
        for (final file in detail.files) {
          if (isVideoFile(file.path)) {
            onFileDropped(file.path);
            return;
          }
        }
      },
      child: child,
    );
  }
}
