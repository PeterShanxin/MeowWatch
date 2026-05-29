import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';

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
            Icon(Icons.movie_outlined, size: 64, color: m.accent),
            const SizedBox(height: 16),
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
