import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/debug/log_level.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/motion.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import 'idle_visibility.dart';
import 'settings/settings_panel.dart';
import 'theme/theme_swatches.dart';

/// Top-left in-player control: a gear button that opens a small anchored
/// popover with the room code (copyable), who's in the room, a "Load video"
/// action, theme swatches, a collapsible Settings section, and "Leave room".
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({
    required this.roomCode,
    required this.nowPlaying,
    required this.members,
    required this.myUsername,
    required this.myDisplayName,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onLoadVideo,
    required this.onPasteLink,
    required this.onLeave,
    required this.chatAutoDim,
    required this.onChatAutoDimChanged,
    required this.chatWakeOnMessage,
    required this.onChatWakeOnMessageChanged,
    required this.chatIdleDim,
    required this.onChatIdleDimChanged,
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

  final String roomCode;

  /// Display name of the currently loaded media, or null when nothing is
  /// loaded. Shown as a "Now playing" line so anyone in the room can confirm
  /// which episode/video is active (#133).
  final String? nowPlaying;

  /// Everyone in the room (including you), keyed by their server-assigned wire
  /// identity — what self-filtering, chat-echo ownership, and peer roster all
  /// agree on. May briefly include a phantom of our own old name after a
  /// reconnect (#100), so dedupe/identity must stay on these wire names.
  final List<String> members;

  /// Our wire identity in [members] (server-assigned). Used to pick the "you"
  /// row — NOT for what that row displays. After a reconnect against a lingering
  /// ghost this can carry a dedupe suffix ("meow" -> "meow_").
  final String myUsername;

  /// The name we actually chose, shown for the "you" row instead of the wire
  /// [myUsername] so a transient reconnect suffix never surfaces to us (#107).
  final String myDisplayName;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final VoidCallback onLoadVideo;
  final VoidCallback onPasteLink;
  final VoidCallback onLeave;
  final bool chatAutoDim;
  final ValueChanged<bool> onChatAutoDimChanged;
  final bool chatWakeOnMessage;
  final ValueChanged<bool> onChatWakeOnMessageChanged;

  /// Current idle-dim opacity and a setter; tunes how readable the dimmed chat
  /// card stays while idle.
  final double chatIdleDim;
  final ValueChanged<double> onChatIdleDimChanged;

  /// Selected notification-sound preset ids and their setters, plus a preview
  /// callback that plays a preset's asset URI on demand.
  final String primarySoundId;
  final ValueChanged<String> onPrimarySoundChanged;
  final String secondarySoundId;
  final ValueChanged<String> onSecondarySoundChanged;
  final ValueChanged<String> onPreviewSound;

  /// Diagnostic-log verbosity and its setter, plus a one-tap export that
  /// bundles the rotating logs to a file the user can send us.
  final LogLevel logLevel;
  final ValueChanged<LogLevel> onLogLevelChanged;
  final VoidCallback onExportLogs;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return MenuAnchor(
      // Drop the popover a touch below the gear so it doesn't crowd the button.
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
          key: const Key('player-menu-gear'),
          tooltip: 'Options',
          icon: Icon(Icons.settings, size: IconSizes.md, color: m.textPrimary),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
      menuChildren: [
        // Entrance: fade + a small downward slide each time the menu opens (the
        // overlay remounts on open, so the tween replays). MenuAnchor itself
        // pops the panel in with no transition otherwise.
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
          child: _MenuPanel(
            roomCode: roomCode,
            nowPlaying: nowPlaying,
            members: members,
            myUsername: myUsername,
            myDisplayName: myDisplayName,
            currentTheme: currentTheme,
            onThemeChanged: onThemeChanged,
            onLoadVideo: onLoadVideo,
            onPasteLink: onPasteLink,
            onLeave: onLeave,
            chatAutoDim: chatAutoDim,
            onChatAutoDimChanged: onChatAutoDimChanged,
            chatWakeOnMessage: chatWakeOnMessage,
            onChatWakeOnMessageChanged: onChatWakeOnMessageChanged,
            chatIdleDim: chatIdleDim,
            onChatIdleDimChanged: onChatIdleDimChanged,
            primarySoundId: primarySoundId,
            onPrimarySoundChanged: onPrimarySoundChanged,
            secondarySoundId: secondarySoundId,
            onSecondarySoundChanged: onSecondarySoundChanged,
            onPreviewSound: onPreviewSound,
            logLevel: logLevel,
            onLogLevelChanged: onLogLevelChanged,
            onExportLogs: onExportLogs,
          ),
        ),
      ],
    );
  }
}

/// The popover body. Stateful only to remember whether the collapsible Settings
/// section is expanded for the current open session.
class _MenuPanel extends StatefulWidget {
  const _MenuPanel({
    required this.roomCode,
    required this.nowPlaying,
    required this.members,
    required this.myUsername,
    required this.myDisplayName,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onLoadVideo,
    required this.onPasteLink,
    required this.onLeave,
    required this.chatAutoDim,
    required this.onChatAutoDimChanged,
    required this.chatWakeOnMessage,
    required this.onChatWakeOnMessageChanged,
    required this.chatIdleDim,
    required this.onChatIdleDimChanged,
    required this.primarySoundId,
    required this.onPrimarySoundChanged,
    required this.secondarySoundId,
    required this.onSecondarySoundChanged,
    required this.onPreviewSound,
    required this.logLevel,
    required this.onLogLevelChanged,
    required this.onExportLogs,
  });

