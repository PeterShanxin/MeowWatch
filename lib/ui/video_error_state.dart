import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import 'load_video_choices.dart';
import 'motion/reveal_in.dart';

/// Shown in place of the video when a load fails, so a bad link or unreadable
/// file never leaves a silent black/frozen screen. Offers a way straight back
/// to picking another source.
class VideoErrorState extends StatelessWidget {
  const VideoErrorState({
    required this.message,
    required this.onLoadVideo,
    this.onRetry,
    this.detail,
    this.attempt = 0,
    super.key,
  });

  /// Friendly, human-readable explanation of what went wrong.
  final String message;

  /// The raw underlying error (e.g. mpv's message), shown small for debugging.
  final String? detail;

  /// Opens the load-video chooser (local file or link) — one entry, matching
  /// the load screen and the gear menu (#222).
  final VoidCallback onLoadVideo;

  /// Re-attempt the same source. Shown as a "Try again" button when non-null —
  /// most load failures (a network blip, a slow CDN) clear on a plain retry, so
  /// the user shouldn't have to re-pick or re-paste the link by hand.
  final VoidCallback? onRetry;

  /// How many loads have failed so far. A repeat failure from an already-failed
  /// state can land on a *visually identical* screen — same generic headline,
  /// same buttons — so nothing tells the user their new attempt was even tried
  /// (#232). Bumping this replays the reveal, making each failure an event you
  /// can see. It is deliberately not shown as a number.
  final int attempt;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Container(
      color: m.background,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.xl),
        // Keyed on the attempt so a new failure remounts the reveal and animates
        // in again, instead of silently re-rendering the same pixels.
        child: RevealIn(
          key: ValueKey<int>(attempt),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: m.error.withValues(alpha: 0.9),
              ),
              const SizedBox(height: Spacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  message,
                  key: const Key('video-error-message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: m.textPrimary,
                    fontSize: TypeScale.title,
                  ),
                ),
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: Spacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Text(
                    detail!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: m.textDim,
                      fontSize: TypeScale.body,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Spacing.xxl),
              Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.md,
                alignment: WrapAlignment.center,
                children: [
                  if (onRetry != null)
                    OutlinedButton.icon(
                      key: const Key('video-error-retry'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: m.accent,
                        side: BorderSide(color: m.accent),
                      ),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: IconSizes.md),
                      label: const Text('Try again'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('video-error-load'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: m.accent,
                      side: BorderSide(color: m.accent),
                    ),
                    onPressed: onLoadVideo,
                    icon: const Icon(
                      Icons.video_library_outlined,
                      size: IconSizes.md,
                    ),
                    label: const Text(kLoadVideoTitle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
