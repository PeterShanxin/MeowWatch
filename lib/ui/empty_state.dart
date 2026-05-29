import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import 'idle_mascot.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({required this.onBrowse, super.key});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Container(
      color: m.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
