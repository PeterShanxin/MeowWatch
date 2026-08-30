import 'package:flutter/material.dart';

import '../../core/audio/notify_sounds.dart';
import '../../core/data/history_mode.dart';
import '../../core/debug/log_level.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';

/// The settings that aren't tied to an open room: notification sounds and the
/// diagnostic-log level + export. Shared verbatim between the in-player gear
/// (`PlayerMenuButton`) and the lobby gear (`LobbySettingsButton`) so both
/// surfaces stay in lockstep. Chat-dim controls live only in the player gear —
/// there is no chat overlay to tune from the lobby.
///
/// Keys keep the `player-menu-` prefix the in-room menu has always used so its
/// tests stay stable; only one `SettingsPanel` is ever mounted at a time.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    required this.historyMode,
    required this.onHistoryModeChanged,
    required this.primarySoundId,
    required this.onPrimarySoundChanged,
    required this.secondarySoundId,
    required this.onSecondarySoundChanged,
    required this.onPreviewSound,
    required this.logLevel,
    required this.onLogLevelChanged,
    required this.onExportLogs,
    this.localPlayerMode,
    this.onLocalPlayerModeChanged,
    super.key,
  });

  /// When both are set, the lobby gear shows the Local Player Mode toggle.
  /// The in-room gear leaves these null — switching mid-session is not a thing.
  final bool? localPlayerMode;
  final ValueChanged<bool>? onLocalPlayerModeChanged;

  final HistoryMode historyMode;
  final ValueChanged<HistoryMode> onHistoryModeChanged;
  final String primarySoundId;
  final ValueChanged<String> onPrimarySoundChanged;
  final String secondarySoundId;
  final ValueChanged<String> onSecondarySoundChanged;
  final ValueChanged<String> onPreviewSound;
  final LogLevel logLevel;
  final ValueChanged<LogLevel> onLogLevelChanged;
  final VoidCallback onExportLogs;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (localPlayerMode != null && onLocalPlayerModeChanged != null) ...[
          LocalPlayerModeControl(
            value: localPlayerMode!,
            onChanged: onLocalPlayerModeChanged!,
          ),
          Divider(color: m.border, height: Spacing.lg),
        ],
        HistoryModeControl(value: historyMode, onChanged: onHistoryModeChanged),
        Divider(color: m.border, height: Spacing.lg),
        SoundPickerRow(
          key: const Key('primary-sound-picker'),
          title: 'Notification sound',
          options: kPrimarySounds,
          currentId: primarySoundId,
          onChanged: onPrimarySoundChanged,
          onPreview: onPreviewSound,
        ),
        SoundPickerRow(
          key: const Key('secondary-sound-picker'),
          title: 'Quiet sound (chat hidden)',
          options: kSecondarySounds,
          currentId: secondarySoundId,
          onChanged: onSecondarySoundChanged,
          onPreview: onPreviewSound,
        ),
        Divider(color: m.border, height: Spacing.lg),
        LogLevelControl(value: logLevel, onChanged: onLogLevelChanged),
        _ExportLogsAction(
          key: const Key('player-menu-export-logs'),
          onTap: onExportLogs,
        ),
      ],
    );
  }
}

/// A labelled dropdown of notify-sound presets with a ▶ preview button.
/// Picking fires [onChanged] with the preset id; preview fires [onPreview] with
/// the selected preset's asset URI. Public so it can be unit-tested directly.
class SoundPickerRow extends StatelessWidget {
  const SoundPickerRow({
    required this.title,
    required this.options,
    required this.currentId,
    required this.onChanged,
    required this.onPreview,
    super.key,
  });

  final String title;
  final List<NotifySound> options;
  final String currentId;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onPreview;

