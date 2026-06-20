import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/update/update_availability.dart';
import '../core/update/update_service.dart';
import 'gallery/design_gallery.dart';
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
    updateAvailable.value = false;
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

    final service = widget.serviceFactory?.call() ?? UpdateService.instance;
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
        updateAvailable.value = true;
        if (mounted) {
          setState(() {});
          _showUpdateToast();
        }
      }
    } finally {
      _checkInFlight = false;
      if (widget.serviceFactory != null) service.dispose();
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
        // Explicit cross so the notice can be dismissed on demand, not only by
        // waiting out the auto-timeout (#61). The once-per-session check means
        // it won't pop back up after being closed.
        showCloseIcon: true,
        closeIconColor: m.textDim,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.new_releases, size: IconSizes.md, color: m.accent),
            const SizedBox(width: Spacing.md),
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

  // Hidden entry to the design-system gallery. Long-press (not tap, which is
  // taken by the update dialog) so it never fires by accident and there is no
  // visible menu item. Also reachable via MEOWWATCH_GALLERY=1 (see main.dart).
  void _openGallery() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DesignGallery()),
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
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: _openDialog,
          onLongPress: _openGallery,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: Spacing.xs),
            decoration: BoxDecoration(
              color: m.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: m.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pets, size: 12, color: m.textDim),
                const SizedBox(width: Spacing.xs),
                Text(
                  'v$appVersion',
                  style: TextStyle(
                    color: m.textDim,
                    fontSize: TypeScale.caption,
                    fontWeight: TypeScale.medium,
                    letterSpacing: 0.3,
                  ),
                ),
                if (_hasUpdate) ...[
                  const SizedBox(width: Spacing.sm),
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
