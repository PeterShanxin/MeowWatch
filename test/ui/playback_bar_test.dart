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
  testWidgets('no theme toggle when theme params are absent', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          state: _sample,
          onSeek: (_) {},
          onTogglePlay: () {},
        ),
      ),
    ));
    expect(find.byKey(const Key('playback-theme-toggle')), findsNothing);
  });

  testWidgets('theme button cycles to the next preset', (tester) async {
    MeowThemeId? next;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          state: _sample,
          onSeek: (_) {},
          onTogglePlay: () {},
          currentTheme: MeowThemeId.cozy,
          onThemeChanged: (id) => next = id,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('playback-theme-toggle')));
    expect(next, MeowThemeId.noir); // cozy -> noir -> aurora -> cozy
  });

  testWidgets('theme button wraps aurora back to cozy', (tester) async {
    MeowThemeId? next;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.aurora),
      home: Scaffold(
        body: PlaybackBar(
          state: _sample,
          onSeek: (_) {},
          onTogglePlay: () {},
          currentTheme: MeowThemeId.aurora,
          onThemeChanged: (id) => next = id,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('playback-theme-toggle')));
    expect(next, MeowThemeId.cozy);
  });
}
