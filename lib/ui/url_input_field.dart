import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/video/video_url.dart';

/// A text field + "Load" button for pasting a direct video link. Validates with
/// [videoUrlError] before firing [onSubmit]; an invalid entry shows an inline
/// message and is never forwarded. Used on the empty/load screen and inside the
/// paste-link dialog so both share the same rules and chrome.
class UrlInputField extends StatefulWidget {
  const UrlInputField({
    required this.onSubmit,
    this.autofocus = false,
    super.key,
  });

  /// Called only with a validated, trimmed URL.
  final void Function(String url) onSubmit;
  final bool autofocus;

  @override
  State<UrlInputField> createState() => _UrlInputFieldState();
}

class _UrlInputFieldState extends State<UrlInputField> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text;
    final error = videoUrlError(raw);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);
    widget.onSubmit(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('url-input-field'),
                controller: _controller,
                autofocus: widget.autofocus,
                style: TextStyle(color: m.textPrimary),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onChanged: (_) {
                  // Clear a stale error as soon as the user edits, so the
                  // message can't linger over fresh input.
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'https://…/video.mp4',
                  hintStyle: TextStyle(color: m.textDim),
                  filled: true,
                  fillColor: m.surface,
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide(color: m.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide(color: m.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            OutlinedButton(
              key: const Key('url-load-button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: m.accent,
                side: BorderSide(color: m.accent),
              ),
              onPressed: _submit,
              child: const Text('Load'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            _error!,
            key: const Key('url-input-error'),
            style: TextStyle(color: m.error, fontSize: TypeScale.body),
          ),
        ],
      ],
    );
  }
}