  // Key prefix derived from the widget's own Key so the dropdown/preview child
  // keys are stable and match tests (e.g. 'primary-sound-picker').
  String get _slug => (key is ValueKey<String>)
      ? (key! as ValueKey<String>).value
      : 'sound-picker';

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final current = options.firstWhere(
      (s) => s.id == currentId,
      orElse: () => options.first,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: Key('$_slug-dropdown'),
                    value: current.id,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: m.surface,
                    iconEnabledColor: m.accent,
                    style: TextStyle(
                      color: m.textPrimary,
                      fontSize: TypeScale.label,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final s in options)
                        DropdownMenuItem<String>(
                          value: s.id,
                          child: Text(s.label),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) onChanged(id);
                    },
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('$_slug-preview'),
            tooltip: 'Preview',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.play_circle_outline,
              size: IconSizes.md,
              color: m.accent,
            ),
            onPressed: () => onPreview(current.asset),
          ),
        ],
      ),
    );
  }
}

/// Lobby-only switch: watch alone without opening a Syncplay room. Public so
/// it can be unit-tested directly.
class LocalPlayerModeControl extends StatelessWidget {
  const LocalPlayerModeControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local Player Mode',
                  style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
                ),
                Text(
                  'Start watching without a room',
                  style: TextStyle(
                    color: m.textDim.withValues(alpha: 0.8),
                    fontSize: TypeScale.label,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('local-player-mode-toggle'),
            value: value,
            onChanged: onChanged,
            activeTrackColor: m.accent.withValues(alpha: 0.5),
            activeThumbColor: m.accent,
          ),
        ],
      ),
    );
  }
}

/// Two-way continue-watching mode picker (Latest per room / Every video) shown
/// as a labelled segmented row, matching [LogLevelControl]. Picking a segment
/// fires [onChanged]. Public so it can be unit-tested directly.
class HistoryModeControl extends StatelessWidget {
  const HistoryModeControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final HistoryMode value;
  final ValueChanged<HistoryMode> onChanged;

  static const Map<HistoryMode, String> _labels = <HistoryMode, String>{
    HistoryMode.latestPerRoom: 'Latest per room',
    HistoryMode.everyVideo: 'Every video',
  };

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Continue watching',
            style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              for (final mode in HistoryMode.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: mode == HistoryMode.everyVideo ? 0 : Spacing.xs,
                    ),
                    child: _LogLevelSegment(
                      key: Key('history-mode-${mode.storageName}'),
                      text: _labels[mode]!,
                      selected: mode == value,
                      onTap: () => onChanged(mode),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Three-way diagnostic-log verbosity picker (Off / Neat / Verbose) shown as a
/// labelled segmented row. Picking a segment fires [onChanged]. Public so it
/// can be unit-tested directly.
class LogLevelControl extends StatelessWidget {
  const LogLevelControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final LogLevel value;
  final ValueChanged<LogLevel> onChanged;

  static const Map<LogLevel, String> _labels = <LogLevel, String>{
    LogLevel.off: 'Off',
    LogLevel.neat: 'Neat',
    LogLevel.verbose: 'Verbose',
  };

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diagnostic logging',
            style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              for (final level in LogLevel.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: level == LogLevel.verbose ? 0 : Spacing.xs,
                    ),
                    child: _LogLevelSegment(
                      key: Key('player-menu-log-${level.storageName}'),
                      text: _labels[level]!,
                      selected: level == value,
                      onTap: () => onChanged(level),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogLevelSegment extends StatelessWidget {
  const _LogLevelSegment({
    required this.text,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? m.accent.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: selected ? m.accent : m.border),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? m.accent : m.textDim,
            fontSize: TypeScale.label,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// The "Export logs…" row. Closes the enclosing menu (if any) before firing, so
/// the gear popover dismisses as the save dialog opens.
class _ExportLogsAction extends StatelessWidget {
  const _ExportLogsAction({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () {
        MenuController.maybeOf(context)?.close();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.ios_share, size: IconSizes.md, color: m.textPrimary),
            const SizedBox(width: Spacing.md),
            Text(
              'Export logs…',
              style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
            ),
          ],
        ),
      ),
    );
  }
}
