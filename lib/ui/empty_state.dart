import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import 'idle_mascot.dart';
import 'url_input_field.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.onBrowse,
    this.onLoadUrl,
    this.onLeave,
    this.notice,
    this.onWatchPeerUrl,
    super.key,
  });

  final VoidCallback onBrowse;
  final VoidCallback? onLeave;

  /// Loads a pasted direct video link. When non-null an "or paste a link" field
  /// is shown beneath Browse; omitted (e.g. in the design gallery) it's hidden.
  final void Function(String url)? onLoadUrl;

  /// Optional heads-up shown above the prompt, e.g. "lin started playback —
  /// load a video to join" when a friend is already watching (#60).
  final String? notice;

  /// One-click "Watch this too" action for a peer-URL join offer (#121): a
  /// friend loaded a direct link and we haven't loaded anything, so [notice]
  /// already names the link and this button loads it with no clipboard step.
  /// Non-null only alongside such a [notice]; the button is hidden otherwise
  /// (a local-file or play-triggered notice has no in-app action to offer).
  final VoidCallback? onWatchPeerUrl;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Container(
      color: m.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.xl),
          child: ConstrainedBox(
            // Keep the load controls in one cohesive, centered card so they read
            // as a single intentional element — clearly separate from the chat
            // overlay docked in the corner, rather than loose widgets that crowd
            // it.
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.xxl,
                vertical: Spacing.xxl,
              ),
              decoration: BoxDecoration(
                color: m.surface,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: m.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (notice != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                        vertical: Spacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: m.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(Radii.xl),
                        border: Border.all(color: m.accent),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '🐾 $notice',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: m.textPrimary,
                              fontSize: TypeScale.label,
                            ),
                          ),
                          if (onWatchPeerUrl != null) ...[
                            const SizedBox(height: Spacing.sm),
                            OutlinedButton(
                              key: const Key('join-prompt-watch-button'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: m.accent,
                                side: BorderSide(color: m.accent),
                              ),
                              onPressed: onWatchPeerUrl,
                              child: const Text('Watch this too'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                  const IdleMascot(size: 104),
                  const SizedBox(height: Spacing.xl),
                  Text(
                    'Drop a video file to start',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: m.textPrimary,
                      fontSize: TypeScale.title,
                    ),
                  ),
                  const SizedBox(height: Spacing.xxl),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: m.accent,
                      side: BorderSide(color: m.accent),
                    ),
                    onPressed: onBrowse,
                    child: const Text('Browse…'),
                  ),
                  if (onLeave != null) ...[
                    const SizedBox(height: Spacing.md),
                    TextButton.icon(
                      key: const Key('empty-state-leave'),
                      style: TextButton.styleFrom(foregroundColor: m.textDim),
                      onPressed: onLeave,
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Leave room'),
                    ),
                  ],
                  if (onLoadUrl != null) ...[
                    const SizedBox(height: Spacing.xl),
                    Text(
                      'or paste a direct video link',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: m.textDim,
                        fontSize: TypeScale.body,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    // Page-background fill so the field stands out against the
                    // surface-colored card instead of blending into it.
                    UrlInputField(
                      onSubmit: onLoadUrl!,
                      fillColor: m.background,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
