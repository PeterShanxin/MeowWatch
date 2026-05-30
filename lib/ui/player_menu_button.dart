import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import 'theme/theme_swatches.dart';

/// Top-left in-player control: a gear button that opens a small anchored
/// popover with the room code (copyable), who's in the room, a "Load video"
/// action, theme swatches, and "Leave room".
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({
    required this.roomCode,
    required this.members,
    required this.myUsername,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onLoadVideo,
    required this.onLeave,
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

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child:
              Text(text, style: TextStyle(color: m.textDim, fontSize: 13)),
        );

    return MenuAnchor(
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
        SizedBox(
          width: 232,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Room code'),
              _RoomCodeRow(code: roomCode),
              const SizedBox(height: 8),
              Divider(color: m.border, height: 16),
              label('In the room (${members.length})'),
              for (final name in members)
                _MemberRow(name: name, isMe: name == myUsername),
              const SizedBox(height: 8),
              Divider(color: m.border, height: 16),
              _MenuAction(
                key: const Key('player-menu-load'),
                icon: Icons.video_library_outlined,
                text: 'Load video…',
                onTap: onLoadVideo,
              ),
              Divider(color: m.border, height: 16),
              label('Theme'),
              ThemeSwatches(current: currentTheme, onChanged: onThemeChanged),
              const SizedBox(height: 8),
              Divider(color: m.border, height: 16),
              _MenuAction(
                key: const Key('player-menu-leave'),
                icon: Icons.arrow_back,
                text: 'Leave room',
                onTap: onLeave,
              ),
            ],
          ),
        ),
      ],
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
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        // Close the popover first: a raw InkWell (unlike MenuItemButton) leaves
        // the menu open, and the open menu's FocusScope traps keyboard focus —
        // so after "Load video…" the video can't receive space/play. Dismissing
        // returns focus to the player.
        MenuController.maybeOf(context)?.close();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: m.textPrimary),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: m.textPrimary, fontSize: 13)),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: m.online, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isMe ? '$name (you)' : name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: m.textPrimary, fontSize: 13),
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.code,
              style: TextStyle(
                color: m.textPrimary,
                fontSize: 15,
                fontFamily: 'monospace',
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 10),
            // Fixed-size slot so flipping copy→check never reflows the row.
            Icon(_copied ? Icons.check : Icons.copy,
                size: 15, color: _copied ? m.online : m.accent),
          ],
        ),
      ),
    );
  }
}
