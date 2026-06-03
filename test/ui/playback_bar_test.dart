import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/ui/playback_bar.dart';

const _sample = PlaybackState(
  status: PlaybackStatus.paused,
  position: Duration(minutes: 1),
  duration: Duration(minutes: 5),
  fileName: 'movie.mkv',
);

void main() {
  testWidgets('shows current position and total duration', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          state: _sample,
          onSeek: (_) {},
          onTogglePlay: () {},
          onToggleMute: () {},
        ),
      ),
    ));
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
  });

  testWidgets('play/pause button fires onTogglePlay', (tester) async {
    var toggled = false;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          state: _sample,
          onSeek: (_) {},
          onTogglePlay: () => toggled = true,
          onToggleMute: () {},
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(toggled, isTrue);
  });

  testWidgets('volume button fires onToggleMute', (tester) async {
    var muted = false;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          state: _sample,
          onSeek: (_) {},
          onTogglePlay: () {},
          onToggleMute: () => muted = true,
        ),
      ),
    ));
    // _sample leaves volume at its 1.0 default → "up" icon.
    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    expect(muted, isTrue);
  });

  testWidgets('volume icon reflects the current level', (tester) async {
    Future<void> pumpAt(double volume) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: PlaybackBar(
            state: _sample.copyWith(volume: volume),
            onSeek: (_) {},
            onTogglePlay: () {},
            onToggleMute: () {},
          ),
        ),
      ));
    }

    await pumpAt(0.0);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await pumpAt(0.3);
    expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);

    await pumpAt(0.9);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });
}
