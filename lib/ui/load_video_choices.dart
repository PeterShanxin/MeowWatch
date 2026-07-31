import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import 'url_input_field.dart';

/// Heading shared by every "load a video" surface, so the card, the dialog and
/// the gear-menu item all name the same one feature (#222).
const String kLoadVideoTitle = 'Load a video';

/// Label of the local-file half of the choice.
const String kLoadFromComputerLabel = 'From my computer';

/// Caption under the link field — the paste path accepts page URLs since #123,
/// not just direct streams.
const String kLoadLinkCaption = 'YouTube, Bilibili, or a direct video link';

/// Which source the user picked.
enum LoadVideoSource { computer, link }

/// The outcome of [showLoadVideoDialog]: browse this computer, or a validated
/// link to load.
@immutable
class LoadVideoChoice {
  const LoadVideoChoice.computer()
    : source = LoadVideoSource.computer,
      url = null;

  const LoadVideoChoice.link(String this.url) : source = LoadVideoSource.link;

  final LoadVideoSource source;

  /// The validated, trimmed link. Non-null only for [LoadVideoSource.link].
  final String? url;
}

/// The two ways to load a video, presented as one feature (#222): pick a file
/// from this computer, or paste a link. Loading a link *is* loading a video, so
/// they sit under a single heading with equal weight instead of reading as two
/// unrelated features.
///
/// Shared body so the empty/load screen card and [showLoadVideoDialog] offer
/// exactly the same choices and copy — one place to change, no drift.
///
/// [onSubmitUrl] omitted (e.g. the design gallery) hides the link half and
/// leaves only the local-file button.
class LoadVideoChoices extends StatelessWidget {
  const LoadVideoChoices({
    required this.onBrowse,
    this.onSubmitUrl,
    this.urlFillColor,
    this.autofocusUrl = false,
    super.key,
  });

  final VoidCallback onBrowse;

  /// Called with a validated link. Null hides the link half entirely.
  final void Function(String url)? onSubmitUrl;

  /// Fill for the link field — pass the page background when this sits on a
  /// surface-colored card so the field doesn't blend into it.
  final Color? urlFillColor;

  final bool autofocusUrl;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('load-video-from-computer'),
          style: OutlinedButton.styleFrom(
            foregroundColor: m.accent,
            side: BorderSide(color: m.accent),
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          ),
          onPressed: onBrowse,
          icon: const Icon(Icons.folder_open, size: IconSizes.md),
          label: const Text(kLoadFromComputerLabel),
        ),
        if (onSubmitUrl != null) ...[
          const SizedBox(height: Spacing.lg),
          _OrDivider(color: m.border, textColor: m.textDim),
          const SizedBox(height: Spacing.lg),
          UrlInputField(
            onSubmit: onSubmitUrl!,
            autofocus: autofocusUrl,
            fillColor: urlFillColor,
            hintText: 'Paste a link…',
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            kLoadLinkCaption,
            style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
          ),
        ],
      ],
    );
  }
}

/// A hairline rule either side of a small "or" — the two choices are peers, so
/// neither reads as the fallback of the other.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.color, required this.textColor});

  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: color, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Text(
            'or',
            style: TextStyle(color: textColor, fontSize: TypeScale.body),
          ),
        ),
        Expanded(child: Divider(color: color, height: 1)),
      ],
    );
  }
}

/// Ask which source to load from, for the compact surfaces that have no room
/// for the full card — the gear menu and the load-error screen (#222). Resolves
/// to the picked [LoadVideoChoice], or null if dismissed.
Future<LoadVideoChoice?> showLoadVideoDialog(BuildContext context) {
  return showDialog<LoadVideoChoice>(
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
          kLoadVideoTitle,
          style: TextStyle(color: m.textPrimary, fontSize: TypeScale.title),
        ),
        content: SizedBox(
          width: 420,
          child: LoadVideoChoices(
            onBrowse: () =>
                Navigator.of(context).pop(const LoadVideoChoice.computer()),
            onSubmitUrl: (url) =>
                Navigator.of(context).pop(LoadVideoChoice.link(url)),
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
