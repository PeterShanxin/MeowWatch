import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({required this.onBrowse, super.key});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1410),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_outlined,
                size: 64, color: Color(0xFFD4A574)),
            const SizedBox(height: 16),
            const Text(
              'Drop a video file to start',
              style: TextStyle(color: Color(0xFFF5E6D3), fontSize: 18),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD4A574),
                side: const BorderSide(color: Color(0xFFD4A574)),
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
