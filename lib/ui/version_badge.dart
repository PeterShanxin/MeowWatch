import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/theme/meow_context.dart';
import '../core/update/update_service.dart';
import 'update_dialog.dart';

/// Bright amber for the "update available" dot — deliberately punchier than the
/// muted cozy accent so it reads as a notification, not chrome.
const Color _updateDotColor = Colors.amber;

/// A subtle version chip anchored to the bottom-right of a parent [Stack].
///
/// Tapping it opens the [UpdateDialog] to check for and apply updates.
/// On first mount per session, silently checks for an update and, if one is
/// available, badges the chip with a dot and shows a tappable toast.
class VersionBadge extends StatefulWidget {
  const VersionBadge({super.key, this.serviceFactory});

  /// Injectable factory for the update service; defaults to a real
  /// [UpdateService]. Tests pass one backed by a mock HTTP client so the silent
  /// check is deterministic and never touches the network.
  final UpdateService Function()? serviceFactory;

  /// Reset the process-wide once-per-session check state. Tests only — keeps
  /// each test order-independent despite the static flags below.
  @visibleForTesting
  static void resetForTest() {
    _VersionBadgeState._checkedThisSession = false;
    _VersionBadgeState._checkInFlight = false;
    _VersionBadgeState._hasUpdate = false;
  }

  @override
  State<VersionBadge> createState() => _VersionBadgeState();
}

class _VersionBadgeState extends State<VersionBadge> {
  // Session-global so the result survives the badge unmounting (it lives only
  // on the connect screen, which is torn down when the user joins a room).
  static bool _checkedThisSession = false;
  static bool _checkInFlight = false;
  static bool _hasUpdate = false;

  @override
  void initState() {
    super.initState();
    _silentCheck();
  }

  Future<void> _silentCheck() async {
    if (_checkedThisSession || _checkInFlight) return;
    _checkInFlight = true;

    final service = widget.serviceFactory?.call() ?? UpdateService();
    try {
      final status = await service.checkForUpdate();
      // A failed check (e.g. offline at launch) does NOT consume the
      // once-per-session slot, so returning to the connect screen retries.
      if (status == UpdateStatus.checkFailed) return;
      _checkedThisSession = true;

      if (status == UpdateStatus.updateAvailable) {
        // Record the fact unconditionally — even if we've already unmounted,
        // a later badge mount must still show the dot this session.
        _hasUpdate = true;
        if (mounted) {
          setState(() {});
          _showUpdateToast();
        }
      }
    } finally {
      _checkInFlight = false;
      service.dispose();
    }
  }

  void _showUpdateToast() {
    if (!mounted) return;
    final m = context.meow;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: m.surface,
        duration: const Duration(seconds: 6),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.new_releases, size: 18, color: m.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '🐾 New version available!',
                style: TextStyle(color: m.textPrimary),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Update',
          textColor: m.accent,
          onPressed: _openDialog,
        ),
      ),
    );
  }

  void _openDialog() {
    if (!mounted) return;
    // Clear the dot when they open the dialog.
    if (_hasUpdate) {
      setState(() => _hasUpdate = false);
    }
    showDialog<void>(
      context: context,
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Tooltip(
      message: "Updates & what's new",
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: m.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: m.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pets, size: 12, color: m.textDim),
                const SizedBox(width: 5),
                Text(
                  'v$appVersion',
                  style: TextStyle(
                    color: m.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                if (_hasUpdate) ...[
                  const SizedBox(width: 6),
                  Container(
                    key: const Key('version-badge-update-dot'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _updateDotColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _updateDotColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
