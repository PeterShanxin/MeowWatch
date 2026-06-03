import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/update/update_service.dart';

/// Modal dialog for checking, downloading, and applying updates.
///
/// States: idle → checking → up-to-date / update-available →
///         downloading (progress) → ready-to-install → error
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, this.service});

  /// Injectable update service; defaults to a real [UpdateService]. Tests pass
  /// one backed by a mock HTTP client.
  final UpdateService? service;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  late final UpdateService _service = widget.service ?? UpdateService.instance;

  @override
  void initState() {
    super.initState();
    if (_service.phase == UpdatePhase.idle ||
        _service.phase == UpdatePhase.error ||
        _service.phase == UpdatePhase.upToDate) {
      _service.checkUpdateForDialog();
    }
  }

  @override
  void dispose() {
    if (widget.service != null) {
      _service.dispose();
    }
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    await _service.checkUpdateForDialog();
  }

  Future<void> _download() async {
    await _service.startDownload();
  }

  Future<void> _install() async {
    final path = _service.downloadedZipPath;
    if (path == null) return;
    await _service.applyUpdate(path);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Dialog(
      backgroundColor: m.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: m.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, minWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.system_update, color: m.accent, size: IconSizes.md),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      'MeowWatch Updates',
                      style: TextStyle(
                        color: m.textPrimary,
                        fontSize: TypeScale.title,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: m.textDim, size: IconSizes.md),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Current version: v$appVersion',
                style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
              ),
              const SizedBox(height: Spacing.xl),

              // Body — varies by phase
              ListenableBuilder(
                listenable: _service,
                builder: (context, _) => _buildBody(m),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(dynamic m) {
    switch (_service.phase) {
      case UpdatePhase.idle:
      case UpdatePhase.checking:
        return _statusRow(
          icon: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: m.accent as Color,
            ),
          ),
          text: 'Checking for updates…',
          m: m,
        );

      case UpdatePhase.upToDate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: Icon(Icons.check_circle, color: m.online as Color, size: IconSizes.md),
              text: 'You\'re up to date!',
              m: m,
              trailing: TextButton(
                onPressed: _checkForUpdate,
                child:
                    Text('Check again', style: TextStyle(color: m.accent as Color)),
              ),
            ),
            if (_service.changelog.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              Text(
                "What's new",
                style: TextStyle(
                  color: m.textDim as Color,
                  fontSize: TypeScale.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              _changelogPanel(m),
            ],
          ],
        );

      case UpdatePhase.updateAvailable:
        final info = _service.latestUpdate!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: Icon(Icons.new_releases, color: m.accent as Color, size: IconSizes.md),
              text: 'New version available: v${info.version}',
              m: m,
            ),
            if (_service.changelog.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              _changelogPanel(m),
            ] else if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: (m.background as Color).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: (m.border as Color).withValues(alpha: 0.5)),
                ),
                child: Text(
                  info.releaseNotes,
                  style: TextStyle(color: m.textDim as Color, fontSize: TypeScale.body),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download, size: IconSizes.md),
                label: const Text('Download Update'),
                style: FilledButton.styleFrom(
                  backgroundColor: m.accent as Color,
                  foregroundColor: m.background as Color,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                ),
                onPressed: _download,
              ),
            ),
          ],
        );

      case UpdatePhase.downloading:
        return DownloadProgressBody(
          hasTotal: _service.hasDownloadTotal,
          progress: _service.downloadProgress,
          receivedBytes: _service.downloadReceivedBytes,
        );

      case UpdatePhase.readyToInstall:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: Icon(Icons.check_circle, color: m.online as Color, size: IconSizes.md),
              text: 'Download complete!',
              m: m,
            ),
            const SizedBox(height: Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.restart_alt, size: IconSizes.md),
                label: const Text('Install & Restart'),
                style: FilledButton.styleFrom(
                  backgroundColor: m.accent as Color,
                  foregroundColor: m.background as Color,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                ),
                onPressed: _install,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'The app will close and reopen with the new version.',
              style: TextStyle(color: m.textDim as Color, fontSize: TypeScale.caption),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case UpdatePhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: const Icon(Icons.error_outline, color: Colors.redAccent, size: IconSizes.md),
              text: _service.errorMessage,
              m: m,
            ),
            const SizedBox(height: Spacing.md),
            TextButton(
              onPressed: _checkForUpdate,
              child: Text('Retry', style: TextStyle(color: m.accent as Color)),
            ),
          ],
        );
    }
  }

  /// Scrollable list of changelog entries (newest first). Shared by the
  /// update-available and up-to-date phases.
  Widget _changelogPanel(dynamic m) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: (m.background as Color).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: (m.border as Color).withValues(alpha: 0.5)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _service.changelog.length,
        separatorBuilder: (_, _) => Divider(
          height: Spacing.lg,
          color: (m.border as Color).withValues(alpha: 0.4),
        ),
        itemBuilder: (context, i) {
          final e = _service.changelog[i];
          final header =
              e.date.isEmpty ? 'v${e.version}' : 'v${e.version} · ${e.date}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                header,
                style: TextStyle(
                  color: m.textPrimary as Color,
                  fontSize: TypeScale.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                e.notes,
                style: TextStyle(color: m.textDim as Color, fontSize: TypeScale.body),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusRow({
    required Widget icon,
    required String text,
    required dynamic m,
    Widget? trailing,
  }) {
    return Row(
      children: [
        icon,
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Text(text, style: TextStyle(color: m.textPrimary as Color, fontSize: TypeScale.label)),
        ),
        ?trailing,
      ],
    );
  }
}

/// The downloading-phase body: a spinner + label and a progress bar. When the
/// server advertised no Content-Length ([hasTotal] false) the bar is
/// **indeterminate** and the label shows received bytes instead of a percentage,
/// so reopening the dialog mid-download never shows a frozen 0% (#63).
@visibleForTesting
class DownloadProgressBody extends StatelessWidget {
  const DownloadProgressBody({
    super.key,
    required this.hasTotal,
    required this.progress,
    required this.receivedBytes,
  });

  final bool hasTotal;
  final double progress;
  final int receivedBytes;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final label = hasTotal
        ? 'Downloading… ${(progress * 100).toStringAsFixed(0)}%'
        : 'Downloading… ${formatDownloadBytes(receivedBytes)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: m.accent),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.xs),
          child: LinearProgressIndicator(
            // null ⇒ indeterminate sweep when the total is unknown.
            value: hasTotal ? progress : null,
            minHeight: 6,
            backgroundColor: m.border,
            valueColor: AlwaysStoppedAnimation<Color>(m.accent),
          ),
        ),
      ],
    );
  }
}

/// Human-readable byte count for the indeterminate download label
/// ("3.4 MB", "512 KB", "900 B").
@visibleForTesting
String formatDownloadBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
