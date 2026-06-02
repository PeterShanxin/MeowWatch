import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import 'idle_mascot.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({required this.onBrowse, this.notice, super.key});

  final VoidCallback onBrowse;

  /// Optional heads-up shown above the prompt, e.g. "lin started playback —
  /// load a video to join" when a friend is already watching (#60).
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Container(
      color: m.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notice != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: m.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: m.accent),
                ),
                child: Text(
                  '🐾 $notice',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: m.textPrimary, fontSize: 14),
                ),
              ),
              const SizedBox(height: 28),
            ],
            const IdleMascot(size: 104),
            const SizedBox(height: 20),
            Text(
              'Drop a video file to start',
              style: TextStyle(color: m.textPrimary, fontSize: 18),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: m.accent,
                side: BorderSide(color: m.accent),
              ),
              onPressed: onBrowse,
              child: const Text('Browse…'),
            ),
          ],
        ),
      ),
    );
  }
}
