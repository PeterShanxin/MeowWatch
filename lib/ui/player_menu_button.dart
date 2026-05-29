import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import 'theme/theme_swatches.dart';

/// Top-left in-player control: a gear button that opens a small anchored
/// popover holding the room code (copyable), theme swatches, and a
/// "Leave room" action. Replaces the bare Leave button so theme switching is a
/// deliberate pick (not a blind cycle) while watching.
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({
    required this.roomCode,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onLeave,
    super.key,
  });

  final String roomCode;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
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
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Room code',
                  style: TextStyle(color: m.textDim, fontSize: 13)),
            ),
            _RoomCodeRow(code: roomCode),
            const SizedBox(height: 8),
            Divider(color: m.border, height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Theme',
                  style: TextStyle(color: m.textDim, fontSize: 13)),
            ),
            ThemeSwatches(current: currentTheme, onChanged: onThemeChanged),
            const SizedBox(height: 8),
            Divider(color: m.border, height: 16),
            InkWell(
              key: const Key('player-menu-leave'),
              borderRadius: BorderRadius.circular(8),
              onTap: onLeave,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 16, color: m.textPrimary),
                    const SizedBox(width: 8),
                    Text('Leave room',
                        style: TextStyle(color: m.textPrimary, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The room code shown in monospace next to a copy button that briefly flips
/// to a check + "Copied!" so the tap feels acknowledged.
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
            Icon(_copied ? Icons.check : Icons.copy,
                size: 15, color: _copied ? m.online : m.accent),
            if (_copied) ...[
              const SizedBox(width: 4),
              Text('Copied!',
                  style: TextStyle(color: m.online, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
