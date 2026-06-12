import 'package:flutter/material.dart';

import '../../core/debug/log_level.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';
import '../theme/theme_swatches.dart';
import 'settings_panel.dart';

/// Top-right gear on the connect/lobby screen: opens an anchored popover with
/// the settings you can change before joining a room — theme, notification
/// sounds, and diagnostic logging + export. It is deliberately settings-only;
/// the room rows (code, members, Leave, Load video) belong to the in-player
/// [PlayerMenuButton]. Presentational: values in, callbacks out — the connect
/// screen owns the state and persistence, mirroring how `HomeScreen` drives the
/// in-room gear.
class LobbySettingsButton extends StatefulWidget {
  const LobbySettingsButton({
    required this.currentTheme,
    required this.onThemeChanged,
    required this.primarySoundId,
    required this.onPrimarySoundChanged,
    required this.secondarySoundId,
    required this.onSecondarySoundChanged,
    required this.onPreviewSound,
    required this.logLevel,
    required this.onLogLevelChanged,
    required this.onExportLogs,
    super.key,
  });

  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final String primarySoundId;
  final ValueChanged<String> onPrimarySoundChanged;
  final String secondarySoundId;
  final ValueChanged<String> onSecondarySoundChanged;
  final ValueChanged<String> onPreviewSound;
  final LogLevel logLevel;
  final ValueChanged<LogLevel> onLogLevelChanged;
  final VoidCallback onExportLogs;

  @override
  State<LobbySettingsButton> createState() => _LobbySettingsButtonState();
}

class _LobbySettingsButtonState extends State<LobbySettingsButton> {
  // Own the scroll position so the popover never grabs the PrimaryScrollController
  // (which the desktop Scrollbar asserts must back a single ScrollView).
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(m.surface),
        side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: m.border)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
        ),
      ),
      builder: (context, controller, _) => Material(
        color: m.background.withValues(alpha: 0.80),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
          side: BorderSide(color: m.border),
        ),
        child: IconButton(
          key: const Key('lobby-settings-gear'),
          tooltip: 'Settings',
          icon: Icon(Icons.settings, size: IconSizes.md, color: m.textPrimary),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
      menuChildren: [
        // Entrance: fade + a small downward slide each time the menu opens, to
        // match the in-player gear.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 160),
          curve: Motion.standard,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -6),
              child: child,
            ),
          ),
          child: _panel(context),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final m = context.meow;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        text,
        style: TextStyle(color: m.textDim, fontSize: TypeScale.label),
      ),
    );

    return SizedBox(
      width: 264,
      // Cap to the window and scroll, so the lower controls (logging + export)
      // stay reachable on short windows instead of clipping off-screen.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height - 120,
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label('Theme'),
              Center(
                child: ThemeSwatches(
                  current: widget.currentTheme,
                  onChanged: widget.onThemeChanged,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Divider(color: m.border, height: Spacing.lg),
              SettingsPanel(
                primarySoundId: widget.primarySoundId,
                onPrimarySoundChanged: widget.onPrimarySoundChanged,
                secondarySoundId: widget.secondarySoundId,
                onSecondarySoundChanged: widget.onSecondarySoundChanged,
                onPreviewSound: widget.onPreviewSound,
                logLevel: widget.logLevel,
                onLogLevelChanged: widget.onLogLevelChanged,
                onExportLogs: widget.onExportLogs,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
