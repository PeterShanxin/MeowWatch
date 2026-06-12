import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import 'url_input_field.dart';

/// Prompt for a direct video link and resolve to the validated URL, or `null`
/// if the user dismisses. Reuses [UrlInputField] so the paste/validation rules
/// match the empty-screen entry point.
Future<String?> showPasteLinkDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      final m = context.meow;
      return AlertDialog(
        backgroundColor: m.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: m.border),
        ),
        title: Text(
          'Paste a video link',
          style: TextStyle(color: m.textPrimary, fontSize: TypeScale.title),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A direct video file or stream (e.g. a .mp4 or .m3u8 URL).',
                style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
              ),
              const SizedBox(height: Spacing.lg),
              UrlInputField(
                autofocus: true,
                onSubmit: (url) => Navigator.of(context).pop(url),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: m.textDim),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