  final String roomCode;
  final String? nowPlaying;
  final List<String> members;
  final String myUsername;
  final String myDisplayName;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final VoidCallback onLoadVideo;
  final VoidCallback onPasteLink;
  final VoidCallback onLeave;
  final bool chatAutoDim;
  final ValueChanged<bool> onChatAutoDimChanged;
  final bool chatWakeOnMessage;
  final ValueChanged<bool> onChatWakeOnMessageChanged;
  final double chatIdleDim;
  final ValueChanged<double> onChatIdleDimChanged;
  final String primarySoundId;
  final ValueChanged<String> onPrimarySoundChanged;
  final String secondarySoundId;
  final ValueChanged<String> onSecondarySoundChanged;
  final ValueChanged<String> onPreviewSound;
  final LogLevel logLevel;
  final ValueChanged<LogLevel> onLogLevelChanged;
  final VoidCallback onExportLogs;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  bool _settingsOpen = false;

  // Own the scroll position so this popover never grabs the PrimaryScrollController
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
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        text,
        style: TextStyle(color: m.textDim, fontSize: TypeScale.label),
      ),
    );

    return SizedBox(
      width: 264,
      // Cap the popover to the window and let it scroll, so the controls near
      // the bottom (diagnostic-log level + Export) stay reachable on short
      // windows instead of clipping off-screen.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height - 120,
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // Stretch so rows/actions fill the card width (bigger tap targets)
            // instead of hugging the left as half-width nubs.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label('Room code'),
              _RoomCodeRow(code: widget.roomCode),
              const SizedBox(height: Spacing.sm),
              Divider(color: m.border, height: Spacing.lg),
              label('Now playing'),
              _NowPlayingRow(fileName: widget.nowPlaying),
              const SizedBox(height: Spacing.sm),
              Divider(color: m.border, height: Spacing.lg),
              label('In the room (${widget.members.length})'),
              for (final name in widget.members)
                // isMe matches the wire identity; the matched "you" row renders our
                // chosen name so a transient reconnect dedupe suffix never shows (#107).
                _MemberRow(
                  name: name == widget.myUsername ? widget.myDisplayName : name,
                  isMe: name == widget.myUsername,
                ),
              const SizedBox(height: Spacing.sm),
              Divider(color: m.border, height: Spacing.lg),
              _MenuAction(
                key: const Key('player-menu-load'),
                icon: Icons.video_library_outlined,
                text: 'Load video…',
                onTap: widget.onLoadVideo,
              ),
              _MenuAction(
                key: const Key('player-menu-paste-link'),
                icon: Icons.link,
                text: 'Paste link…',
                onTap: widget.onPasteLink,
              ),
              Divider(color: m.border, height: Spacing.lg),
              label('Theme'),
              Center(
                child: ThemeSwatches(
                  current: widget.currentTheme,
                  onChanged: widget.onThemeChanged,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Divider(color: m.border, height: Spacing.lg),
              // Collapsible Settings — keeps the menu short until you want the
              // chat-dim controls.
              _SectionHeader(
                key: const Key('player-menu-settings'),
                text: 'Settings',
                expanded: _settingsOpen,
                onTap: () => setState(() => _settingsOpen = !_settingsOpen),
              ),
              AnimatedSize(
                duration: Motion.base,
                curve: Motion.symmetric,
                alignment: Alignment.topCenter,
                child: _settingsOpen
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _MenuSwitch(
                            text: 'Dim chat when idle',
                            value: widget.chatAutoDim,
                            onChanged: widget.onChatAutoDimChanged,
                          ),
                          // The wake toggle + dim slider only mean something while
                          // auto-dim is on; reveal/collapse them smoothly (#51).
                          AnimatedSize(
                            duration: Motion.base,
                            curve: Motion.symmetric,
                            alignment: Alignment.topCenter,
                            child: widget.chatAutoDim
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _MenuSwitch(
                                        text: 'Fully wake chat on message',
                                        value: widget.chatWakeOnMessage,
                                        onChanged:
                                            widget.onChatWakeOnMessageChanged,
                                      ),
                                      _DimSlider(
                                        value: widget.chatIdleDim,
                                        onChanged: widget.onChatIdleDimChanged,
                                      ),
                                    ],
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          const SizedBox(height: Spacing.xs),
                          SettingsPanel(
                            primarySoundId: widget.primarySoundId,
                            onPrimarySoundChanged: widget.onPrimarySoundChanged,
                            secondarySoundId: widget.secondarySoundId,
                            onSecondarySoundChanged:
                                widget.onSecondarySoundChanged,
                            onPreviewSound: widget.onPreviewSound,
                            logLevel: widget.logLevel,
                            onLogLevelChanged: widget.onLogLevelChanged,
                            onExportLogs: widget.onExportLogs,
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
              Divider(color: m.border, height: Spacing.lg),
              _MenuAction(
                key: const Key('player-menu-leave'),
                icon: Icons.arrow_back,
                text: 'Leave room',
                onTap: widget.onLeave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable section header with a rotating chevron, used to expand/collapse
/// the Settings group.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.text,
    required this.expanded,
    required this.onTap,
    super.key,
  });

  final String text;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            Text(
              text,
              style: TextStyle(color: m.textDim, fontSize: TypeScale.label),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: Motion.base,
              child: Icon(
                Icons.expand_more,
                size: IconSizes.md,
                color: m.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slider for the idle-dim opacity, with a live percentage and a reset button
/// back to the default. Keeps a local value so dragging is smooth and only
/// commits on release (no settings write per tick).
class _DimSlider extends StatefulWidget {
  const _DimSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_DimSlider> createState() => _DimSliderState();
}

class _DimSliderState extends State<_DimSlider> {
  late double _v = widget.value;

  @override
  void didUpdateWidget(_DimSlider old) {
    super.didUpdateWidget(old);
    // Adopt an external change (e.g. a reset) when we're not mid-drag.
    if (old.value != widget.value) _v = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.xs,
        Spacing.sm,
        Spacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dimmed chat readability',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '${(_v * 100).round()}%',
                style: TextStyle(
                  color: m.textPrimary,
                  fontSize: TypeScale.body,
                ),
              ),
              // Reset to the default opacity.
              IconButton(
                key: const Key('player-menu-dim-reset'),
                tooltip: 'Reset',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.restart_alt,
                  size: IconSizes.sm,
                  color: m.accent,
                ),
                onPressed: () {
                  setState(() => _v = kChatIdleGhostOpacity);
                  widget.onChanged(kChatIdleGhostOpacity);
                },
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: m.accent,
              inactiveTrackColor: m.border,
              thumbColor: m.accent,
              overlayColor: m.accent.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _v.clamp(kChatIdleDimMin, kChatIdleDimMax),
              min: kChatIdleDimMin,
              max: kChatIdleDimMax,
              onChanged: (v) => setState(() => _v = v),
              onChangeEnd: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable icon+label row used for the menu actions.
class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.text,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () {
        // Close the popover first: a raw InkWell (unlike MenuItemButton) leaves
        // the menu open, and the open menu's FocusScope traps keyboard focus —
        // so after "Load video…" the video can't receive space/play. Dismissing
        // returns focus to the player.
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
            Icon(icon, size: IconSizes.md, color: m.textPrimary),
            const SizedBox(width: Spacing.md),
            Text(
              text,
              style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable row with a toggle switch for menu settings.
class _MenuSwitch extends StatelessWidget {
  const _MenuSwitch({
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: m.textPrimary,
                  fontSize: TypeScale.label,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: m.accent.withValues(alpha: 0.5),
              activeThumbColor: m.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// One room member: a presence dot + name, with "(you)" for yourself.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.name, required this.isMe});

  final String name;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: m.online, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              isMe ? '$name (you)' : name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
            ),
          ),
        ],
      ),
    );
  }
}

/// The currently loaded media's name beside a film icon, or a dim "Nothing
/// loaded yet" when no file is open. The name wraps to two lines and ellipsizes
/// so a long filename never overflows or stretches the menu (#133).
class _NowPlayingRow extends StatelessWidget {
  const _NowPlayingRow({required this.fileName});

  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final name = fileName;
    final hasFile = name != null && name.isNotEmpty;
    return Padding(
      key: const Key('player-menu-now-playing'),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasFile ? Icons.movie_outlined : Icons.movie_filter_outlined,
            size: IconSizes.md,
            color: hasFile ? m.accent : m.textDim,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              hasFile ? name : 'Nothing loaded yet',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasFile ? m.textPrimary : m.textDim,
                fontSize: TypeScale.label,
                fontStyle: hasFile ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The room code in monospace next to a copy button. The button briefly flips
/// to a check; the words go to a SnackBar so the row never changes width.
class _RoomCodeRow extends StatefulWidget {
  const _RoomCodeRow({required this.code});

  final String code;

  @override
  State<_RoomCodeRow> createState() => _RoomCodeRowState();
}

class _RoomCodeRowState extends State<_RoomCodeRow> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    final m = context.meow;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: m.surface,
          duration: const Duration(seconds: 2),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: IconSizes.md, color: m.online),
              const SizedBox(width: Spacing.md),
              Text(
                'Room code ${widget.code} copied',
                style: TextStyle(color: m.textPrimary),
              ),
            ],
          ),
        ),
      );
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return InkWell(
      key: const Key('player-menu-room-code'),
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: _copy,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                widget.code,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: m.textPrimary,
                  fontSize: TypeScale.title,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            // Fixed-size slot so flipping copy→check never reflows the row.
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: IconSizes.md,
              color: _copied ? m.online : m.accent,
            ),
          ],
        ),
      ),
    );
  }
}
