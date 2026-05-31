import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/theme/meow_context.dart';
import '../core/update/update_service.dart';
import 'update_dialog.dart';

/// A subtle version chip anchored to the bottom-right of a parent [Stack].
///
/// Tapping it opens the [UpdateDialog] to check for and apply updates.
/// On first mount per session, silently checks for an update.
class VersionBadge extends StatefulWidget {
  const VersionBadge({super.key});

  @override
  State<VersionBadge> createState() => _VersionBadgeState();
}

class _VersionBadgeState extends State<VersionBadge> {
  static DateTime? _lastCheckTime;
  static bool _hasUpdate = false;

  @override
  void initState() {
    super.initState();
    _silentCheck();
  }

  Future<void> _silentCheck() async {
    if (_lastCheckTime != null) return; // Only once per session
    _lastCheckTime = DateTime.now();

    final service = UpdateService();
    try {
      final status = await service.checkForUpdate();
      if (status == UpdateStatus.updateAvailable && mounted) {
        setState(() {
          _hasUpdate = true;
        });
        _showUpdateToast();
      }
    } finally {
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
        duration: const Duration(seconds: 5),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.new_releases, size: 18, color: m.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '🐾 New version available! Click to update.',
                style: TextStyle(color: m.textPrimary),
              ),
            ),
          ],
        ),
      ),
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
          onTap: () {
            // Clear the dot when they open the dialog
            if (_hasUpdate) {
              setState(() => _hasUpdate = false);
            }
            showDialog<void>(
              context: context,
              builder: (_) => const UpdateDialog(),
            );
          },
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
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.5),
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
