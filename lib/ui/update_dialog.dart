import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/theme/meow_context.dart';
import '../core/update/update_service.dart';

/// Modal dialog for checking, downloading, and applying updates.
///
/// States: idle → checking → up-to-date / update-available →
///         downloading (progress) → ready-to-install → error
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdatePhase {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  error,
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _service = UpdateService();
  _UpdatePhase _phase = _UpdatePhase.idle;
  double _downloadProgress = 0;
  String? _downloadedZipPath;
  String _errorMessage = '';
  List<ChangelogEntry> _changelog = const [];

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    setState(() => _phase = _UpdatePhase.checking);
    final status = await _service.checkForUpdate();
    if (!mounted) return;
    switch (status) {
      case UpdateStatus.upToDate:
        setState(() => _phase = _UpdatePhase.upToDate);
      case UpdateStatus.updateAvailable:
        final changelog = await _service.fetchChangelog();
        if (!mounted) return;
        setState(() {
          _changelog = changelog;
          _phase = _UpdatePhase.updateAvailable;
        });
      case UpdateStatus.checkFailed:
        setState(() {
          _phase = _UpdatePhase.error;
          _errorMessage = 'Could not reach update server.\nCheck your connection and try again.';
        });
    }
  }

  Future<void> _download() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _downloadProgress = 0;
    });
    try {
      final path = await _service.downloadUpdate((p) {
        if (mounted) setState(() => _downloadProgress = p);
      });
      if (!mounted) return;
      setState(() {
        _downloadedZipPath = path;
        _phase = _UpdatePhase.readyToInstall;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = 'Download failed: $e';
      });
    }
  }

  Future<void> _install() async {
    final path = _downloadedZipPath;
    if (path == null) return;
    await _service.applyUpdate(path);
    // applyUpdate calls exit(0), so we never reach here.
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Dialog(
      backgroundColor: m.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: m.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, minWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.system_update, color: m.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'MeowWatch Updates',
                      style: TextStyle(
                        color: m.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: m.textDim, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Current version: v$appVersion',
                style: TextStyle(color: m.textDim, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // Body — varies by phase
              _buildBody(m),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(dynamic m) {
    switch (_phase) {
      case _UpdatePhase.idle:
      case _UpdatePhase.checking:
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

      case _UpdatePhase.upToDate:
        return _statusRow(
          icon: Icon(Icons.check_circle, color: m.online as Color, size: 20),
          text: 'You\'re up to date!',
          m: m,
          trailing: TextButton(
            onPressed: _checkForUpdate,
            child: Text('Check again', style: TextStyle(color: m.accent as Color)),
          ),
        );

      case _UpdatePhase.updateAvailable:
        final info = _service.latestUpdate!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: Icon(Icons.new_releases, color: m.accent as Color, size: 20),
              text: 'New version available: v${info.version}',
              m: m,
            ),
            if (_changelog.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (m.background as Color).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (m.border as Color).withValues(alpha: 0.5)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _changelog.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 16,
                    color: (m.border as Color).withValues(alpha: 0.4),
                  ),
                  itemBuilder: (context, i) {
                    final e = _changelog[i];
                    final header =
                        e.date.isEmpty ? 'v${e.version}' : 'v${e.version} · ${e.date}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          header,
                          style: TextStyle(
                            color: m.textPrimary as Color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.notes,
                          style: TextStyle(color: m.textDim as Color, fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ] else if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (m.background as Color).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (m.border as Color).withValues(alpha: 0.5)),
                ),
                child: Text(
                  info.releaseNotes,
                  style: TextStyle(color: m.textDim as Color, fontSize: 12),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download Update'),
                style: FilledButton.styleFrom(
                  backgroundColor: m.accent as Color,
                  foregroundColor: m.background as Color,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _download,
              ),
            ),
          ],
        );

      case _UpdatePhase.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: m.accent as Color,
                ),
              ),
              text: 'Downloading… ${(_downloadProgress * 100).toStringAsFixed(0)}%',
              m: m,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 6,
                backgroundColor: m.border as Color,
                valueColor: AlwaysStoppedAnimation<Color>(m.accent as Color),
              ),
            ),
          ],
        );

      case _UpdatePhase.readyToInstall:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: Icon(Icons.check_circle, color: m.online as Color, size: 20),
              text: 'Download complete!',
              m: m,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Install & Restart'),
                style: FilledButton.styleFrom(
                  backgroundColor: m.accent as Color,
                  foregroundColor: m.background as Color,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _install,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The app will close and reopen with the new version.',
              style: TextStyle(color: m.textDim as Color, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case _UpdatePhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusRow(
              icon: const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
              text: _errorMessage,
              m: m,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _checkForUpdate,
              child: Text('Retry', style: TextStyle(color: m.accent as Color)),
            ),
          ],
        );
    }
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
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: m.textPrimary as Color, fontSize: 14)),
        ),
        ?trailing,
      ],
    );
  }
}
