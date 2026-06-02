import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/audio/notify_sounds.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import 'idle_visibility.dart';
import 'theme/theme_swatches.dart';

/// Top-left in-player control: a gear button that opens a small anchored
/// popover with the room code (copyable), who's in the room, a "Load video"
/// action, theme swatches, a collapsible Settings section, and "Leave room".
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({
    required this.roomCode,
    required this.members,
    required this.myUsername,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onLoadVideo,
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
    super.key,
  });

  final String roomCode;

  /// Everyone in the room (including you).
  final List<String> members;
  final String myUsername;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final VoidCallback onLoadVideo;
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
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.fromLTRB(14, 12, 14, 8),
        ),
      ),
      builder: (context, controller, _) => Material(
        color: m.background.withValues(alpha: 0.80),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: m.border),
        ),
        child: IconButton(
          key: const Key('player-menu-gear'),
          tooltip: 'Options',
          icon: Icon(Icons.settings, size: 18, color: m.textPrimary),
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
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -6),
              child: child,
            ),
          ),
          child: _MenuPanel(
            roomCode: roomCode,
            members: members,
            myUsername: myUsername,
            currentTheme: currentTheme,
            onThemeChanged: onThemeChanged,
            onLoadVideo: onLoadVideo,
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
    required this.members,
    required this.myUsername,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onLoadVideo,
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
  });

  final String roomCode;
  final List<String> members;
  final String myUsername;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final VoidCallback onLoadVideo;
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

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  bool _settingsOpen = false;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: TextStyle(color: m.textDim, fontSize: 14)),
        );

    return SizedBox(
      width: 264,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // Stretch so rows/actions fill the card width (bigger tap targets)
        // instead of hugging the left as half-width nubs.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label('Room code'),
          _RoomCodeRow(code: widget.roomCode),
          const SizedBox(height: 8),
          Divider(color: m.border, height: 16),
          label('In the room (${widget.members.length})'),
          for (final name in widget.members)
            _MemberRow(name: name, isMe: name == widget.myUsername),
          const SizedBox(height: 8),
          Divider(color: m.border, height: 16),
          _MenuAction(
            key: const Key('player-menu-load'),
            icon: Icons.video_library_outlined,
            text: 'Load video…',
            onTap: widget.onLoadVideo,
          ),
          Divider(color: m.border, height: 16),
          label('Theme'),
          Center(
            child: ThemeSwatches(
              current: widget.currentTheme,
              onChanged: widget.onThemeChanged,
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: m.border, height: 16),
          // Collapsible Settings — keeps the menu short until you want the
          // chat-dim controls.
          _SectionHeader(
            key: const Key('player-menu-settings'),
            text: 'Settings',
            expanded: _settingsOpen,
            onTap: () => setState(() => _settingsOpen = !_settingsOpen),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
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
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: widget.chatAutoDim
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _MenuSwitch(
                                    text: 'Fully wake chat on message',
                                    value: widget.chatWakeOnMessage,
                                    onChanged: widget.onChatWakeOnMessageChanged,
                                  ),
                                  _DimSlider(
                                    value: widget.chatIdleDim,
                                    onChanged: widget.onChatIdleDimChanged,
                                  ),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      const SizedBox(height: 4),
                      SoundPickerRow(
                        key: const Key('primary-sound-picker'),
                        title: 'Notification sound',
                        options: kPrimarySounds,
                        currentId: widget.primarySoundId,
                        onChanged: widget.onPrimarySoundChanged,
                        onPreview: widget.onPreviewSound,
                      ),
                      SoundPickerRow(
                        key: const Key('secondary-sound-picker'),
                        title: 'Quiet sound (chat hidden)',
                        options: kSecondarySounds,
                        currentId: widget.secondarySoundId,
                        onChanged: widget.onSecondarySoundChanged,
                        onPreview: widget.onPreviewSound,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          Divider(color: m.border, height: 16),
          _MenuAction(
            key: const Key('player-menu-leave'),
            icon: Icons.arrow_back,
            text: 'Leave room',
            onTap: widget.onLeave,
          ),
        ],
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
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            Text(text, style: TextStyle(color: m.textDim, fontSize: 14)),
            const Spacer(),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, size: 18, color: m.textDim),
            ),
          ],
        ),
      ),
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
  String get _slug =>
      (key is ValueKey<String>) ? (key! as ValueKey<String>).value : 'sound-picker';

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final current = options.firstWhere(
      (s) => s.id == currentId,
      orElse: () => options.first,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: m.textDim, fontSize: 13)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: Key('$_slug-dropdown'),
                    value: current.id,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: m.surface,
                    iconEnabledColor: m.accent,
                    style: TextStyle(color: m.textPrimary, fontSize: 15),
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
            icon: Icon(Icons.play_circle_outline, size: 20, color: m.accent),
            onPressed: () => onPreview(current.asset),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dimmed chat readability',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: m.textDim, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(_v * 100).round()}%',
                style: TextStyle(color: m.textPrimary, fontSize: 13),
              ),
              // Reset to the default opacity.
              IconButton(
                key: const Key('player-menu-dim-reset'),
                tooltip: 'Reset',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.restart_alt, size: 16, color: m.accent),
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
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        // Close the popover first: a raw InkWell (unlike MenuItemButton) leaves
        // the menu open, and the open menu's FocusScope traps keyboard focus —
        // so after "Load video…" the video can't receive space/play. Dismissing
        // returns focus to the player.
        MenuController.maybeOf(context)?.close();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: m.textPrimary),
            const SizedBox(width: 12),
            Text(text, style: TextStyle(color: m.textPrimary, fontSize: 15)),
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
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(text, style: TextStyle(color: m.textPrimary, fontSize: 15))),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
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
              style: TextStyle(color: m.textPrimary, fontSize: 15),
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
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: m.surface,
        duration: const Duration(seconds: 2),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 18, color: m.online),
            const SizedBox(width: 10),
            Text('Room code ${widget.code} copied',
                style: TextStyle(color: m.textPrimary)),
          ],
        ),
      ));
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
      borderRadius: BorderRadius.circular(8),
      onTap: _copy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                widget.code,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: m.textPrimary,
                  fontSize: 18,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Fixed-size slot so flipping copy→check never reflows the row.
            Icon(_copied ? Icons.check : Icons.copy,
                size: 18, color: _copied ? m.online : m.accent),
          ],
        ),
      ),
    );
  }
}
